import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../core/preferences.dart';
import '../storage/file_preferences.dart';
import '../storage/file_lock.dart';
import 'development_storage.dart';
import 'platform/host_files_io.dart';

Future<bool> supportsDevelopment() async {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  if (Platform.isWindows) return true;
  if (!Platform.isMacOS) {
    return false;
  }
  try {
    final result = await Process.run('/usr/sbin/sysctl', [
      '-n',
      'hw.optional.arm64',
    ]);
    return result.exitCode == 0 && (result.stdout as String).trim() == '1';
  } on ProcessException {
    return false;
  }
}

Future<DevelopmentStorage> openDevelopmentStorage(
  PreferenceStore preferences,
) async {
  final home = Platform.environment['HOME'];
  final local =
      Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
  if (!(Platform.isWindows && local != null) &&
      !(Platform.isMacOS && home != null)) {
    throw const DevelopmentStorageException(
      '开发功能目前支持 Windows 和 Apple 芯片 macOS。',
    );
  }
  return NativeDevelopmentStorage(
    preferences: preferences,
    defaultRoot: Platform.isWindows
        ? p.join(local!, 'mcdev_income', 'development')
        : p.join(
            home!,
            'Library',
            'Application Support',
            'mcdev_income',
            'development',
          ),
    lockPath: p.join(mcdevHome(), 'development-storage.lock'),
  );
}

bool _isSessionLease(String relative) {
  final parts = p.split(relative);
  return parts.length == 2 &&
      parts.first == 'prefixes' &&
      RegExp(r'^\.session-[a-zA-Z0-9_-]{1,64}\.lock$').hasMatch(parts.last);
}

class _Entry {
  const _Entry(this.type, {this.size = 0, this.modified, this.target});
  final FileSystemEntityType type;
  final int size;
  final DateTime? modified;
  final String? target;
}

/// Managed development data, separate from the existing account/config store.
/// Inspection is read only; the development page initializes a fresh default
/// on first entry, while unavailable saved locations require explicit recovery.
class NativeDevelopmentStorage implements DevelopmentStorage {
  NativeDevelopmentStorage({
    required this.preferences,
    required this.defaultRoot,
    required this.lockPath,
  }) : _paths = DevelopmentPaths(
         preferences.getString(DevelopmentStorage.preferenceKey) ?? defaultRoot,
       );

  final PreferenceStore preferences;
  final String defaultRoot;
  @override
  final String lockPath;
  DevelopmentPaths _paths;
  @override
  DevelopmentPaths get paths => _paths;
  static const markerName = '.mcdev-development.json';
  static const _kind = 'mcdev-development';

  String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<T> _exclusive<T>(Future<T> Function() action) =>
      withFileLock(lockPath, () => _withIdleSessions(action), wait: false);

  /// Launch preparation holds the storage lock only until the game starts.
  /// The session leases outlive preparation, so another app process cannot
  /// move an active prefix or switch its data directory while a game runs.
  Future<T> _withIdleSessions<T>(Future<T> Function() action) async {
    final directory = Directory(paths.prefixes);
    final leases = <String>[];
    if (await directory.exists()) {
      await for (final entry in directory.list(followLinks: false)) {
        if (RegExp(
          r'^\.session-[a-zA-Z0-9_-]{1,64}\.lock$',
        ).hasMatch(p.basename(entry.path))) {
          if (entry is! File) {
            throw const DevelopmentStorageException('测试容器锁文件无效。');
          }
          leases.add(entry.path);
        }
      }
    }
    leases.sort();
    Future<T> acquire(int index) async {
      if (index == leases.length) return action();
      var acquired = false;
      try {
        return await withFileLock(leases[index], () {
          acquired = true;
          return acquire(index + 1);
        }, wait: false);
      } on FileSystemException {
        if (acquired) rethrow;
        throw const DevelopmentStorageException('请先退出所有测试游戏，再更改开发数据目录。');
      }
    }

    return acquire(0);
  }

  /// Resolve existing ancestors too, so symlink aliases cannot bypass nesting checks.
  Future<String> _canonical(String value) async {
    var path = value.trim();
    if (path == '~' || path.startsWith('~/')) {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null) throw const DevelopmentStorageException('无法确定用户目录。');
      path = path == '~' ? home : p.join(home, path.substring(2));
    }
    if (!p.isAbsolute(path)) {
      throw const DevelopmentStorageException('请选择或输入完整的绝对路径。');
    }
    path = p.normalize(path);
    if (Platform.isMacOS && p.isWithin('/Volumes', path)) {
      final parts = p.split(path);
      if (parts.length >= 3 &&
          !await Directory(p.joinAll(parts.take(3))).exists()) {
        throw const DevelopmentStorageException('存储卷未连接，请先连接磁盘再操作。');
      }
    }
    var ancestor = path;
    final missing = <String>[];
    while (await FileSystemEntity.type(ancestor, followLinks: false) ==
        FileSystemEntityType.notFound) {
      missing.insert(0, p.basename(ancestor));
      final parent = p.dirname(ancestor);
      if (parent == ancestor) {
        throw const DevelopmentStorageException('无法访问目标目录。');
      }
      ancestor = parent;
    }
    if (!await Directory(ancestor).exists()) {
      throw const DevelopmentStorageException('所选路径不是可用的文件夹。');
    }
    final resolved = await Directory(ancestor).resolveSymbolicLinks();
    final result = p.normalize(p.joinAll([resolved, ...missing]));
    if (result == p.rootPrefix(result)) {
      throw const DevelopmentStorageException('不能使用磁盘根目录作为开发数据目录。');
    }
    final configDirectory = await _resolveConfigDirectory();
    if (p.equals(result, configDirectory) ||
        p.isWithin(result, configDirectory)) {
      throw const DevelopmentStorageException('开发数据目录不能包含应用的配置目录。');
    }
    return result;
  }

  Future<String> _resolveConfigDirectory() async {
    var dir = p.dirname(p.absolute(lockPath));
    final missing = <String>[];
    while (!await Directory(dir).exists()) {
      missing.insert(0, p.basename(dir));
      dir = p.dirname(dir);
    }
    return p.normalize(
      p.joinAll([await Directory(dir).resolveSymbolicLinks(), ...missing]),
    );
  }

  Future<void> _validateMarker(String root) async {
    final file = File(p.join(root, markerName));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const DevelopmentStorageException(
        '此目录不是本应用创建的开发数据目录，请选择已有开发目录或使用空目录。',
      );
    }
    if (await file.length() > 8192) {
      throw const DevelopmentStorageException('开发目录标记无效。');
    }
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map ||
          data['kind'] != _kind ||
          data['schema'] != 1 ||
          data['id'] is! String ||
          (data['id'] as String).isEmpty) {
        throw const FormatException();
      }
    } on FormatException {
      throw const DevelopmentStorageException('开发目录标记无效或版本不受支持。');
    }
    for (final name in DevelopmentPaths.folders) {
      final type = await FileSystemEntity.type(
        p.join(root, name),
        followLinks: false,
      );
      if (type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.notFound) {
        throw DevelopmentStorageException('目录结构冲突：$name 必须是实际文件夹。');
      }
    }
  }

  Future<void> _probeWritable(String root) async {
    final probe = File(p.join(root, '.mcdev-write-${_id()}'));
    try {
      await probe.writeAsString('mcdev', flush: true);
    } on FileSystemException {
      throw const DevelopmentStorageException('该目录不可写，请选择有写入权限的位置。');
    } finally {
      if (await probe.exists()) await probe.delete();
    }
  }

  Future<void> _makeFolders(String root) async {
    for (final name in DevelopmentPaths.folders) {
      await Directory(p.join(root, name)).create();
    }
  }

  Future<void> _saveRoot(String root, {String? copiedTabsFrom}) async {
    if (copiedTabsFrom != null) {
      final tabs = preferences.getString(
        'development_test_tabs_v1:$copiedTabsFrom',
      );
      if (tabs != null &&
          !await preferences.setString(
            'development_test_tabs_v1:$root',
            tabs,
          )) {
        throw const DevelopmentStorageException('测试标签页设置未能迁移，原位置仍保持启用。');
      }
    }
    if (!await preferences.setString(DevelopmentStorage.preferenceKey, root)) {
      throw const DevelopmentStorageException('路径设置未能保存，原位置仍保持启用。');
    }
    _paths = DevelopmentPaths(root);
  }

  @override
  Future<DevelopmentStorageStatus> inspect() async {
    final root = paths.root;
    if (!await Directory(root).exists()) {
      return DevelopmentStorageStatus(
        initialized: false,
        exists: false,
        problem: preferences.getString(DevelopmentStorage.preferenceKey) != null
            ? '数据目录暂不可访问；请检查磁盘连接，或选择其他位置。'
            : null,
      );
    }
    try {
      await _validateMarker(root);
      final counts = <String, int>{};
      for (final name in DevelopmentPaths.folders) {
        final dir = Directory(paths.folder(name));
        counts[name] = await dir.exists()
            ? await dir
                  .list(followLinks: false)
                  .where((entry) => !p.basename(entry.path).startsWith('.'))
                  .length
            : 0;
      }
      return DevelopmentStorageStatus(
        initialized: true,
        exists: true,
        entries: counts,
      );
    } on DevelopmentStorageException catch (error) {
      return DevelopmentStorageStatus(
        initialized: false,
        exists: true,
        problem: error.message,
      );
    } on FileSystemException {
      return const DevelopmentStorageStatus(
        initialized: false,
        exists: true,
        problem: '无法读取数据目录，请检查权限或磁盘连接。',
      );
    }
  }

  @override
  Future<void> initialize({String? root}) => _exclusive(() async {
    final destination = await _canonical(root ?? paths.root);
    final directory = Directory(destination);
    if (await directory.exists()) {
      final marker = File(p.join(destination, markerName));
      if (await marker.exists()) {
        await _validateMarker(destination);
      } else if (await directory
          .list(followLinks: false)
          .any((entry) => p.basename(entry.path) != '.DS_Store')) {
        throw const DevelopmentStorageException('请使用空目录；已有开发数据请通过“使用已有目录”加载。');
      }
    } else {
      await directory.create(recursive: true);
    }
    await _probeWritable(destination);
    final marker = File(p.join(destination, markerName));
    if (!await marker.exists()) {
      await marker.writeAsString(
        jsonEncode({'kind': _kind, 'schema': 1, 'id': _id()}),
        flush: true,
      );
    }
    await _makeFolders(destination);
    await _saveRoot(destination);
  });

  @override
  Future<void> useExisting(String root) => _exclusive(() async {
    final destination = await _canonical(root);
    await _validateMarker(destination);
    await _probeWritable(destination);
    await _makeFolders(destination);
    await _saveRoot(destination);
  });

  Future<Map<String, _Entry>> _inventory(String root) async {
    final result = <String, _Entry>{};
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: root);
      // Windows leases are mandatory locks, not user data to copy or hash.
      if (Platform.isWindows && _isSessionLease(relative)) continue;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        result[relative] = _Entry(
          type,
          target: await Link(entity.path).target(),
        );
      } else if (type == FileSystemEntityType.file) {
        final stat = await entity.stat();
        result[relative] = _Entry(
          type,
          size: stat.size,
          modified: stat.modified,
        );
      } else if (type == FileSystemEntityType.directory) {
        result[relative] = _Entry(type);
      } else {
        throw DevelopmentStorageException('迁移期间文件不可访问：$relative');
      }
    }
    return result;
  }

  String _movedLinkTarget(
    String relative,
    String target,
    String source,
    String destination,
  ) {
    final absolute = p.isAbsolute(target)
        ? p.normalize(target)
        : p.normalize(p.join(source, p.dirname(relative), target));
    if (p.equals(source, absolute) || p.isWithin(source, absolute)) {
      return p.isAbsolute(target)
          ? p.join(destination, p.relative(absolute, from: source))
          : target;
    }
    // Relative external project links must retain their meaning after a move.
    return p.isAbsolute(target) ? target : absolute;
  }

  @override
  Future<void> migrateTo(
    String root, {
    void Function(StorageMigrationProgress)? onProgress,
  }) => _exclusive(() async {
    final source = await _canonical(paths.root);
    final destination = await _canonical(root);
    if (p.equals(source, destination)) {
      throw const DevelopmentStorageException('所选目录已经是当前数据位置。');
    }
    if (p.isWithin(source, destination) || p.isWithin(destination, source)) {
      throw const DevelopmentStorageException('新旧数据目录不能互相包含，请选择独立位置。');
    }
    await _validateMarker(source);
    final target = Directory(destination);
    if (await target.exists() &&
        !await target.list(followLinks: false).isEmpty) {
      throw const DevelopmentStorageException('迁移目标必须是空目录，已有文件不会被覆盖。');
    }
    await target.parent.create(recursive: true);
    await _probeWritable(target.parent.path);
    final stage = Directory(
      p.join(target.parent.path, '.mcdev-migration-${_id()}'),
    );
    try {
      onProgress?.call(const StorageMigrationProgress('检查开发数据'));
      final original = await _inventory(source);
      onProgress?.call(const StorageMigrationProgress('复制开发数据'));
      // ditto preserves executable modes and copies symbolic links without
      // traversing Wine's dosdevices/z: link or linked external projects.
      await copyDevelopmentTree(
        source,
        stage.path,
        excludedFiles: Platform.isWindows
            ? [
                await for (final entry in Directory(
                  p.join(source, 'prefixes'),
                ).list(followLinks: false))
                  if (_isSessionLease(p.relative(entry.path, from: source)))
                    entry.path,
              ]
            : const [],
      );
      for (final entry in original.entries.where(
        (entry) => entry.value.type == FileSystemEntityType.link,
      )) {
        final expected = _movedLinkTarget(
          entry.key,
          entry.value.target!,
          source,
          destination,
        );
        final link = Link(p.join(stage.path, entry.key));
        if (await link.target() != expected) {
          await link.delete();
          await link.create(expected);
        }
      }
      final copy = await _inventory(stage.path);
      if (original.length != copy.length ||
          original.keys.any((key) => !copy.containsKey(key))) {
        throw const DevelopmentStorageException('迁移校验失败：目录内容不一致，原数据保持可用。');
      }
      final fileCount = original.values
          .where((entry) => entry.type == FileSystemEntityType.file)
          .length;
      var verified = 0;
      for (final item in original.entries) {
        final actual = copy[item.key]!;
        if (actual.type != item.value.type) {
          throw const DevelopmentStorageException('迁移校验失败：文件类型不一致。');
        }
        if (item.value.type == FileSystemEntityType.link) {
          if (actual.target !=
              _movedLinkTarget(
                item.key,
                item.value.target!,
                source,
                destination,
              )) {
            throw const DevelopmentStorageException('迁移校验失败：链接目标不一致。');
          }
        } else if (item.value.type == FileSystemEntityType.file) {
          final sourceFile = File(p.join(source, item.key));
          final stat = await sourceFile.stat();
          if (stat.size != item.value.size ||
              stat.modified != item.value.modified ||
              actual.size != item.value.size) {
            throw const DevelopmentStorageException('迁移期间数据发生变化，请关闭游戏后重试。');
          }
          final before = await sha256.bind(sourceFile.openRead()).first;
          final after = await sha256
              .bind(File(p.join(stage.path, item.key)).openRead())
              .first;
          if (before != after) {
            throw const DevelopmentStorageException('迁移校验失败：文件内容不一致。');
          }
          verified++;
          onProgress?.call(
            StorageMigrationProgress(
              '校验开发数据',
              completed: verified,
              total: fileCount,
            ),
          );
        }
      }
      final finalSource = await _inventory(source);
      if (finalSource.length != original.length ||
          original.entries.any((entry) {
            final last = finalSource[entry.key];
            return last == null ||
                last.type != entry.value.type ||
                last.size != entry.value.size ||
                last.modified != entry.value.modified ||
                last.target != entry.value.target;
          })) {
        throw const DevelopmentStorageException('迁移期间数据发生变化，请关闭游戏后重试。');
      }
      onProgress?.call(const StorageMigrationProgress('切换数据位置'));
      // Renaming over a nonempty target fails atomically: never delete it.
      await stage.rename(destination);
      await _saveRoot(destination, copiedTabsFrom: source);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  });

  @override
  Future<void> reveal(String path) async {
    if (!await Directory(path).exists()) {
      throw const DevelopmentStorageException('该目录尚未创建或存储卷未连接。');
    }
    await revealDevelopmentDirectory(path);
  }
}
