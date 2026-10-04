import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'development_storage.dart';

const lanPatchVersion = '3.10.0.420447';
const lanGameHash =
    '9be281dbe08bc591336680d5a50f94d87f3c57ee75b3afcb3cabdf03347e0269';
const lanPatchHash =
    '426bcea3d8fcf451e7686a149deb39ee6f0500ecd0fc21693d376ec4aefed10c';
// This existing helper checks the exact process path and waits for 3.10's
// unpacked code before loading the DLL. Its renderer DLL is not needed here.
const lanInjectorFile = 'renderer-inject.exe';
const lanInjectorHash =
    '8a8fbedd6b058e02c0994c10a957c8185ace161181c6740f0989268f70153f8f';
const lanPatchAssets = {
  'lan-patch.dll': lanPatchHash,
  lanInjectorFile: lanInjectorHash,
};

bool supportsLanPatch(String? version) => version == lanPatchVersion;

Future<bool> _matches(File file, String hash) async =>
    await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file &&
    (await sha256.bind(file.openRead()).first).toString() == hash;

/// Must pass before injection. A matching version label alone is insufficient;
/// the original downloaded executable's entire SHA-256 must also match.
Future<void> validateLanGame(String version, File executable) async {
  if (!supportsLanPatch(version) || !await _matches(executable, lanGameHash)) {
    throw const DevelopmentStorageException(
      '局域网适配与游戏文件不匹配，请重新下载 3.10.0.420447 Haldra x64。',
    );
  }
}

/// Stage only hash-pinned helpers, separate from the game and renderer patch.
/// The DLL's ready log must still be observed: a successful injection only
/// confirms that Windows loaded it, not that both native signatures matched.
Future<Directory> prepareLanPatch(
  String runtimes, {
  AssetBundle? bundle,
}) async {
  final source = bundle ?? rootBundle;
  final directory = Directory(p.join(runtimes, 'lan-patch-v1'));
  final pending = <String, Uint8List>{};
  for (final entry in lanPatchAssets.entries) {
    if (await _matches(File(p.join(directory.path, entry.key)), entry.value)) {
      continue;
    }
    final data = await source.load('assets/development/${entry.key}');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != entry.value) {
      throw const DevelopmentStorageException('局域网适配资源校验失败，未注入。');
    }
    pending[entry.key] = bytes;
  }
  if (pending.isEmpty) return directory;
  await directory.create(recursive: true);
  // Separate temporary directories allow tabs to prepare the same pinned
  // helpers concurrently without sharing or truncating a temporary file.
  final stage = await directory.createTemp('.prepare-');
  try {
    for (final entry in pending.entries) {
      final file = File(p.join(stage.path, entry.key));
      await file.writeAsBytes(entry.value, flush: true);
      await file.rename(p.join(directory.path, entry.key));
    }
  } finally {
    await stage.delete(recursive: true);
  }
  return directory;
}
