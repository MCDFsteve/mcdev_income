// Explicit opt-in: installs a current game only in the separate diagnostic
// snapshot, using the launcher's production download and startup paths.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/render_dragon.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'live_performance_smoke.dart' show IsolatedGraphicsPreferences;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'current game renderer starts through the isolated production launcher',
    () async {
      final path = Platform.environment['MCDEV_LIVE_PERFORMANCE_ROOT'];
      final version = Platform.environment['MCDEV_LIVE_GAME_VERSION'];
      final assets = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      if (path == null || version == null) {
        throw StateError('Explicit isolated root and game version required');
      }
      final root = await Directory(path).resolveSymbolicLinks();
      final account = await FilePreferences.open(mcdevHome());
      final original = await Directory(
        account.getString(DevelopmentStorage.preferenceKey) ??
            p.join(
              Platform.environment['HOME']!,
              'Library',
              'Application Support',
              'mcdev_income',
              'development',
            ),
      ).resolveSymbolicLinks();
      if (p.equals(root, original) || p.isWithin(original, root)) {
        throw StateError('Refusing original development data');
      }
      final prefix = await Directory(
        p.join(root, 'prefixes', 'game'),
      ).resolveSymbolicLinks();
      if (!p.isWithin(root, prefix)) {
        throw StateError('Prefix must be isolated');
      }
      CoreRuntime.preferences = () async => account;
      CoreRuntime.system = 'Mac';
      if (assets != null) {
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
          final file = File(p.join(assets, key));
          return await file.exists()
              ? ByteData.sublistView(await file.readAsBytes())
              : null;
        });
      }
      final prefs = IsolatedGraphicsPreferences(root);
      final storage = NativeDevelopmentStorage(
        preferences: prefs,
        defaultRoot: root,
        lockPath: p.join(p.dirname(root), 'locks', 'launcher.lock'),
      );
      final launcher = NativeDevelopmentLauncher(
        storage,
        prefs,
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? launched;
      final options = File(
        p.join(
          prefix,
          'drive_c/users/dfsteve/AppData/Roaming/MinecraftPE_Netease/minecraftpe/options.txt',
        ),
      );
      final originalOptions = await options.readAsString();
      final vibrant = Platform.environment['MCDEV_LIVE_VIBRANT'] == '1';
      String? gameLog;
      String? rendererLog;
      String? previous;
      launcher.addListener(() {
        final message = launcher.progress?.message ?? launcher.notice;
        if (message != null && message != previous) {
          previous = message;
          stdout.writeln('Isolated graphics: $message');
        }
      });
      try {
        await launcher.refresh();
        if (!launcher.games.any((game) => game.version == version)) {
          await launcher.installVersion(version);
          if (launcher.error != null) {
            throw StateError('Isolated installation failed (details withheld)');
          }
        }
        await launcher.chooseVersion(version);
        if (Platform.environment['MCDEV_LIVE_NO_MODS'] == '1') {
          // In-memory only: isolate built-in skins from player model overrides.
          // Never save the changed selection to projects.json.
          launcher.selectedPacks.clear();
        }
        await launcher.choosePlayerSkin(
          Platform.environment['MCDEV_LIVE_SKIN'] == 'alex'
              ? TestPlayerSkin.alex
              : TestPlayerSkin.steve,
        );
        await launcher.chooseFullscreenShortcut(
          Platform.environment['MCDEV_LIVE_FULLSCREEN_SHORTCUT'] == '1',
        );
        final requestedRenderer =
            Platform.environment['MCDEV_LIVE_RENDERER'] == 'dragon'
            ? GameRenderer.renderDragon
            : GameRenderer.openGL;
        if (launcher.rendererSwitchSupported) {
          await launcher.chooseRenderer(requestedRenderer);
        } else {
          expect(requestedRenderer, GameRenderer.openGL);
          expect(launcher.effectiveRenderer, GameRenderer.openGL);
        }
        if (launcher.vibrantVisualsSupported) {
          await launcher.chooseVibrantVisuals(vibrant);
        }
        final newWorld = Platform.environment['MCDEV_LIVE_NEW_WORLD'] == '1';
        await launcher.chooseNewWorld(newWorld);
        // This is a copied save; user-selected projects and original saves remain untouched.
        launched = launcher.launchTest(
          worldName: '渲染器隔离验证',
          creative: true,
          menuOnly: false,
          seed: Platform.environment['MCDEV_LIVE_WORLD_SEED'],
        );
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (!launcher.running && DateTime.now().isBefore(deadline)) {
          if (launcher.error != null) {
            final safeReason = [
              '开发者登录验证失败，请在设置中重新登录。',
              '开发者登录无法取得游戏访问权限，请在设置中重新登录。',
              '请先使用软件现有登录入口登录开发者账号。',
              'Wine 游戏窗口组件与支持的版本不匹配。',
              '准备 Wine 游戏窗口组件失败。',
              '测试游戏图标资源校验失败。',
            ].where((message) => launcher.error!.contains(message)).firstOrNull;
            throw StateError(
              'Game launch failed (${safeReason ?? 'details withheld'})',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(launcher.running, isTrue);
        final config =
            jsonDecode(
                  await File(
                    p.join(prefix, 'drive_c', 'MCDevTests', 'test.cppconfig'),
                  ).readAsString(),
                )
                as Map;
        expect(
          config['skin_info']['slim'],
          launcher.playerSkin == TestPlayerSkin.alex,
        );
        expect(
          config['skin_info']['skin_iid'],
          launcher.playerSkin == TestPlayerSkin.alex ? '-2' : '-1',
        );
        expect(config['skin_info']['in_package'], isFalse);
        expect(config['skin_info']['sync'], isTrue);
        if (newWorld) {
          expect(config['world_info']['level_id'], startsWith('mcdev_test_'));
          expect(
            config['world_info']['seed'],
            (Platform.environment['MCDEV_LIVE_WORLD_SEED'] ?? '').trim(),
          );
        }
        expect(
          config['skin_info']['skin'],
          p.windows.join(
            r'C:\MCDevTests\skins',
            launcher.playerSkin.textureFile,
          ),
        );
        expect(
          await File(
            p.join(
              prefix,
              'drive_c',
              'MCDevTests',
              'skins',
              launcher.playerSkin.textureFile,
            ),
          ).readAsBytes(),
          await File(
            p.join(
              launcher.games
                  .singleWhere((game) => game.version == version)
                  .directory,
              'data',
              'skin_packs',
              'vanilla',
              launcher.playerSkin.textureFile,
            ),
          ).readAsBytes(),
        );
        if (launcher.rendererSwitchSupported) {
          expect(
            config['render_engine'],
            launcher.effectiveRenderer.configValue,
          );
          expect(config['client_type'], 1);
        } else {
          expect(config.containsKey('render_engine'), false);
          expect(config.containsKey('client_type'), false);
        }
        await Future<void>.delayed(const Duration(seconds: 60));
        expect(
          launcher.running,
          isTrue,
          reason: 'Game must stay alive after renderer initialization',
        );
        expect(
          launcher.error,
          isNull,
          reason: 'Renderer activation must succeed',
        );
        // Optional time for direct CUA window capture; keep the same isolated
        // production launch and exit checks without changing user preferences.
        final holdSeconds = int.parse(
          Platform.environment['MCDEV_LIVE_HOLD_SECONDS'] ?? '0',
        );
        if (holdSeconds < 0 || holdSeconds > 1800) {
          throw StateError('Invalid window observation duration');
        }
        if (holdSeconds > 0) {
          stdout.writeln('Isolated game ready for direct window observation');
          final observationEnd = DateTime.now().add(
            Duration(seconds: holdSeconds),
          );
          final stopPath = Platform.environment['MCDEV_LIVE_STOP_FILE'];
          while (DateTime.now().isBefore(observationEnd)) {
            if (stopPath != null && await File(stopPath).exists()) break;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          expect(launcher.running, isTrue);
        }
        gameLog = launcher.logPath;
        if (launcher.renderDragonCompatibilitySupported &&
            launcher.effectiveRenderer == GameRenderer.renderDragon) {
          rendererLog = gameLog!.replaceFirst('test-', 'renderer-');
          final native = await File(rendererLog).readAsString();
          expect(native, contains('"renderer_patch":"active"'));
          expect(native, contains('"backend":2'));
          expect(native, contains('"vibrant_supported":true'));
          if (vibrant) {
            expect(native, contains('"structured_buffer":"ready"'));
            expect(native, contains('"structured_upload":"default_resource"'));
            expect(native, isNot(contains('"structured_buffer":"failed"')));
            expect(
              native,
              isNot(contains('"structured_upload":"invalid_range"')),
            );
          }
          expect(
            await options.readAsString(),
            contains('graphics_mode:${vibrant ? 2 : 1}'),
          );
        }
        await launcher.stopGame();
        await launched.timeout(const Duration(seconds: 45));
        launched = null;
        expect(launcher.running, isFalse);
        expect(
          launcher.error,
          isNull,
          reason: 'Requested exit must complete without launcher errors',
        );
        final console = utf8.decode(
          await File(gameLog!).readAsBytes(),
          allowMalformed: true,
        );
        final inputGuardLoaded = console.contains(
          '[MCDev input] Command+Shift fullscreen shortcut disabled',
        );
        expect(
          inputGuardLoaded,
          !launcher.fullscreenShortcut,
          reason: 'Only disabled fullscreen shortcuts load the input guard',
        );
        for (final error in [
          'BGFX: Fatal error',
          'Assertion failed:',
          'Unhandled exception',
          'Failed to create shader',
          'RefCount is',
        ]) {
          expect(
            console.contains(error),
            isFalse,
            reason: 'Renderer failure marker: $error',
          );
        }
        if (rendererLog != null) {
          final restored = await options.readAsString();
          for (final key in ['graphics_mode', 'gfx_msaa']) {
            final pattern = RegExp('^$key:.*', multiLine: true);
            expect(
              pattern.firstMatch(restored)?.group(0),
              pattern.firstMatch(originalOptions)?.group(0),
            );
          }
        }
        final result = {
          'version': version,
          'renderer': launcher.effectiveRenderer.name,
          'limit_60_fps': launcher.limit60Fps,
          'fullscreen_shortcut': launcher.fullscreenShortcut,
          'input_guard_loaded': inputGuardLoaded,
          'running_after_60_seconds': true,
          'vibrant_visuals': vibrant,
          'requested_exit_complete': true,
          'renderer_assertions': false,
          'temporary_options_restored': rendererLog != null,
          'visual_validation': 'pending_direct_window_capture',
          'log_path': gameLog,
          'renderer_log_path': rendererLog,
          'supported_version': renderDragonPatchVersion,
        };
        await File(
          p.join(
            p.dirname(root),
            'renderer-${launcher.effectiveRenderer.name}-${vibrant ? "vibrant" : "forward"}.json',
          ),
        ).writeAsString(jsonEncode(result), flush: true);
        stdout.writeln('Isolated renderer result: ${jsonEncode(result)}');
      } finally {
        if (launcher.running) await launcher.stopGame();
        if (launched != null) {
          await launched.timeout(const Duration(seconds: 45));
        }
        launcher.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}
