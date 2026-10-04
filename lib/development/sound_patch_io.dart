import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'development_storage.dart';
import 'game_graphics.dart';
import 'lan_patch_io.dart' show lanGameHash, lanInjectorFile, lanInjectorHash;
import 'performance_patch_io.dart' show injectPerformancePatch;
import 'sound_patch.dart';
export 'sound_patch.dart';

const soundPatchHash =
    '14e84826d0ee71fea0751154a47c76a72a4cb56b51b0a9c4086416323b5250c0';
const soundFmodHash =
    '94907cdc342771fb1cecec031b85174ebc4d2fe723118e80b87012bac6623b57';
const soundPatchAssets = {
  'sound-patch.dll': soundPatchHash,
  lanInjectorFile: lanInjectorHash,
};

Future<bool> _matches(File file, String hash) async =>
    await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file &&
    (await sha256.bind(file.openRead()).first).toString() == hash;

Future<void> validateSoundGame(String version, File executable) async {
  if (!supportsSoundPatch(version) ||
      !await _matches(executable, lanGameHash) ||
      !await _matches(
        File(p.join(executable.parent.path, 'fmod64.dll')),
        soundFmodHash,
      )) {
    throw const DevelopmentStorageException(
      '关闭声音仅支持已校验的 3.10.0.420447 x64 游戏，请重新下载或取消勾选。',
    );
  }
}

Future<Directory> prepareSoundPatch(
  String runtimes, {
  AssetBundle? bundle,
}) async {
  final source = bundle ?? rootBundle;
  final directory = Directory(p.join(runtimes, 'sound-patch-v1'));
  final pending = <String, Uint8List>{};
  for (final entry in soundPatchAssets.entries) {
    if (await _matches(File(p.join(directory.path, entry.key)), entry.value)) {
      continue;
    }
    final data = await source.load('assets/development/${entry.key}');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != entry.value) {
      throw const DevelopmentStorageException('关闭声音组件校验失败，未注入。');
    }
    pending[entry.key] = bytes;
  }
  if (pending.isEmpty) return directory;
  await directory.create(recursive: true);
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

/// Only a native record of output=NOSOUND proves that the running audio system
/// is silent. Loaded/armed alone is not success. Keep monitoring later failures.
Future<void> activateSoundPatch({
  required Directory files,
  required String executable,
  required String? wine,
  required int targetPid,
  required Map<String, String> environment,
  required String Function(String) gamePath,
  required File log,
  required Future<void> exited,
  required bool Function() current,
  required void Function() onReady,
  Duration readyTimeout = const Duration(seconds: 70),
}) async {
  final loaded = await injectPerformancePatch(
    wine: wine,
    targetPid: targetPid,
    environment: environment,
    helper: gamePath(p.join(files.path, lanInjectorFile)),
    dll: gamePath(p.join(files.path, 'sound-patch.dll')),
    executable: gamePath(executable),
    cancelWhen: exited,
  );
  if (!current()) return;
  if (!loaded) throw const DevelopmentStorageException('关闭声音 DLL 注入失败。');
  final deadline = DateTime.now().add(readyTimeout);
  var ready = false;
  while (current()) {
    if (await log.exists()) {
      try {
        final record = jsonDecode(await log.readAsString()) as Map;
        if (record['state'] == 'failed') {
          throw DevelopmentStorageException(
            '关闭声音 DLL 初始化失败：${record['reason']}。',
          );
        }
        if (record['state'] == 'ready' && record['output'] == 2 && !ready) {
          ready = true;
          if (current()) onReady();
        }
      } on FormatException {
        // A filesystem may briefly expose a replaced record during startup.
      }
    }
    if (!ready && DateTime.now().isAfter(deadline)) {
      throw const DevelopmentStorageException('关闭声音 DLL 初始化超时。');
    }
    await Future<void>.delayed(Duration(milliseconds: ready ? 500 : 100));
  }
}

/// Silence the window before DLL readiness, then restore only the master-volume
/// option on exit. The sidecar also recovers after an interrupted app session.
class SoundOptionsGuard {
  SoundOptionsGuard(this.options);
  final File options;
  File get backup => File('${options.path}.mcdev-sound-backup');

  Future<void> capture(String original) async {
    final values = original
        .split(RegExp(r'\r?\n'))
        .where((line) => line.startsWith('audio_main:'));
    final value = values.isEmpty
        ? '1'
        : values.last.substring('audio_main:'.length);
    final staging = File('${backup.path}.tmp');
    await staging.writeAsString(jsonEncode({'audio_main': value}), flush: true);
    await staging.rename(backup.path);
  }

  Future<void> restore() async {
    if (!await backup.exists()) return;
    final record = jsonDecode(await backup.readAsString()) as Map;
    final value = record['audio_main'];
    if (value is! String || !RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
      throw const DevelopmentStorageException('无法恢复游戏音量设置，请检查启动目录。');
    }
    final current = await options.exists()
        ? await options.readAsString(encoding: gameOptionsEncoding)
        : '';
    final staging = File('${options.path}.mcdev-sound-tmp');
    await staging.writeAsString(
      mergeGameOptions(current, {'audio_main': value}),
      flush: true,
    );
    await staging.rename(options.path);
    await backup.delete();
  }
}
