// Explicit opt-in. Uses isolated game/Wine copies, no live projects or saves.
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
    'checked launch injects NOSOUND and unchecked launch restores sound settings',
    () async {
      final target = Platform.environment['MCDEV_LIVE_SOUND_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_SOUND_SOURCE'];
      final assets = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      if (target == null ||
          source == null ||
          assets == null ||
          p.equals(target, source) ||
          p.isWithin(source, target) ||
          p.isWithin(target, source)) {
        throw StateError(
          'Separate isolated root, source and release assets required',
        );
      }
      final account = await FilePreferences.open(mcdevHome());
      final activeRoot =
          account.getString(DevelopmentStorage.preferenceKey) ??
          p.join(
            Platform.environment['HOME']!,
            'Library/Application Support/mcdev_income/development',
          );
      if (p.equals(target, activeRoot) ||
          p.isWithin(activeRoot, target) ||
          p.isWithin(target, activeRoot)) {
        throw StateError('Refusing the live development directory');
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
        final bundled = File(p.join(assets, key));
        final file = await bundled.exists()
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
        lockPath: p.join(p.dirname(target), 'sound-storage.lock'),
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
          expect(
            (await Process.run('/bin/cp', [
              '-cR',
              p.join(source, relative),
              dest.path,
            ])).exitCode,
            0,
          );
        }
      }
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'sound-probe',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? lifetime;
      Future<void> waitFor(bool Function() predicate) async {
        for (var i = 0; i < 420; ++i) {
          if (predicate()) return;
          if (host.error != null) throw StateError(host.error!);
          if (i % 30 == 0) {
            stdout.writeln(
              'SOUND: waiting $i seconds; running=${host.running}',
            );
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        throw StateError('Sound probe timed out');
      }

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
      try {
        await host.refresh();
        await host.chooseVersion(version);
        // Reuse this isolated fixture world on subsequent probe runs.
        await host.chooseNewWorld(false);
        await host.chooseDisableSound(true);
        host.selectedPacks.clear();
        lifetime = host.launchTest(
          worldName: '无声输出隔离验证',
          creative: true,
          menuOnly: false,
          seed: '20261004',
        );
        await waitFor(() => host.lanAvailable);
        final log = File(
          p.join(
            storage.paths.logs,
            p
                .basename(host.logPath!)
                .replaceFirst('test-', 'sound-')
                .replaceFirst('.log', '.json'),
          ),
        );
        for (var i = 0; i < 70; i++) {
          if (await log.exists() &&
              (jsonDecode(await log.readAsString()) as Map)['state'] ==
                  'ready') {
            break;
          }
          if (host.error != null) throw StateError(host.error!);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        final before = jsonDecode(await log.readAsString()) as Map;
        expect(before['state'], 'ready');
        expect(before['output'], 2);
        expect(before['failures'], 0);
        final options = await optionsFile();
        expect(await options.readAsString(), contains('audio_main:0'));
        final backup = File('${options.path}.mcdev-sound-backup');
        final original =
            (jsonDecode(await backup.readAsString()) as Map)['audio_main'];
        await Future<void>.delayed(const Duration(seconds: 5));
        final after = jsonDecode(await log.readAsString()) as Map;
        // A background game can stop audio updates once its world is loaded.
        // Silence must remain effective even when the update counter pauses.
        expect(before['updates'], greaterThan(0));
        expect(
          after['updates'],
          greaterThanOrEqualTo(before['updates'] as int),
        );
        expect(after['state'], 'ready');
        expect(after['output'], 2);
        expect(after['failures'], 0);
        stdout.writeln(
          'SOUND: running world uses NOSOUND; updates ${before['updates']} -> ${after['updates']}, failures=0',
        );
        await host.stopGame();
        await lifetime;
        lifetime = null;
        expect(await backup.exists(), isFalse);
        expect(await options.readAsString(), contains('audio_main:$original'));
        await host.chooseDisableSound(false);
        lifetime = host.launchTest(
          worldName: '恢复音量验证',
          creative: true,
          menuOnly: true,
        );
        await waitFor(() => host.running);
        expect(await options.readAsString(), contains('audio_main:$original'));
        final secondSoundLog = File(
          p.join(
            storage.paths.logs,
            p
                .basename(host.logPath!)
                .replaceFirst('test-', 'sound-')
                .replaceFirst('.log', '.json'),
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 15));
        expect(host.running, isTrue);
        expect(host.error, isNull);
        expect(await secondSoundLog.exists(), isFalse);
        expect(await backup.exists(), isFalse);
        stdout.writeln(
          'SOUND: unchecked menu launch has no mute DLL log and retains audio_main=$original',
        );
      } finally {
        await host.stopGame();
        await lifetime;
        host.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_SOUND'] != '1',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
