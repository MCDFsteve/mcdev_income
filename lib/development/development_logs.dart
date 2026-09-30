import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'log_format.dart';
import 'log_store_stub.dart'
    if (dart.library.io) 'log_store_io.dart'
    as backend;

DevelopmentLogStore openDevelopmentLogs(String directory) =>
    backend.openDevelopmentLogs(directory);

class DevelopmentLogFile {
  const DevelopmentLogFile(this.path, this.modified, this.size);
  final String path;
  final DateTime modified;
  final int size;
  String get name => p.basename(path);
  String get label => '${name.startsWith('game-') ? '游戏' : 'Wine'} · $name';
}

class DevelopmentLogChunk {
  const DevelopmentLogChunk({
    required this.bytes,
    required this.nextOffset,
    this.reset = false,
    this.skippedBytes = 0,
  });
  final Uint8List bytes;
  final int nextOffset;
  final bool reset;
  final int skippedBytes;
}

abstract class DevelopmentLogStore {
  Future<List<DevelopmentLogFile>> list();
  Future<DevelopmentLogChunk> read(String path, {int? offset});
  Future<void> exportOriginal(String source, String destination);
  Future<void> exportText(String source, String destination, String text);
}

class DevelopmentLogEntry {
  const DevelopmentLogEntry(this.number, this.text, this.level);
  final int number;
  final String text;
  final DevelopmentLogLevel level;
}

/// Keeps a bounded tail and a streaming UTF-8 decoder, including incomplete
/// lines/code points. It never needs to reread a growing file in full.
class DevelopmentLogBuffer {
  DevelopmentLogBuffer({
    this.maxLines = 5000,
    this.maxCharacters = 2 * 1024 * 1024,
  }) {
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(_decoded));
  }
  final int maxLines;
  final int maxCharacters;
  final _decoded = StringBuffer();
  late ByteConversionSink _decoder;
  final _lines = <DevelopmentLogEntry>[];
  String _partial = '';
  int _number = 1;
  int _characters = 0;
  int droppedLines = 0;
  DevelopmentLogLevel _previousLevel = DevelopmentLogLevel.other;
  static final _ansi = RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]');

  List<DevelopmentLogEntry> get entries => [
    ..._lines,
    if (_partial.isNotEmpty)
      DevelopmentLogEntry(
        _number,
        _partial,
        classifyLogLine(_partial, continuation: _previousLevel),
      ),
  ];

  void add(Uint8List bytes) {
    _decoder.add(bytes);
    final text = _decoded.toString();
    _decoded.clear();
    final pieces = '$_partial$text'.replaceAll('\r', '').split('\n');
    for (final raw in pieces.take(pieces.length - 1)) {
      final line = raw.replaceAll(_ansi, '').replaceAll('\u0000', '');
      final level = classifyLogLine(line, continuation: _previousLevel);
      _lines.add(DevelopmentLogEntry(_number++, line, level));
      _previousLevel = level;
      _characters += line.length;
    }
    _partial = pieces.last.replaceAll(_ansi, '').replaceAll('\u0000', '');
    if (_partial.length > maxCharacters) {
      _partial = _partial.substring(_partial.length - maxCharacters);
      droppedLines++;
    }
    var remove = 0;
    while (remove < _lines.length &&
        (_lines.length - remove + (_partial.isEmpty ? 0 : 1) > maxLines ||
            _characters + _partial.length > maxCharacters)) {
      _characters -= _lines[remove++].text.length;
    }
    if (remove > 0) {
      _lines.removeRange(0, remove);
      droppedLines += remove;
    }
  }

  void close() => _decoder.close();
}

class DevelopmentLogController extends ChangeNotifier {
  DevelopmentLogController(this.store, {this.preferredPath});
  final DevelopmentLogStore store;
  final String? preferredPath;
  List<DevelopmentLogFile> files = [];
  String? selectedPath;
  String? error;
  bool loading = true;
  bool truncated = false;
  int revision = 0;
  DevelopmentLogBuffer _buffer = DevelopmentLogBuffer();
  int? _offset;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _pending;

  List<DevelopmentLogEntry> get entries => _buffer.entries;
  bool get tailOnly => truncated || _buffer.droppedLines > 0;

  List<DevelopmentLogEntry> filter(String query, DevelopmentLogLevel? level) {
    final keyword = query.trim().toLowerCase();
    return entries
        .where(
          (line) =>
              (level == null || line.level == level) &&
              (keyword.isEmpty || line.text.toLowerCase().contains(keyword)),
        )
        .toList();
  }

  void _select(String? path) {
    _buffer.close();
    _buffer = DevelopmentLogBuffer();
    selectedPath = path;
    _offset = null;
    truncated = false;
    error = null;
    revision++;
    _generation++;
  }

  Future<void> select(String path) async {
    if (_disposed || path == selectedPath) return;
    _select(path);
    loading = true;
    notifyListeners();
    if (_pending != null) await _pending;
    if (!_disposed) await refresh(scan: false);
  }

  Future<void> refresh({bool scan = true}) {
    if (_disposed) return Future.value();
    return _pending ??= _refresh(scan).whenComplete(() => _pending = null);
  }

  Future<void> _refresh(bool scan) async {
    try {
      if (scan) {
        final listed = await store.list();
        if (_disposed) return;
        files = listed;
        if (!files.any((file) => file.path == selectedPath)) {
          _select(
            files.any((file) => file.path == preferredPath)
                ? preferredPath
                : files.firstOrNull?.path,
          );
        }
      }
      final path = selectedPath;
      final generation = _generation;
      if (path != null) {
        final chunk = await store.read(path, offset: _offset);
        if (_disposed || generation != _generation) return;
        if (chunk.reset) {
          _buffer.close();
          _buffer = DevelopmentLogBuffer();
          truncated = false;
          revision++;
        }
        _offset = chunk.nextOffset;
        truncated |= chunk.skippedBytes > 0;
        if (chunk.bytes.isNotEmpty) {
          _buffer.add(chunk.bytes);
          revision++;
        }
      }
      error = null;
    } catch (e) {
      if (!_disposed) error = '无法读取日志：$e';
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _buffer.close();
    super.dispose();
  }
}
