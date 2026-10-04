import 'dart:io';
import 'package:path/path.dart' as p;

/// The embedded Python loader assumes the standard Windows profile depth.
/// A session-local DOS drive gives it X:\users\Developer\AppData\Roaming while
/// retaining all files in the user's chosen storage directory.
class WindowsSessionDrive {
  WindowsSessionDrive(this.directory);
  final String directory;
  String? _drive;

  Future<Map<String, String>> _mappings() async {
    final result = await Process.run('subst.exe', []);
    if (result.exitCode != 0) throw const FileSystemException('无法查询测试容器盘符');
    return {
      for (final match in RegExp(
        r'^([A-Za-z]:)\\: => (.+)\r?$',
        multiLine: true,
      ).allMatches(result.stdout.toString()))
        match[1]!.toUpperCase(): match[2]!.trim(),
    };
  }

  Future<void> mount() async {
    final mappings = await _mappings();
    // Recover only an exact previous mapping of this session after an app crash.
    for (final entry in mappings.entries) {
      if (p.windows.equals(entry.value, p.absolute(directory))) {
        _drive = entry.key;
        return;
      }
    }
    for (var code = 90; code >= 68; code--) {
      final drive = '${String.fromCharCode(code)}:';
      if (mappings.containsKey(drive) || await Directory('$drive\\').exists()) {
        continue;
      }
      final result = await Process.run('subst.exe', [
        drive,
        p.absolute(directory),
      ]);
      if (result.exitCode == 0) {
        _drive = drive;
        return;
      }
    }
    throw const FileSystemException('没有可用测试盘符，请关闭一个测试窗口后重试');
  }

  String translate(String path) {
    final absolute = p.absolute(path);
    if (_drive == null ||
        !(p.equals(absolute, p.absolute(directory)) ||
            p.isWithin(p.absolute(directory), absolute))) {
      return p.windows.normalize(absolute);
    }
    return p.windows.join(
      '$_drive\\',
      p.relative(absolute, from: p.absolute(directory)),
    );
  }

  Future<void> unmount() async {
    final drive = _drive;
    _drive = null;
    if (drive == null) return;
    final current = (await _mappings())[drive];
    if (current != null && p.windows.equals(current, p.absolute(directory))) {
      await Process.run('subst.exe', [drive, '/D']);
    }
  }
}
