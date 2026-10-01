// Explicit opt-in: installs a current game only in the separate diagnostic
// snapshot, using the launcher's production download and startup paths.
import 'dart:convert';
import 'dart:io';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'current game renderer starts through the isolated production launcher',
    () async {
      final path = Platform.environment['MCDEV_LIVE_PERFORMANCE_ROOT'];
      final version = Platform.environment['MCDEV_LIVE_GAME_VERSION'];
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
        await launcher.chooseRenderer(
          Platform.environment['MCDEV_LIVE_RENDERER'] == 'dragon'
              ? GameRenderer.renderDragon
              : GameRenderer.openGL,
        );
        // This is a copied save; user-selected projects and original saves remain untouched.
        launched = launcher.launchTest(
          worldName: '渲染器隔离验证',
          creative: true,
          menuOnly: false,
        );
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (!launcher.running && DateTime.now().isBefore(deadline)) {
          if (launcher.error != null) {
            throw StateError('Game launch failed (details withheld)');
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
        expect(config['render_engine'], launcher.effectiveRenderer.configValue);
        expect(config['client_type'], 1);
        await Future<void>.delayed(const Duration(seconds: 60));
        expect(
          launcher.running,
          isTrue,
          reason: 'Game must stay alive after renderer initialization',
        );
        final result = {
          'version': version,
          'renderer': launcher.effectiveRenderer.name,
          'limit_60_fps': launcher.limit60Fps,
          'running_after_60_seconds': true,
          'log_path': launcher.logPath,
        };
        await File(
          p.join(
            p.dirname(root),
            'renderer-${launcher.effectiveRenderer.name}.json',
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
