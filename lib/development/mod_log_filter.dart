import 'dart:convert';

/// Source identities from the selected pack snapshots, never engine names.
class ModLogSources {
  ModLogSources({
    required Iterable<String> modules,
    required Iterable<String> paths,
    Iterable<String> identifiers = const [],
  }) : modules = modules.toSet(),
       _paths = paths.map(_normalize).where((s) => s.isNotEmpty).toSet(),
       _identifiers = identifiers.where((s) => s.contains(':')).toSet();

  final Set<String> modules;
  final Set<String> _paths;
  final Set<String> _identifiers;

  static String _normalize(String text) =>
      text.replaceAll('\\', '/').toLowerCase();

  bool ownsModule(String module) =>
      modules.any((root) => module == root || module.startsWith('$root.'));

  bool mentionsSource(String text) {
    final normalized = _normalize(text);
    if (_paths.any(normalized.contains)) return true;
    for (final module in modules) {
      if (RegExp(
        '(?<![a-zA-Z0-9_])${RegExp.escape(module)}(?=[./\\\\"\' :]|\$)',
      ).hasMatch(text)) {
        return true;
      }
    }
    return _identifiers.any(
      (id) => RegExp(
        '(?<![a-zA-Z0-9_.:-])${RegExp.escape(id)}(?![a-zA-Z0-9_.:-])',
      ).hasMatch(text),
    );
  }
}

/// Consumes the official developer stream. Prints are accepted only with a
/// session-specific marker emitted by the selected pack's stdout wrapper.
/// Unmarked tracebacks are kept only when a frame belongs to a selected pack.
class ModLogFilter {
  ModLogFilter({
    required this.marker,
    required this.sources,
    required this.onText,
  });

  final String marker;
  final ModLogSources sources;
  final void Function(String) onText;
  String _partial = '';
  final List<String> _traceback = [];
  int _tracebackLength = 0;
  bool _closed = false;
  static const _maxRecord = 256 * 1024;
  static final _exception = RegExp(r'^[A-Za-z_][\w.]*(?::|$)');
  static final _timestamp = RegExp(r'^\[\d{4}-\d\d-\d\d ');
  static final _frame = RegExp(r'^\s+File "([^"]+)"');
  static final _error = RegExp(
    r'\[(?:error|err|fatal|critical)\]|\b(?:Error|Exception):',
    caseSensitive: false,
  );

  void add(String text) {
    if (_closed) return;
    var cursor = 0;
    while (cursor < text.length) {
      final end = text.indexOf('\n', cursor);
      final stop = end < 0 ? text.length : end;
      _partial += text.substring(cursor, stop);
      // An unbounded engine record must never grow the launcher heap.
      if (_partial.length > _maxRecord) _partial = '';
      if (end < 0) return;
      _line(
        _partial.endsWith('\r')
            ? _partial.substring(0, _partial.length - 1)
            : _partial,
      );
      _partial = '';
      cursor = end + 1;
    }
  }

  void _line(String line) {
    if (line.startsWith('$marker:')) {
      final parts = line.substring(marker.length + 1).split(':');
      if (parts.length != 3 || (parts[0] != 'P' && parts[0] != 'E')) return;
      try {
        final module = utf8.decode(base64.decode(parts[1]));
        if (!sources.ownsModule(module)) return;
        final text = utf8.decode(base64.decode(parts[2]), allowMalformed: true);
        // Marked chunks can be part of a print (spaces, trailing commas,
        // multiline text). Preserve them exactly, even if they resemble logs.
        onText(text);
      } on FormatException {
        // Ignore malformed/foreign records rather than displaying engine data.
      }
      return;
    }
    if (line.startsWith('Traceback (most recent call last):')) {
      _flushTraceback();
      _traceback.add(line);
      _tracebackLength = line.length;
      return;
    }
    if (_traceback.isNotEmpty) {
      if (_timestamp.hasMatch(line) || line.startsWith('LoadWindowsAddonPy:')) {
        _flushTraceback();
      } else {
        _traceback.add(line);
        _tracebackLength += line.length;
        if (_exception.hasMatch(line) || _tracebackLength > _maxRecord) {
          _flushTraceback();
        }
        return;
      }
    }
    if (_error.hasMatch(line) && sources.mentionsSource(line)) {
      onText('$line\n');
    }
  }

  void _flushTraceback() {
    if (_traceback.any((line) {
      final frame = _frame.firstMatch(line);
      return frame != null && sources.mentionsSource(frame.group(1)!);
    })) {
      onText('${_traceback.join('\n')}\n');
    }
    _traceback.clear();
    _tracebackLength = 0;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_partial.isNotEmpty) _line(_partial);
    _partial = '';
    _flushTraceback();
  }
}

/// Native resource/JSON loading failures may not use the Python log socket.
/// Keep an entire native diagnostic only when it both reports an error and
/// names a selected pack/file/declared content identifier.
class ModNativeErrorFilter {
  ModNativeErrorFilter(this.sources, this.onText);
  final ModLogSources sources;
  final void Function(String) onText;
  String _partial = '';
  final List<String> _record = [];
  int _length = 0;
  bool _closed = false;
  static final _start = RegExp(
    r'^\[\d{4}-\d\d-\d\d [\d:, .]+(?:INFO|ERROR|WARN|DEBUG|TRACE|FATAL)\b',
  );
  static final _error = RegExp(
    r'\b(?:ERROR|FATAL)\b|\b(?:error|exception|failed|failure)\b|'
    r'could not be found|unable to (?:load|parse)|invalid (?:json|syntax)',
    caseSensitive: false,
  );

  void add(String text) {
    if (_closed) return;
    for (final piece in text.split('\n').indexed) {
      if (piece.$1 > 0) {
        _line(_partial);
        _partial = '';
      }
      _partial += piece.$2;
      if (_partial.length > 256 * 1024) _partial = '';
    }
  }

  void _line(String line) {
    // Python timestamp records are handled on the developer channel. Starting
    // one here ends the native block but never duplicates a Python traceback.
    if (RegExp(r'^\[\d{4}-\d\d-\d\d ').hasMatch(line)) {
      _flush();
      if (!_start.hasMatch(line)) return;
    }
    if (_record.isEmpty && !_start.hasMatch(line)) return;
    if (_record.isNotEmpty &&
        !_start.hasMatch(line) &&
        line.isNotEmpty &&
        !RegExp(r'^\s|^Error:|^Call stack:|^[{}\[\]]|^at \[').hasMatch(line)) {
      _flush();
      return;
    }
    _record.add(line);
    _length += line.length;
    // Native diagnostics end in a source frame or call-stack terminator. They
    // must not swallow unrelated raw prints that follow the diagnostic.
    if (line == ']' || line.startsWith('at [') || _length > 256 * 1024) {
      _flush();
    }
  }

  void _flush() {
    final text = _record.join('\n');
    if (_error.hasMatch(text) && sources.mentionsSource(text)) {
      onText('$text\n');
    }
    _record.clear();
    _length = 0;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_partial.isNotEmpty) _line(_partial);
    _partial = '';
    _flush();
  }
}
