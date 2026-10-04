// Explicit opt-in fixture for direct macOS menu inspection in an isolated world.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'live_performance_smoke.dart' show IsolatedGraphicsPreferences;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'macOS menus operate on their isolated test game',
    () async {
      final env = Platform.environment;
      final root = await Directory(
        env['MCDEV_LIVE_PERFORMANCE_ROOT']!,
      ).resolveSymbolicLinks();
      final app = env['MCDEV_CHROME_CLIENT_APP']!;
      final assets = p.join(
        app,
        'Contents/Frameworks/App.framework/Resources/flutter_assets',
      );
      final account = await FilePreferences.open(mcdevHome());
      final original = await Directory(
        account.getString(DevelopmentStorage.preferenceKey)!,
      ).resolveSymbolicLinks();
      if (p.equals(root, original) ||
          p.isWithin(original, root) ||
          p.isWithin(root, original)) {
        throw StateError('An independent diagnostic root is required');
      }
      final prefix = await Directory(
        p.join(root, 'prefixes/game'),
      ).resolveSymbolicLinks();
      if (!p.isWithin(root, prefix)) {
        throw StateError('Prefix must be isolated');
      }
      CoreRuntime.preferences = () async => account;
      CoreRuntime.system = 'Mac';
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
      final prefs = IsolatedGraphicsPreferences(root);
      final storage = NativeDevelopmentStorage(
        preferences: prefs,
        defaultRoot: root,
        lockPath: p.join(p.dirname(root), 'locks/menu-smoke.lock'),
      );
      final launcher = NativeDevelopmentLauncher(
        storage,
        prefs,
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? launched;
      try {
        await launcher.refresh();
        await launcher.chooseVersion(
          env['MCDEV_LIVE_GAME_VERSION'] ?? '3.10.0.420447',
        );
        launcher.selectedPacks.clear();
        if (launcher.rendererSwitchSupported) {
          await launcher.chooseRenderer(
            env['MCDEV_LIVE_RENDERER'] == 'dragon'
                ? GameRenderer.renderDragon
                : GameRenderer.openGL,
          );
        }
        await launcher.chooseNewWorld(true);
        launched = launcher.launchTest(
          worldName: 'macOS 菜单验证',
          creative: true,
          menuOnly: false,
        );
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (!launcher.running && DateTime.now().isBefore(deadline)) {
          if (launcher.error != null) {
            throw StateError('Diagnostic launch failed (details withheld)');
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        expect(launcher.running, isTrue);
        stdout.writeln('ISOLATED_MENU_GAME_RUNNING');
        final end = DateTime.now().add(const Duration(minutes: 20));
        final stop = env['MCDEV_LIVE_STOP_FILE'];
        while (launcher.running &&
            DateTime.now().isBefore(end) &&
            (stop == null || !await File(stop).exists())) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (launcher.running) await launcher.stopGame();
        await launched.timeout(const Duration(seconds: 45));
        launched = null;
        expect(launcher.error, isNull);
        stdout.writeln('ISOLATED_MENU_GAME_EXITED');
      } finally {
        if (launcher.running) await launcher.stopGame();
        if (launched != null) {
          await launched.timeout(const Duration(seconds: 45));
        }
        launcher.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_WINDOW_MENUS'] != '1',
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
