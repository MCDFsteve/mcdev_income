// Explicit opt-in, isolated two-game integration check. Never uses live saves.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'development_test.dart' show MemoryPreferences;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'two real 3.10 sessions coexist and stopping one preserves the other',
    () async {
      final root = Platform.environment['MCDEV_LIVE_SESSIONS_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_SESSIONS_SOURCE'];
      final assets = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      if (root == null ||
          source == null ||
          assets == null ||
          p.equals(root, source)) {
        throw StateError(
          'Explicit separate diagnostic root, source and assets required',
        );
      }
      final account = await FilePreferences.open(mcdevHome());
      final original =
          account.getString(DevelopmentStorage.preferenceKey) ??
          p.join(
            Platform.environment['HOME']!,
            'Library/Application Support/mcdev_income/development',
          );
      final target = p.normalize(p.absolute(root));
      if (p.equals(target, original) ||
          p.isWithin(original, target) ||
          p.isWithin(target, original) ||
          p.isWithin(source, target) ||
          p.isWithin(target, source)) {
        throw StateError('Refusing overlapping game directories');
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
      final preferences = MemoryPreferences();
      final storage = NativeDevelopmentStorage(
        preferences: preferences,
        defaultRoot: target,
        lockPath: p.join(p.dirname(target), 'multi-session-storage.lock'),
      );
      await storage.initialize();
      const version = '3.10.0.420447';
      for (final relative in [
        'runtimes/wine-11.0_1-mcs-v1',
        'games/$version',
      ]) {
        final dest = Directory(p.join(target, relative));
        if (!await dest.exists()) {
          await dest.parent.create(recursive: true);
          final copy = await Process.run('/bin/cp', [
            '-cR',
            p.join(source, relative),
            dest.path,
          ]);
          expect(copy.exitCode, 0, reason: 'APFS diagnostic copy must succeed');
        }
      }
      final first = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'multi-a',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      final second = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'multi-b',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      final launches = <Future<void>>[];
      Future<void> waitRunning(NativeDevelopmentLauncher launcher) async {
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (!launcher.running && DateTime.now().isBefore(deadline)) {
          if (launcher.error != null) {
            throw StateError('Diagnostic launch failed; details withheld');
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        expect(launcher.running, isTrue);
      }

      try {
        var index = 0;
        for (final launcher in [first, second]) {
          index++;
          final project = Directory(p.join(target, 'projects', 'probe-$index'));
          await project.create(recursive: true);
          await File(p.join(project.path, 'manifest.json')).writeAsString(
            jsonEncode({
              'format_version': 2,
              'header': {
                'name': '多开验证 $index',
                'description': 'Isolated multi-window check',
                'uuid': '1ee4f11e-0000-4000-8000-00000000000$index',
                'version': [1, 0, 0],
                'min_engine_version': [1, 20, 0],
              },
              'modules': [
                {
                  'type': 'data',
                  'uuid': '2ee4f11e-0000-4000-8000-00000000000$index',
                  'version': [1, 0, 0],
                },
              ],
            }),
          );
          await launcher.refresh();
          await launcher.chooseVersion(version);
          await launcher.importMods(project.path);
          await launcher.chooseNewWorld(true);
          launches.add(
            launcher.launchTest(
              worldName: '多开验证 $index',
              creative: true,
              menuOnly: false,
              seed: '2026100$index',
            ),
          );
          await waitRunning(launcher);
          stdout.writeln(
            'Session $index running with independent prefix and project',
          );
        }
        expect(first.running && second.running, isTrue);
        expect(first.gamePrefix, isNot(second.gamePrefix));
        expect(first.logPath, isNot(second.logPath));
        for (final launcher in [first, second]) {
          final config = jsonDecode(
            await File(
              p.join(launcher.gamePrefix, 'drive_c/MCDevTests/test.cppconfig'),
            ).readAsString(),
          );
          expect(
            (config['world_info']['behavior_packs'] as List)
                .where((pack) => pack != 'mcdev_lan_bridge')
                .length,
            1,
          );
          expect(config['world_info']['level_id'], startsWith('mcdev_test_'));
        }
        stdout.writeln('BOTH_SESSIONS_READY');
        final stop = Platform.environment['MCDEV_LIVE_SESSIONS_STOP'];
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (stop != null &&
            !await File(stop).exists() &&
            DateTime.now().isBefore(deadline)) {
          expect(first.running && second.running, isTrue);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        await first.stopGame();
        expect(first.running, isFalse);
        await Future<void>.delayed(const Duration(seconds: 5));
        expect(second.running, isTrue);
        stdout.writeln('FIRST_STOPPED_SECOND_STILL_RUNNING');
        await second.stopGame();
        await Future.wait(launches);
        expect(second.running, isFalse);
        expect(first.error, isNull);
        expect(second.error, isNull);
      } finally {
        await first.stopGame();
        await second.stopGame();
        await Future.wait(launches);
        first.dispose();
        second.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_SESSIONS'] != '1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
