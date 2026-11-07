import 'dart:convert';
import 'dart:io';

import 'development_storage.dart';
import 'game_graphics.dart';

/// Mutes a test through the game's own master volume, then restores only that
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
