import 'dart:io';
import 'package:path/path.dart' as p;
import '../development_storage.dart';

/// Dart's Windows directory enumeration still needs extended paths beyond
/// MAX_PATH, even when opening the same file by its ordinary path succeeds.
/// Keep this spelling at filesystem boundaries, out of saved paths and UI.
String nativeFileSystemPath(String path) {
  if (!Platform.isWindows) return path;
  final absolute = p.normalize(p.absolute(path));
  if (absolute.startsWith(r'\\?\')) return absolute;
  if (absolute.startsWith(r'\\')) {
    return r'\\?\UNC\' + absolute.substring(2);
  }
  return r'\\?\' + absolute;
}

/// Copy without following links. Windows/Linux never invoke macOS utilities.
/// Preserve links for storage migration; callers validating game/mod trees
/// reject them before this operation.
Future<void> copyDevelopmentTree(
  String source,
  String destination, {
  List<String> excludedFiles = const [],
}) async {
  if (Platform.isWindows) {
    // Parallel native copies matter for the game's tens of thousands of small
    // files. Copy links themselves; never mirror/delete destination contents.
    final result = await Process.run(
      'robocopy.exe',
      [
        source,
        destination,
        '/E',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/SL',
        '/SJ',
        '/R:1',
        '/W:1',
        '/MT:8',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP',
        if (excludedFiles.isNotEmpty) ...['/XF', ...excludedFiles],
      ],
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    // Robocopy uses 0..7 for successful copies (including changed files).
    if (result.exitCode >= 8) {
      throw const DevelopmentStorageException('复制文件失败，请检查权限和剩余空间。');
    }
    return;
  }
  if (Platform.isMacOS) {
    final result = await Process.run('/usr/bin/ditto', [
      '--noextattr',
      '--norsrc',
      source,
      destination,
    ]);
    if (result.exitCode != 0) {
      throw const DevelopmentStorageException('复制文件失败，请检查权限和剩余空间。');
    }
    return;
  }
  await Directory(destination).create(recursive: true);
  await for (final entry in Directory(source).list(followLinks: false)) {
    final target = p.join(destination, p.basename(entry.path));
    if (entry is Link) {
      await Link(target).create(await entry.target());
    } else if (entry is Directory) {
      await copyDevelopmentTree(entry.path, target);
    } else if (entry is File) {
      await entry.copy(target);
      await File(target).setLastModified(await entry.lastModified());
    } else {
      throw const DevelopmentStorageException('目录中包含不支持的文件类型。');
    }
  }
}

Future<void> revealDevelopmentDirectory(String path) async {
  if (Platform.isWindows) {
    // Explorer can return 1 when it delegates to an existing window.
    await Process.start('explorer.exe', [
      p.normalize(path),
    ], mode: ProcessStartMode.detached);
    return;
  }
  final result = await Process.run(
    Platform.isMacOS ? '/usr/bin/open' : 'xdg-open',
    [path],
  );
  if (result.exitCode != 0) {
    throw const DevelopmentStorageException('无法在文件管理器中打开目录。');
  }
}
