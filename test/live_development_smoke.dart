// Explicit opt-in integration diagnostic; never runs in the normal test suite.
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/storage/file_preferences.dart';
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/launcher_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'real downloaded runtime, game, mod, and test launch',
    () async {
      if (Platform.environment['MCDEV_LIVE_DEVELOPMENT'] != '1') {
        throw StateError('Explicit MCDEV_LIVE_DEVELOPMENT=1 required');
      }
      final preferences = await FilePreferences.open(mcdevHome());
      CoreRuntime.preferences = () async => preferences;
      CoreRuntime.system = 'Mac';
      final storage = await openDevelopmentStorage(preferences);
      await storage.initialize();
      final cached = File(
        p.join(storage.paths.downloads, 'wine-stable-11.0_1.tar.xz'),
      );
      if (!await cached.exists())
        await File('/tmp/mcdev-wine11.tar.xz').copy(cached.path);
      final launcher = NativeDevelopmentLauncher(
        storage,
        preferences,
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      var last = '';
      launcher.addListener(() {
        final message =
            launcher.error ??
            launcher.progress?.message ??
            launcher.notice ??
            '';
        if (message != last) {
          last = message;
          print('Development: $message');
        }
      });
      await launcher.refresh();
      await launcher.installWine();
      expect(launcher.error, isNull);
      await launcher.queryLatest();
      expect(launcher.error, isNull);
      expect(launcher.latestPackage, isNotNull);
      print(
        'Existing Flutter login verified. Stable: ${launcher.latestPackage!.version}',
      );
      if (Platform.environment['MCDEV_LIVE_LAUNCH'] != '1') {
        launcher.dispose();
        return;
      }
      if (launcher.games.isEmpty) {
        await launcher.installLatest();
        expect(launcher.error, isNull);
      }
      expect(launcher.games, isNotEmpty);
      final project = Directory(
        p.join(storage.paths.root, 'projects', 'smoke-behavior'),
      );
      await project.create(recursive: true);
      await File(p.join(project.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'format_version': 2,
          'header': {
            'name': 'MCDev 验证包',
            'description': 'Flutter 模组装配验证',
            'uuid': '794c9e43-1145-4190-9834-56a9dba88a23',
            'version': [1, 0, 0],
            'min_engine_version': [1, 20, 0],
          },
          'modules': [
            {
              'type': 'data',
              'uuid': '895bc3f5-56b1-4215-87f2-964bc425cbaa',
              'version': [1, 0, 0],
            },
          ],
        }),
      );
      await Directory(
        p.join(project.path, 'functions'),
      ).create(recursive: true);
      await File(
        p.join(project.path, 'functions', 'mcdev_verify.mcfunction'),
      ).writeAsString(
        'say MCDev pack is loaded\ngive @s minecraft:diamond 1\n',
      );
      await launcher.importMods(project.path);
      expect(launcher.error, isNull);
      print(
        'Starting test game with MCDev validation pack. Root: ${storage.paths.root}',
      );
      await launcher.launchTest(
        worldName: 'Flutter 模组验证',
        creative: true,
        menuOnly: false,
      );
      print('Game closed.');
      expect(launcher.error, isNull);
      launcher.dispose();
    },
    timeout: const Timeout(Duration(hours: 1)),
  );
}
