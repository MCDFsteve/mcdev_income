// Opt-in native smoke test; never runs as part of the ordinary unit suite.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mcdev_income/development/platform/game_window_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/platform/windows_game_runtime.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/test_session_io.dart';
import 'development_test.dart' show MemoryPreferences;

void main() {
  test(
    'native Windows game starts and writes only its isolated profile',
    () async {
      final source = Platform.environment['MCDEV_WINDOWS_GAME'];
      if (!Platform.isWindows || source == null) {
        throw StateError(
          'Set MCDEV_WINDOWS_GAME to an installed numeric game version.',
        );
      }
      final root = p.absolute('build', 'windows-runtime-smoke');
      final storage = NativeDevelopmentStorage(
        preferences: MemoryPreferences(),
        defaultRoot: root,
        lockPath: '$root.lock',
      );
      await storage.initialize();
      final runtime = WindowsGameRuntime(
        storage,
        'smoke',
        window: const HeadlessGameWindow(),
      );
      await runtime.prepare((_) {});
      final version = p.basename(source);
      final game = await prepareSessionGame(
        source: source,
        prefix: runtime.prefix,
        version: version,
      );
      final child = await runtime.start(
        executable: p.join(game, 'Minecraft.Windows.exe'),
        arguments: ['dc_tag1=mod_pc_no_launcher'],
        workingDirectory: game,
        version: version,
        displayName: 'MCDev Windows 验证',
        renderer: 'OpenGL',
        fullscreenShortcut: false,
      );
      final drains = [child.stdout.drain<void>(), child.stderr.drain<void>()];
      int? exit;
      unawaited(child.exitCode.then((value) => exit = value));
      try {
        final gameData = Directory(
          p.join(await runtime.roaming(), 'MinecraftPE_Netease'),
        );
        for (var attempt = 0; attempt < 60 && exit == null; attempt++) {
          if (await gameData.exists() && !await gameData.list().isEmpty) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(
          exit,
          isNull,
          reason: 'Native game exited before the profile became ready.',
        );
        expect(await gameData.exists(), isTrue);
        expect(await gameData.list().isEmpty, isFalse);
        await File(p.join(root, 'result.json')).writeAsString(
          jsonEncode({
            'version': version,
            'pid': child.pid,
            'native': true,
            'roaming': await runtime.roaming(),
            'gameDataCreated': true,
          }),
        );
      } finally {
        await runtime.stop(child);
        await runtime.terminateHelpers();
        await Future.wait(drains).timeout(const Duration(seconds: 5));
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
