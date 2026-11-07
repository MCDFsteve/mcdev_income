// Explicit opt-in on Windows. Uses an isolated copy, never the user's projects.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/game_graphics.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'development_test.dart' show MemoryPreferences;
import 'live_item_info_smoke.dart' show capture;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'native RenderDragon switches Vibrant Visuals through the game setting',
    () async {
      final target = Platform.environment['MCDEV_LIVE_VIBRANT_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_AI_GAME_SOURCE'];
      final assets = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      final version = Platform.environment['MCDEV_LIVE_VIBRANT_VERSION'];
      if (!Platform.isWindows ||
          target == null ||
          source == null ||
          assets == null ||
          version == null ||
          p.equals(target, source) ||
          p.isWithin(source, target) ||
          p.isWithin(target, source)) {
        throw StateError('Windows, isolated root, source and version required');
      }
      final account = await FilePreferences.open(mcdevHome());
      final activeRoot =
          account.getString(DevelopmentStorage.preferenceKey) ?? source;
      if (p.equals(target, activeRoot) ||
          p.isWithin(activeRoot, target) ||
          p.isWithin(target, activeRoot)) {
        throw StateError('Refusing the live development directory');
      }
      CoreRuntime.preferences = () async => account;
      CoreRuntime.system = 'Windows';
      binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
        message,
      ) async {
        if (message == null) return null;
        final key = utf8.decode(
          message.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        final bundled = File(p.join(assets, key));
        final file = !key.startsWith('tools/') && await bundled.exists()
            ? bundled
            : File(p.join(Directory.current.path, key));
        return await file.exists()
            ? ByteData.sublistView(await file.readAsBytes())
            : null;
      });
      final preferences = MemoryPreferences();
      final storage = NativeDevelopmentStorage(
        preferences: preferences,
        defaultRoot: target,
        lockPath: p.join(p.dirname(target), 'vibrant-storage.lock'),
      );
      await storage.initialize();
      final game = Directory(p.join(target, 'games', version));
      if (!await game.exists()) {
        await game.parent.create(recursive: true);
        final copy = await Process.run('robocopy', [
          p.join(source, 'games', version),
          game.path,
          '/E',
          '/NFL',
          '/NDL',
          '/NJH',
          '/NJS',
          '/NP',
        ]);
        // Robocopy reports success with any exit code below 8.
        expect(copy.exitCode, lessThan(8));
      }
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'vibrant',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );

      Future<File> optionsFile() async =>
          (await Directory(host.gamePrefix)
                  .list(recursive: true, followLinks: false)
                  .where(
                    (item) =>
                        item is File && p.basename(item.path) == 'options.txt',
                  )
                  .cast<File>()
                  .toList())
              .single;
      Future<String?> setting() async {
        final text = await (await optionsFile()).readAsString(
          encoding: gameOptionsEncoding,
        );
        return RegExp(
          r'^graphics_mode:(.*?)\r?$',
          multiLine: true,
        ).firstMatch(text)?.group(1);
      }

      Future<String?> run(bool vibrant, String shot) async {
        await host.chooseVibrantVisuals(vibrant);
        expect(host.error, isNull);
        final lifetime = host.launchTest(
          worldName: '灵动视效隔离验证',
          creative: true,
          menuOnly: false,
          seed: '20261107',
        );
        try {
          var log = '';
          for (var i = 0; i < 300 && !log.contains('世界脚本已运行'); i++) {
            if (!host.running && host.error != null) {
              throw StateError(host.error!);
            }
            final file = host.logPath == null ? null : File(host.logPath!);
            if (file != null && await file.exists()) {
              log = await file.readAsString();
            }
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          expect(log, contains('世界脚本已运行'), reason: '${host.logPath}');
          await Future<void>.delayed(const Duration(seconds: 30));
          final during = await setting();
          await capture(shot);
          final hits = [
            for (final line in LineSplitter.split(
              await File(host.logPath!).readAsString(),
            ))
              if (RegExp(
                r'deferred|vibrant|renderdragon|d3d1[12]|fallback',
                caseSensitive: false,
              ).hasMatch(line))
                line.substring(0, line.length.clamp(0, 200)),
          ];
          stdout.writeln(
            'VIBRANT $vibrant running=${host.running} '
            'graphics_mode=$during log=${jsonEncode(hits.take(12).toList())}',
          );
          expect(host.running, isTrue, reason: 'The game must stay open');
          return during;
        } finally {
          await host.stopGame();
          await lifetime;
        }
      }

      try {
        await host.refresh();
        await host.chooseVersion(version);
        await host.chooseRenderer(GameRenderer.renderDragon);
        expect(host.vibrantVisualsSupported, isTrue);
        await host.chooseNewWorld(true);
        host.selectedPacks.clear();
        final shots = Platform.environment['MCDEV_LIVE_VIBRANT_SHOTS']!;
        await run(false, p.join(shots, 'off.png'));
        final original = await setting();
        await host.chooseNewWorld(false);
        expect(await run(true, p.join(shots, 'on.png')), '2');
        expect(await setting(), original, reason: 'Restored after exit');
        stdout.writeln('VIBRANT LIVE PASS: restored graphics_mode=$original');
      } finally {
        host.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_VIBRANT'] != '1',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
