import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'development_storage.dart';
import 'lan_patch_io.dart' show lanGameHash, lanInjectorFile, lanInjectorHash;
import 'mod_log_capture_io.dart';
import 'game_archive_io.dart' show rejectTreeLinks;

const pythonReloadVersion = '3.10.0.420447';
const pythonReloadDllHash =
    '68309afd8485c36b8b5a44bee447dbcf005befc55c2ddaba774d6a12684f29e0';

class PythonReloadPack {
  const PythonReloadPack(this.source, this.mounted);
  final String source;
  final String mounted;
}

class _PythonFile {
  const _PythonFile(this.pack, this.relative, this.module, this.bytes);
  final PythonReloadPack pack;
  final String relative;
  final String module;
  final List<int> bytes;
  String get key => '${pack.mounted}/$relative';
  String get digest => sha256.convert(bytes).toString();
  File get target => File(p.join(pack.mounted, relative));
}

/// Immutable launch-time pack mapping. Runtime writes only touch these mounted
/// copies, and the baseline advances only after the in-game acknowledgement.
class PythonReloadSession {
  PythonReloadSession._(this.packs, this._baseline, this._manifests);
  final List<PythonReloadPack> packs;
  Map<String, _PythonFile> _baseline;
  final Map<String, String> _manifests;
  bool get hasScripts => _baseline.isNotEmpty;
  List<String> get roots =>
      _baseline.values
          .map((file) => file.module.split('.').first)
          .toSet()
          .toList()
        ..sort();

  static Future<PythonReloadSession> capture(
    List<PythonReloadPack> packs,
  ) async {
    final baseline = <String, _PythonFile>{};
    final manifests = <String, String>{};
    for (final pack in packs) {
      if (p.equals(pack.source, pack.mounted) ||
          p.isWithin(pack.source, pack.mounted) ||
          p.isWithin(pack.mounted, pack.source)) {
        throw const DevelopmentStorageException('热重载需要独立的测试副本。');
      }
      manifests[pack.source] = await _manifest(pack.mounted);
      for (final file in await _files(pack, pack.mounted)) {
        baseline[file.key] = file;
      }
    }
    final modules = baseline.values.map((file) => file.module).toList();
    if (modules.toSet().length != modules.length ||
        modules.any(
          (name) => name.split('.').first == PythonReloadBridge.scriptsName,
        )) {
      throw const DevelopmentStorageException('Python 模块名称重复或占用了热重载辅助包名称。');
    }
    return PythonReloadSession._(List.unmodifiable(packs), baseline, manifests);
  }

  Future<PythonReloadChanges> changes() async {
    final next = <String, _PythonFile>{};
    final modules = <String, String>{};
    for (final pack in packs) {
      if (await _manifest(pack.source) != _manifests[pack.source]) {
        throw const DevelopmentStorageException('包清单已变化，请重新启动测试游戏。');
      }
      for (final file in await _files(pack, pack.source)) {
        if (!roots.contains(file.module.split('.').first)) {
          throw const DevelopmentStorageException('新增脚本包需要重新启动测试游戏。');
        }
        final owner = modules[file.module];
        if (owner != null && owner != file.key) {
          throw DevelopmentStorageException(
            'Python 模块 ${file.module} 在多个包中重复，无法确定重载目标。',
          );
        }
        modules[file.module] = file.key;
        next[file.key] = file;
      }
    }
    if (_baseline.keys.any((key) => !next.containsKey(key))) {
      throw const DevelopmentStorageException('Python 文件已删除或重命名，请重新启动测试游戏。');
    }
    final changed = next.values
        .where((file) => _baseline[file.key]?.digest != file.digest)
        .toList();
    if (changed.length > 4096 ||
        changed.fold<int>(0, (size, file) => size + file.bytes.length) >
            32 * 1024 * 1024) {
      throw const DevelopmentStorageException('本次 Python 修改过多，请重新启动测试游戏。');
    }
    return PythonReloadChanges._(this, next, changed);
  }

  static Future<String> _manifest(String root) async {
    if (await FileSystemEntity.type(root, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const DevelopmentStorageException('模组目录已移动或不是实际目录，请重新启动测试。');
    }
    await rejectTreeLinks(root);
    final file = File(p.join(root, 'manifest.json'));
    if (await file.length() > 1024 * 1024) {
      throw const DevelopmentStorageException('包清单过大，无法验证热重载目标。');
    }
    final value = jsonDecode(await file.readAsString()) as Map;
    return jsonEncode([
      value['header'],
      value['modules'],
      value['dependencies'],
    ]);
  }

  static Future<List<_PythonFile>> _files(
    PythonReloadPack pack,
    String root,
  ) async {
    await rejectTreeLinks(root);
    final files = <_PythonFile>[];
    var size = 0;
    await for (final item in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (item is! File || p.extension(item.path) != '.py') continue;
      final relative = p.relative(item.path, from: root);
      final parts = p.split(relative);
      // Top-level files are not mounted as an importable ModSDK package.
      if (parts.length < 2) continue;
      final names = [
        ...parts.take(parts.length - 1),
        p.basenameWithoutExtension(item.path),
      ];
      if (names.last == '__init__') names.removeLast();
      if (names.any(
        (part) => !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(part),
      )) {
        throw DevelopmentStorageException('Python 模块路径无效：$relative');
      }
      final length = await item.length();
      size += length;
      if (length > 4 * 1024 * 1024 || size > 32 * 1024 * 1024) {
        throw const DevelopmentStorageException('Python 源码过大，无法执行热重载。');
      }
      files.add(
        _PythonFile(pack, relative, names.join('.'), await item.readAsBytes()),
      );
    }
    files.sort((a, b) => a.module.compareTo(b.module));
    return files;
  }
}

class PythonReloadChanges {
  PythonReloadChanges._(this._session, this._next, this._changed);
  final PythonReloadSession _session;
  final Map<String, _PythonFile> _next;
  final List<_PythonFile> _changed;
  final Map<String, List<int>?> _backups = {};
  bool get isEmpty => _changed.isEmpty;
  int get count => _changed.length;

  List<Map<String, Object>> requestFiles(String Function(String) gamePath) => [
    for (final file in _changed)
      {
        'module': file.module,
        'path': gamePath(file.target.path),
        'source': base64Encode(file.bytes),
      },
  ];

  /// All source bytes were read before staging. Do not use the raw source path
  /// again: an editor saving concurrently must belong to the next transaction.
  Future<void> stage(void Function() checkCurrent) async {
    try {
      for (final file in _changed) {
        checkCurrent();
        await rejectTreeLinks(file.pack.mounted);
        final target = file.target;
        final previous = await target.exists()
            ? await target.readAsBytes()
            : null;
        _backups[target.path] = previous;
        final bytes = previous == null
            ? file.bytes
            : replaceModLogOriginalSource(previous, file.bytes);
        await target.parent.create(recursive: true);
        await _atomicBytes(target, bytes);
        for (final suffix in ['c', 'o']) {
          final compiled = File('${target.path}$suffix');
          if (await compiled.exists()) {
            _backups[compiled.path] = await compiled.readAsBytes();
            await compiled.delete();
          }
        }
      }
      checkCurrent();
    } catch (_) {
      await rollback();
      rethrow;
    }
  }

  Future<void> rollback() async {
    for (final entry in _backups.entries.toList().reversed) {
      final file = File(entry.key);
      if (entry.value == null) {
        if (await file.exists()) await file.delete();
      } else {
        await _atomicBytes(file, entry.value!);
      }
    }
    _backups.clear();
  }

  void commit() {
    _session._baseline = _next;
    _backups.clear();
  }
}

Future<void> _atomicBytes(File target, List<int> bytes) async {
  final temporary = File(
    '${target.path}.mcdev-${Random.secure().nextInt(1 << 32)}',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<Directory> preparePythonReloadDll(
  String runtimes,
  File executable,
) async {
  if ((await sha256.bind(executable.openRead()).first).toString() !=
      lanGameHash) {
    throw const DevelopmentStorageException(
      'Python 热重载仅支持已校验的 3.10.0.420447 x64 游戏。',
    );
  }
  final directory = Directory(p.join(runtimes, 'python-reload-v1'));
  await directory.create(recursive: true);
  for (final entry in {
    'python-reload.dll': pythonReloadDllHash,
    lanInjectorFile: lanInjectorHash,
  }.entries) {
    final target = File(p.join(directory.path, entry.key));
    if (await target.exists() &&
        (await sha256.bind(target.openRead()).first).toString() ==
            entry.value) {
      continue;
    }
    final data = await rootBundle.load('assets/development/${entry.key}');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != entry.value) {
      throw const DevelopmentStorageException('Python 热重载组件校验失败。');
    }
    await _atomicBytes(target, bytes);
  }
  return directory;
}

class PythonReloadBridge {
  PythonReloadBridge._(
    this.directory,
    this.nonce,
    this.gameDirectory,
    this.roots,
  );
  static const packName = 'mcdev_python_reload';
  static const packUuid = 'ad9940e5-755e-422c-8cb5-3d004ef11ea2';
  static const scriptsName = 'mcdevPythonReloadScripts';
  final Directory directory;
  final String nonce;
  final String gameDirectory;
  final List<String> roots;
  String? epoch;
  int _sequence = -1;
  DateTime? _heartbeat;
  bool _closed = false;
  bool get ready =>
      !_closed &&
      epoch != null &&
      _heartbeat != null &&
      DateTime.now().difference(_heartbeat!) < const Duration(seconds: 8);
  String get nativeLogPath => p.join(directory.path, 'native.json');
  Map<String, String> get environment => {
    'MCDEV_PYTHON_RELOAD_DIRECTORY': gameDirectory,
    'MCDEV_PYTHON_RELOAD_NONCE': nonce,
    'MCDEV_PYTHON_RELOAD_ROOTS': jsonEncode(roots),
    'MCDEV_PYTHON_RELOAD_LOG': p.windows.join(gameDirectory, 'native.json'),
  };

  static Future<PythonReloadBridge> create({
    required String behaviorPacks,
    required String testDirectory,
    required String Function(String) gamePath,
    required List<String> roots,
  }) async {
    final nonce = List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final directory = Directory(p.join(testDirectory, 'python-reload-$nonce'));
    await directory.create(recursive: true);
    final pack = Directory(p.join(behaviorPacks, packName));
    if (await FileSystemEntity.type(pack.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const DevelopmentStorageException('Python 热重载辅助包目录不能使用符号链接。');
    }
    if (await pack.exists()) {
      await rejectTreeLinks(pack.path);
      final manifest = jsonDecode(
        await File(p.join(pack.path, 'manifest.json')).readAsString(),
      );
      if (manifest is! Map || manifest['header']?['uuid'] != packUuid) {
        throw const DevelopmentStorageException('Python 热重载辅助包目录已被其他项目占用。');
      }
    }
    final scripts = Directory(p.join(pack.path, scriptsName));
    await scripts.create(recursive: true);
    await File(p.join(pack.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'format_version': 2,
        'header': {
          'name': 'MCDev Python Reload',
          'description': 'Local Python reload bridge',
          'uuid': packUuid,
          'version': [1, 0, 0],
          'min_engine_version': [1, 18, 0],
        },
        'modules': [
          {
            'type': 'data',
            'uuid': '7f142ab2-bd13-4236-b209-8e48ba2d5efc',
            'version': [1, 0, 0],
          },
        ],
      }),
    );
    final files = {
      '__init__.py': '',
      'modMain.py': _reloadModMain,
      '_mcdev_py_reload.py': await rootBundle.loadString(
        'tools/python_reload/runtime.py',
      ),
    };
    for (final entry in files.entries) {
      final file = File(p.join(scripts.path, entry.key));
      await file.writeAsString(entry.value);
      for (final suffix in ['c', 'o']) {
        final cached = File('${file.path}$suffix');
        if (await cached.exists()) await cached.delete();
      }
    }
    return PythonReloadBridge._(
      directory,
      nonce,
      gamePath(directory.path),
      roots,
    );
  }

  Future<Map<String, dynamic>?> poll() async {
    if (_closed) return null;
    try {
      final file = File(p.join(directory.path, 'report.json'));
      if (await file.length() > 128 * 1024) return null;
      final report = jsonDecode(await file.readAsString());
      if (report is! Map<String, dynamic> ||
          report['nonce'] != nonce ||
          report['epoch'] is! String ||
          report['sequence'] is! int) {
        return null;
      }
      if (epoch != report['epoch'] || _sequence != report['sequence']) {
        epoch = report['epoch'] as String;
        _sequence = report['sequence'] as int;
        _heartbeat = DateTime.now();
      }
      return report;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, dynamic>> request({
    required String id,
    required String operation,
    required String worldEpoch,
    required List<Map<String, Object>> files,
    required void Function() checkCurrent,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    checkCurrent();
    if (_closed || epoch != worldEpoch) {
      throw const DevelopmentStorageException('测试世界已变化，请重新执行热重载。');
    }
    final request = File(p.join(directory.path, 'request.json'));
    final bytes = utf8.encode(
      jsonEncode({
        'nonce': nonce,
        'epoch': worldEpoch,
        'id': id,
        'operation': operation,
        'files': files,
      }),
    );
    if (bytes.length > 48 * 1024 * 1024) {
      throw const DevelopmentStorageException('本次 Python 修改过多，请重新启动测试游戏。');
    }
    await _atomicBytes(request, bytes);
    final deadline = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        checkCurrent();
        final report = await poll();
        if (_closed || epoch != worldEpoch) {
          throw const DevelopmentStorageException('测试世界已变化，请重新执行热重载。');
        }
        final result = report?['result'];
        if (result is Map<String, dynamic> &&
            result['id'] == id &&
            result['operation'] == operation) {
          return result;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw TimeoutException('Python 热重载未收到游戏确认，请返回游戏后重试。');
    } finally {
      await _removeRequest();
    }
  }

  Future<void> close() async {
    _closed = true;
    await _removeRequest();
  }

  Future<void> _removeRequest() async {
    final request = File(p.join(directory.path, 'request.json'));
    try {
      if (await request.exists()) await request.delete();
    } on FileSystemException {
      // The close path and a cancelled request may remove the same file.
    }
  }
}

const _reloadModMain = r'''# -*- coding: utf-8 -*-
import time
from mod.common.mod import Mod
import mod.client.extraClientApi as clientApi
from mcdevPythonReloadScripts import _mcdev_py_reload

@Mod.Binding(name="MCDevPythonReload", version="1.0.0")
class ReloadMod(object):
    @Mod.InitClient()
    def InitClient(self):
        clientApi.RegisterSystem("MCDevPythonReload", "Reload", "mcdevPythonReloadScripts.modMain.ReloadSystem")

class ReloadSystem(clientApi.GetClientSystemCls()):
    def __init__(self, namespace, name):
        super(ReloadSystem, self).__init__(namespace, name)
        self.epoch = "%d-%d" % (int(time.time() * 1000000), id(self))
        self.ListenForEvent(clientApi.GetEngineNamespace(), clientApi.GetEngineSystemName(), "OnScriptTickClient", self, self.OnTick)

    def OnTick(self, *args):
        _mcdev_py_reload.tick(self.epoch)

    def Destroy(self):
        self.UnListenForEvent(clientApi.GetEngineNamespace(), clientApi.GetEngineSystemName(), "OnScriptTickClient", self, self.OnTick)
''';
