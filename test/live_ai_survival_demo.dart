// Explicit opt-in demonstration. The world lives in a separate persistent root.
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
    'AI survival demonstration in isolated 3.10 world',
    () async {
      final root = Platform.environment['MCDEV_AI_DEMO_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_AI_GAME_SOURCE'];
      final assets = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      if (root == null || source == null || assets == null) {
        throw StateError('Demo root, source, and release assets are required.');
      }
      final account = await FilePreferences.open(mcdevHome());
      final activeRoot =
          account.getString(DevelopmentStorage.preferenceKey) ??
          p.join(
            Platform.environment['HOME']!,
            'Library/Application Support/mcdev_income/development',
          );
      if (p.equals(root, activeRoot) ||
          p.isWithin(activeRoot, root) ||
          p.isWithin(root, activeRoot) ||
          p.equals(root, source) ||
          p.isWithin(source, root) ||
          p.isWithin(root, source)) {
        throw StateError('Refusing active or source development data.');
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
        final file = !key.startsWith('tools/') && await bundled.exists()
            ? bundled
            : File(p.join(Directory.current.path, key));
        return await file.exists()
            ? ByteData.sublistView(await file.readAsBytes())
            : null;
      });
      final storage = NativeDevelopmentStorage(
        preferences: MemoryPreferences(),
        defaultRoot: root,
        lockPath: p.join(p.dirname(root), 'ai-survival-storage.lock'),
      );
      await storage.initialize();
      const version = '3.10.0.420447';
      for (final relative in [
        'runtimes/wine-11.0_1-mcs-v1',
        'games/$version',
      ]) {
        final dest = Directory(p.join(root, relative));
        if (!await dest.exists()) {
          await dest.parent.create(recursive: true);
          final copy = await Process.run('/bin/cp', [
            '-cR',
            p.join(source, relative),
            dest.path,
          ]);
          expect(copy.exitCode, 0, reason: '${copy.stderr}');
        }
      }
      final host = NativeDevelopmentLauncher(
        storage,
        MemoryPreferences(),
      sessionId: Platform.environment['MCDEV_AI_DEMO_REUSE_SESSION'] ??
          'ai-survival',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? lifetime;
      try {
        await host.refresh();
        await host.chooseVersion(version);
        await host.chooseAiControl(true);
        await host.chooseNewWorld(
          Platform.environment['MCDEV_AI_DEMO_RESUME'] != '1',
        );
        host.selectedPacks.clear();
        await host.importMods(
          p.join(Directory.current.path,
              'tools/ai_game/fixtures/crafting_behavior'),
        );
        lifetime = host.launchTest(
          worldName: 'AI 生存演示',
          creative: false,
          menuOnly: false,
          seed: '1',
          difficulty: 0,
        );
        for (var i = 0; i < 420 && !host.aiControlReady; i++) {
          if (i % 30 == 0) {
            stdout.writeln('SURVIVAL waiting $i: ${host.logPath}');
          }
          if (!host.running && host.error != null) {
            throw StateError(host.error!);
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(
          host.aiControlReady,
          true,
          reason: '${host.error}; ${host.logPath}',
        );
        final session = File(p.join(root, 'demo-session.json'));
        await session.writeAsString(
          jsonEncode({
            'descriptor': host.aiDescriptorPath,
            'log': host.logPath,
            'seed': '1',
            'mode': 'survival',
            'started_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        stdout.writeln('SURVIVAL READY: ${session.path}');
        final done = File(p.join(root, 'demo-stop'));
        for (var i = 0; i < 1200 && host.running; i++) {
          if (await done.exists()) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } finally {
        await host.stopGame();
        await lifetime;
        host.dispose();
      }
    },
    skip: Platform.environment['MCDEV_AI_DEMO'] != '1',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
