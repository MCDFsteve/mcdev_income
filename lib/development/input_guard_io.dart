import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'development_storage.dart';

const fullscreenShortcutGuardHash =
    '772e09039ad6f3930c50e5ec4c84e023578da1fe46d3ea30f71abe398efc30a0';
const _asset = 'assets/development/fullscreen-shortcut.dylib';

/// Independent input helper; the game's renderer and performance DLLs are
/// unchanged. A verified cache can be reused after moving the data directory.
Future<File> prepareFullscreenShortcutGuard(
  String runtimes, {
  AssetBundle? bundle,
}) async {
  final directory = Directory(p.join(runtimes, 'input-guard-v1'));
  final target = File(p.join(directory.path, 'fullscreen-shortcut.dylib'));
  if (target.path.contains(':')) {
    throw const DevelopmentStorageException('游戏输入组件路径不能包含冒号，请调整开发数据目录。');
  }
  if (await target.exists() &&
      (await sha256.bind(target.openRead()).first).toString() ==
          fullscreenShortcutGuardHash) {
    return target;
  }
  final data = await (bundle ?? rootBundle).load(_asset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() != fullscreenShortcutGuardHash) {
    throw const DevelopmentStorageException('游戏输入组件校验失败，未启动。');
  }
  await directory.create(recursive: true);
  final staging = await directory.createTemp('.input-guard-');
  try {
    final temporary = File(p.join(staging.path, 'fullscreen-shortcut.dylib'));
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  } finally {
    await staging.delete(recursive: true);
  }
  return target;
}

/// Apply only to the real game loader's Process.start environment, leaving
/// separately launched Wine setup, server and patch helpers on their old path.
Map<String, String> fullscreenShortcutEnvironment(
  String library, {
  Map<String, String>? inherited,
}) {
  final previous = (inherited ?? Platform.environment)['DYLD_INSERT_LIBRARIES'];
  return {
    'DYLD_INSERT_LIBRARIES': [
      if (previous != null && previous.isNotEmpty) previous,
      library,
    ].join(':'),
    'MCDEV_FULLSCREEN_SHORTCUT': '0',
  };
}
