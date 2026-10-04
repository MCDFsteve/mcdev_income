import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'development_storage.dart';
import 'download_io.dart';
import 'platform/host_files_io.dart';

String safeArchivePath(String name) {
  final value = name.replaceAll('\\', '/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value) ||
      value.split('/').contains('..') ||
      value.contains('\u0000') ||
      value
          .split('/')
          .any(
            (segment) =>
                RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(segment) ||
                (segment != '.' &&
                    (segment.endsWith('.') || segment.endsWith(' '))) ||
                RegExp(
                  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
                  caseSensitive: false,
                ).hasMatch(segment),
          )) {
    throw const DevelopmentStorageException('归档包含越界路径，未安装。');
  }
  return p.posix.normalize(value);
}

Future<void> extractZipSafe(
  Archive archive,
  String target, {
  DownloadControl? control,
  String? sourceRoot,
  void Function(StorageMigrationProgress)? onProgress,
}) async {
  final seen = <String>{};
  // Validate every entry before any write, including case-insensitive macOS conflicts.
  for (final entry in archive) {
    final relative = safeArchivePath(entry.name);
    if (entry.isSymbolicLink || !seen.add(relative.toLowerCase())) {
      throw const DevelopmentStorageException('归档包含链接或重复路径，未安装。');
    }
  }
  target = nativeFileSystemPath(target);
  final prefix = sourceRoot == null ? null : '${safeArchivePath(sourceRoot)}/';
  await Directory(target).create(recursive: true);
  var completed = 0;
  for (final entry in archive) {
    control?.check();
    var relative = safeArchivePath(entry.name);
    if (prefix != null) {
      if (!relative.startsWith(prefix)) continue;
      relative = relative.substring(prefix.length);
      if (relative.isEmpty) continue;
    }
    final out = p.join(target, relative);
    if (!p.isWithin(p.normalize(target), p.normalize(out))) {
      throw const DevelopmentStorageException('归档路径不合法。');
    }
    if (entry.isFile) {
      await File(out).parent.create(recursive: true);
      final stream = OutputFileStream(out);
      try {
        entry.writeContent(stream);
      } finally {
        await stream.close();
      }
    } else {
      await Directory(out).create(recursive: true);
    }
    completed++;
    if (completed % 100 == 0 || completed == archive.length) {
      onProgress?.call(
        StorageMigrationProgress(
          '解压游戏包',
          completed: completed,
          total: archive.length,
        ),
      );
    }
  }
}

/// Strip the publisher's long build folder before writing the game tree.
/// Every archive entry still passes preflight, including ignored siblings.
Future<void> extractGameZipSafe(
  Archive archive,
  String target, {
  DownloadControl? control,
  void Function(StorageMigrationProgress)? onProgress,
}) async {
  final candidates = [
    for (final entry in archive)
      if (entry.isFile &&
          p.posix.basename(safeArchivePath(entry.name)) ==
              'Minecraft.Windows.exe' &&
          safeArchivePath(entry.name).split('/').length <= 2)
        p.posix.dirname(safeArchivePath(entry.name)),
  ];
  if (candidates.length != 1) {
    throw const DevelopmentStorageException('游戏包中没有唯一的游戏目录。');
  }
  await extractZipSafe(
    archive,
    target,
    sourceRoot: candidates.single == '.' ? null : candidates.single,
    control: control,
    onProgress: onProgress,
  );
}

Map<String, String> parseGamePatch(String text) {
  final data = jsonDecode(text);
  final entries = data['md5'];
  if (entries is! Map || entries.isEmpty) {
    throw const DevelopmentStorageException('游戏补丁清单无效。');
  }
  final hashes = <String, String>{};
  final lower = <String>{};
  for (final entry in entries.entries) {
    final key = safeArchivePath(entry.key as String);
    if (entry.value is! String ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(entry.value) ||
        !lower.add(key.toLowerCase())) {
      throw const DevelopmentStorageException('游戏清单包含无效摘要或重复路径。');
    }
    hashes[key] = entry.value.toLowerCase();
  }
  if (!hashes.containsKey('Minecraft.Windows.exe')) {
    throw const DevelopmentStorageException('游戏清单缺少主程序。');
  }
  return hashes;
}

Future<void> verifyGameFiles(
  String root,
  Map<String, String> hashes, {
  DownloadControl? control,
  void Function(StorageMigrationProgress)? onProgress,
}) async {
  root = nativeFileSystemPath(root);
  await rejectTreeLinks(root);
  // The authoritative patch is the allowlist: extra DLLs must not be loaded.
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File) {
      final relative = p
          .relative(entity.path, from: root)
          .replaceAll('\\', '/');
      if (!hashes.containsKey(relative) &&
          !['patch.json', '.mcdev-game.json'].contains(relative)) {
        await entity.delete();
      }
    }
  }
  var count = 0;
  for (final entry in hashes.entries) {
    control?.check();
    final path = p.join(root, entry.key);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        (await md5.bind(File(path).openRead()).first).toString() !=
            entry.value) {
      throw DevelopmentStorageException('游戏文件校验失败：${entry.key}');
    }
    count++;
    if (count % 100 == 0 || count == hashes.length) {
      onProgress?.call(
        StorageMigrationProgress(
          '校验游戏文件',
          completed: count,
          total: hashes.length,
        ),
      );
    }
  }
}

Future<void> rejectTreeLinks(String root) async {
  root = nativeFileSystemPath(root);
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw const DevelopmentStorageException('游戏或模组文件包含符号链接，请使用完整的实际文件。');
    }
  }
}
