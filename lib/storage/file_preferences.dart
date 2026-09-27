import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../core/preferences.dart';
import 'file_lock.dart';

String mcdevHome() {
  final env = Platform.environment;
  if (env['MCDEV_HOME']?.isNotEmpty == true) return env['MCDEV_HOME']!;
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home == null) throw StateError('请设置 MCDEV_HOME');
  if (Platform.isMacOS) {
    // The sandboxed GUI's HOME already ends in the container's Data directory.
    // An unsandboxed CLI must address that same directory explicitly.
    const container = '/Library/Containers/com.aimessoft.consmelt/Data';
    final base = home.endsWith(container) ? home : '$home$container';
    return '$base/Library/Application Support/mcdev';
  }
  if (Platform.isWindows) return '${env['APPDATA'] ?? home}/mcdev';
  return '${env['XDG_CONFIG_HOME'] ?? '$home/.config'}/mcdev';
}

Future<PreferenceStore?> openDesktopPreferences(
  Map<String, Object> seed,
) async {
  // Flutter tests use platform mocks and must never read a user's real session.
  if (Platform.environment.containsKey('FLUTTER_TEST') ||
      !(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return null;
  }
  final store = await FilePreferences.open(mcdevHome());
  if (store._values['gui_migrated_v1'] != true) {
    // The macOS desktop bundle is no longer sandboxed so --headless can access
    // command paths. Recover preferences from the old container once.
    final legacy = await _legacyMacPreferences();
    await store.migrateGui({...legacy, ...seed});
  }
  return store;
}

Future<Map<String, Object>> _legacyMacPreferences() async {
  if (!Platform.isMacOS) return {};
  final home = Platform.environment['HOME'];
  if (home == null) return {};
  const container = '/Library/Containers/com.aimessoft.consmelt/Data';
  final base = home.endsWith(container) ? home : '$home$container';
  final file = File('$base/Library/Preferences/com.aimessoft.consmelt.plist');
  if (!await file.exists()) return {};
  final result = await Process.run('/usr/bin/plutil', [
    '-convert',
    'json',
    '-o',
    '-',
    file.path,
  ]);
  if (result.exitCode != 0) return {};
  try {
    final values = jsonDecode(result.stdout as String);
    if (values is! Map<String, dynamic>) return {};
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith('flutter.') &&
            (entry.key.substring(8).startsWith('login_') ||
                entry.key.substring(8).startsWith('resource_draft_v1:') ||
                entry.key == 'flutter.theme_mode' ||
                entry.key == 'flutter.income_presets_v1') &&
            (entry.value is String || entry.value is int))
          entry.key.substring(8): entry.value as Object,
    };
  } on FormatException {
    return {};
  }
}

/// Atomic, permission-restricted state with a cross-process writer lock.
class FilePreferences implements PreferenceStore {
  FilePreferences._(this.directory, this._values);
  final String directory;
  Map<String, dynamic> _values;
  File get _file => File('$directory/state.json');
  static Future<FilePreferences> open(String directory) async {
    final dir = Directory(directory);
    await dir.create(recursive: true);
    await _restrict(dir.path, '700');
    final store = FilePreferences._(dir.absolute.path, {});
    store._values = await store._read();
    return store;
  }

  static Future<void> _restrict(String path, String mode) async {
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', [mode, path]);
      if (result.exitCode != 0) throw FileSystemException('无法限制会话文件权限', path);
    }
  }

  Future<Map<String, dynamic>> _read() async {
    if (!await _file.exists()) return {};
    final data = jsonDecode(await _file.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('本地状态不是 JSON 对象');
    }
    return data;
  }

  Future<void> _update(void Function(Map<String, dynamic>) change) =>
      withFileLock('$directory/state.lock', () async {
        final latest = await _read();
        change(latest);
        final temp = File(
          '$directory/.state-$pid-${Random.secure().nextInt(1 << 32)}.tmp',
        );
        try {
          await temp.create();
          await _restrict(temp.path, '600');
          await temp.writeAsString(jsonEncode(latest), flush: true);
          await temp.rename(_file.path);
          _values = latest;
        } finally {
          if (await temp.exists()) await temp.delete();
        }
      });

  Future<void> migrateGui(Map<String, Object> seed) async {
    if (_values['gui_migrated_v1'] == true) return;
    await _update((values) {
      if (values['gui_migrated_v1'] == true) return;
      // A CLI login/logout before the first GUI launch owns the entire session.
      // Never mix an old GUI password/token with a newer CLI account.
      final hasManagedLogin = values.keys.any((k) => k.startsWith('login_'));
      for (final entry in seed.entries) {
        if (hasManagedLogin && entry.key.startsWith('login_')) continue;
        values.putIfAbsent(entry.key, () => entry.value);
      }
      values['gui_migrated_v1'] = true;
    });
  }

  @override
  String? getString(String key) => _values[key] as String?;
  @override
  int? getInt(String key) => _values[key] as int?;
  @override
  Set<String> getKeys() => _values.keys.toSet();
  @override
  Future<bool> setString(String key, String value) async {
    await _update((m) => m[key] = value);
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    await _update((m) => m[key] = value);
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    await _update((m) => m.remove(key));
    return true;
  }

  @override
  Future<void> apply(Map<String, Object?> changes) => _update((m) {
    for (final e in changes.entries) {
      if (e.value == null) {
        m.remove(e.key);
      } else {
        m[e.key] = e.value;
      }
    }
  });
}
