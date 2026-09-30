import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'development_logs.dart';
import 'development_storage.dart';

DevelopmentLogStore openDevelopmentLogs(String directory) =>
    NativeDevelopmentLogs(directory);

class NativeDevelopmentLogs extends DevelopmentLogStore {
  NativeDevelopmentLogs(this.directory, {this.chunkBytes = 512 * 1024});
  final String directory;
  final int chunkBytes;

  Future<File> _file(String path) async {
    if (p.normalize(p.absolute(p.dirname(path))) !=
            p.normalize(p.absolute(directory)) ||
        !path.toLowerCase().endsWith('.log') ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const DevelopmentStorageException('日志不存在或不属于当前开发目录。');
    }
    return File(path);
  }

  @override
  Future<List<DevelopmentLogFile>> list() async {
    final root = Directory(directory);
    if (!await root.exists()) return [];
    final files = <DevelopmentLogFile>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.log')) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.file) {
        files.add(DevelopmentLogFile(entity.path, stat.modified, stat.size));
      }
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  @override
  Future<DevelopmentLogChunk> read(String path, {int? offset}) async {
    final handle = await (await _file(path)).open();
    try {
      final length = await handle.length();
      final reset = offset != null && offset > length;
      var start = offset == null || reset
          ? max(0, length - chunkBytes)
          : offset;
      await handle.setPosition(start);
      var bytes = await handle.read(min(chunkBytes, max(0, length - start)));
      final nextOffset = start + bytes.length;
      if ((offset == null || reset) && start > 0) {
        // Omit the leading partial record/code point when opening a large file.
        final newline = bytes.indexOf(10);
        if (newline >= 0) {
          start += newline + 1;
          bytes = bytes.sublist(newline + 1);
        } else {
          while (bytes.isNotEmpty && bytes.first & 0xc0 == 0x80) {
            start++;
            bytes = bytes.sublist(1);
          }
        }
      }
      return DevelopmentLogChunk(
        bytes: bytes,
        nextOffset: nextOffset,
        reset: reset,
        skippedBytes: offset == null || reset ? start : 0,
      );
    } finally {
      await handle.close();
    }
  }

  Future<File> _destination(String source, String destination) async {
    final original = await _file(source);
    final target = File(destination);
    final originalPath = await original.resolveSymbolicLinks();
    final targetPath = await target.exists()
        ? await target.resolveSymbolicLinks()
        : p.join(
            await target.parent.resolveSymbolicLinks(),
            p.basename(target.path),
          );
    if (p.equals(originalPath, targetPath) ||
        p.isWithin(
          await Directory(directory).resolveSymbolicLinks(),
          targetPath,
        )) {
      throw const DevelopmentStorageException('请导出到日志目录以外，避免覆盖正在使用的日志。');
    }
    return target;
  }

  @override
  Future<void> exportOriginal(String source, String destination) async {
    final original = await _file(source);
    final target = await _destination(source, destination);
    // Capture the current length: exports finish even while the game appends.
    final length = await original.length();
    final output = target.openWrite();
    try {
      await output.addStream(original.openRead(0, length));
    } finally {
      await output.close();
    }
  }

  @override
  Future<void> exportText(
    String source,
    String destination,
    String text,
  ) async {
    final target = await _destination(source, destination);
    await target.writeAsString(text, flush: true);
  }
}
