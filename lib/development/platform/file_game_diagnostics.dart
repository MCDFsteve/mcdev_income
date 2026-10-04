import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'game_diagnostics.dart';
export 'game_diagnostics.dart' show classifyNativeDiagnostic;

/// Incremental reader for the developer client's native diagnostics. Existing
/// content is skipped per launch; reads and partial lines have bounded memory.
class FileGameDiagnostics extends GameDiagnostics {
  FileGameDiagnostics({
    required this.dataDirectory,
    required this.crashDirectory,
  });
  final String dataDirectory;
  final String crashDirectory;
  final Map<String, int> _offsets = {};
  final Map<String, String> _partial = {};
  final Set<String> _dumps = {};
  final Set<String> _reported = {};

  Future<List<File>> _files(String path, bool recursive) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    return dir
        .list(recursive: recursive, followLinks: false)
        .where((e) => e is File)
        .cast<File>()
        .toList();
  }

  @override
  Future<void> prepare() async {
    for (final file in await _files(p.join(dataDirectory, 'logs'), false)) {
      _offsets[file.path] = await file.length();
    }
    final python = File(p.join(dataDirectory, 'mcp.log'));
    if (await python.exists()) _offsets[python.path] = await python.length();
    for (final file in await _files(crashDirectory, true)) {
      if (file.path.endsWith('.dmp')) _dumps.add(file.path);
    }
  }

  @override
  Stream<GameDiagnostic> watch() async* {
    while (true) {
      yield* Stream.fromIterable(await poll());
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
  }

  Future<List<GameDiagnostic>> poll() async {
    final events = <GameDiagnostic>[];
    try {
      final files = await _files(p.join(dataDirectory, 'logs'), false);
      final python = File(p.join(dataDirectory, 'mcp.log'));
      if (await python.exists()) files.add(python);
      for (final file in files) {
        final encoded = p.basename(file.path) == 'mcp.log';
        if (!encoded && !p.basename(file.path).startsWith('Debug_Log')) {
          continue;
        }
        final handle = await file.open();
        try {
          final size = await handle.length();
          var offset = _offsets[file.path] ?? 0;
          if (size < offset) {
            offset = 0;
            _partial.remove(file.path);
          }
          await handle.setPosition(offset);
          final bytes = await handle.read(256 * 1024);
          _offsets[file.path] = offset + bytes.length;
          final lines =
              '${_partial.remove(file.path) ?? ''}${utf8.decode(bytes, allowMalformed: true)}'
                  .split('\n');
          final tail = lines.removeLast();
          if (tail.length < 65536) _partial[file.path] = tail;
          for (var line in lines) {
            if (encoded) {
              try {
                line = utf8.decode(
                  base64.decode(line.trim()),
                  allowMalformed: true,
                );
              } on FormatException {
                continue;
              }
            }
            for (final text in line.split('\n')) {
              final event = classifyNativeDiagnostic(text);
              if (event != null && _reported.add(event.message)) {
                events.add(event);
              }
            }
          }
        } finally {
          await handle.close();
        }
      }
      for (final file in await _files(crashDirectory, true)) {
        if (file.path.endsWith('.dmp') && _dumps.add(file.path)) {
          events.add(
            GameDiagnostic(
              '游戏发生原生崩溃，转储：${file.path}',
              level: GameDiagnosticLevel.error,
              fatal: true,
            ),
          );
        }
      }
    } on FileSystemException {
      if (_reported.add('unavailable')) {
        events.add(
          const GameDiagnostic(
            '暂时无法读取游戏诊断文件。',
            level: GameDiagnosticLevel.warning,
          ),
        );
      }
    }
    return events;
  }
}
