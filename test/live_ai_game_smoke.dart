// Explicit opt-in. Uses isolated 3.10 copies and never the user's projects/saves.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/game_graphics.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'development_test.dart' show MemoryPreferences;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'AI stream controls current player in an isolated 3.10 world',
    () async {
      final target = Platform.environment['MCDEV_LIVE_AI_GAME_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_AI_GAME_SOURCE'];
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
        lockPath: p.join(p.dirname(target), 'ai-game-storage.lock'),
      );
      await storage.initialize();
      const version = '3.10.0.420447';
      final metal = Platform.environment['MCDEV_LIVE_AI_RENDERER'] == 'metal';
      for (final relative in [
        'runtimes/wine-11.0_1-mcs-v1',
        if (metal) 'runtimes/wine-11.0_1-dxmt-0.80-v1',
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
        sessionId: 'ai-game',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? lifetime;
      Socket? agent;
      final baselineMode = Platform.environment['MCDEV_LIVE_AI_BASELINE'];
      final baseline = baselineMode != null;
      try {
        await host.refresh();
        await host.chooseVersion(version);
        if (metal) await host.chooseRenderer(GameRenderer.renderDragon);
        await host.chooseAiControl(!baseline);
        await host.chooseNewWorld(true);
        await host.importMods(
          p.join(
            Directory.current.path,
            'tools/ai_game/fixtures/movement_behavior',
          ),
        );
        if (baselineMode == 'vanilla') host.selectedPacks.clear();
        lifetime = host.launchTest(
          worldName: 'AI 隔离验证',
          creative: true,
          menuOnly: false,
          seed: '20261005',
        );
        if (baseline) {
          var loaded = false;
          for (var i = 0; i < 420 && !loaded; i++) {
            if (i % 30 == 0) {
              stdout.writeln('BASELINE waiting $i: ${host.logPath}');
            }
            final log = host.logPath == null ? null : File(host.logPath!);
            loaded = baselineMode == 'vanilla'
                ? host.lanAvailable
                : log != null &&
                      await log.exists() &&
                      (await log.readAsString()).contains('AI_FIXTURE_READY');
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          expect(loaded, true);
          stdout.writeln('BASELINE loaded, checking shutdown: ${host.logPath}');
        } else {
          for (var i = 0; i < 420 && !host.aiControlReady; i++) {
            if (i % 30 == 0) {
              stdout.writeln('AI waiting $i: ${host.error}; ${host.logPath}');
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
          final descriptor =
              jsonDecode(await File(host.aiDescriptorPath!).readAsString())
                  as Map;
          agent = await Socket.connect('127.0.0.1', descriptor['port'] as int);
          final messages = <Map<String, dynamic>>[];
          agent
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                final data = jsonDecode(line) as Map<String, dynamic>;
                messages.add(data);
                if (data['type'] != 'observation') {
                  stdout.writeln('AI ${jsonEncode(data)}');
                }
              });
          void send(Map<String, dynamic> value) =>
              agent!.write('${jsonEncode(value)}\n');
          Future<Map<String, dynamic>> wait(
            bool Function(Map<String, dynamic>) predicate,
          ) async {
            for (var i = 0; i < 200; i++) {
              final found = messages.where(predicate).lastOrNull;
              if (found != null) return found;
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            throw StateError(
              'AI response timeout; ${messages.take(5).toList()}',
            );
          }

          send({
            'type': 'hello',
            'role': 'agent',
            'token': descriptor['token'],
            'protocol': 1,
          });
          final before = await wait((x) => x['type'] == 'observation');
          stdout.writeln('AI first observation: ${jsonEncode(before)}');
          send({'type': 'claim', 'epoch': before['epoch'], 'hz': 5});
          final claimed = await wait((x) => x['type'] == 'claimed');
          final envelope = {
            'epoch': claimed['epoch'],
            'generation': claimed['generation'],
          };
          final heartbeat = Timer.periodic(
            const Duration(milliseconds: 500),
            (_) => send({'type': 'heartbeat', ...envelope}),
          );
          try {
            send({
              'type': 'action',
              ...envelope,
              'id': 'look',
              'action': {'op': 'look', 'pitch': 20, 'yaw': 90},
            });
            final lookReceipt = await wait(
              (x) => x['id'] == 'look' && x['status'] == 'completed',
            );
            final rotated = await wait(
              (x) =>
                  x['type'] == 'observation' &&
                  x['tick'] >= lookReceipt['tick'] &&
                  ((((x['player'] as Map)['rotation'] as List?)?[0] as num? ??
                                  0) -
                              20)
                          .abs() <
                      1 &&
                  (((x['player'] as Map)['rotation'] as List?)?[1] as num? ??
                          0) >
                      89,
            );
            expect(
              ((rotated['player'] as Map)['rotation'] as List)[0],
              closeTo(20, 1),
            );
            send({
              'type': 'action',
              ...envelope,
              'id': 'move',
              'action': {
                'op': 'move',
                'left': 0,
                'forward': 1,
                'duration_ms': 1000,
              },
            });
            final moveReceipt = await wait(
              (x) => x['id'] == 'move' && x['status'] == 'completed',
            );
            final moved = await wait(
              (x) =>
                  x['type'] == 'observation' &&
                  x['tick'] >= moveReceipt['tick'],
            );
            stdout.writeln('AI after move: ${jsonEncode(moved)}');
            final a = ((rotated['player'] as Map)['position'] as List)
                .cast<num>();
            final b = ((moved['player'] as Map)['position'] as List)
                .cast<num>();
            expect((a[0] - b[0]).abs() + (a[2] - b[2]).abs(), greaterThan(.1));
            send({
              'type': 'action',
              ...envelope,
              'id': 'slot',
              'action': {'op': 'select_slot', 'slot': 0},
            });
            await wait((x) => x['id'] == 'slot' && x['status'] == 'completed');
            send({
              'type': 'action',
              ...envelope,
              'id': 'down',
              'action': {'op': 'look', 'pitch': 89, 'yaw': 0},
            });
            final down = await wait(
              (x) => x['id'] == 'down' && x['status'] == 'completed',
            );
            final aimed = await wait(
              (x) =>
                  x['type'] == 'observation' &&
                  x['tick'] > down['tick'] &&
                  ((x['player'] as Map)['rotation'] as List)[0] > 88 &&
                  ((x['scene'] as Map)['crosshair'] as Map)['type'] == 'Block',
            );
            final targetBlock = (aimed['scene'] as Map)['crosshair'] as Map;
            send({
              'type': 'action',
              ...envelope,
              'id': 'dig',
              'action': {
                'op': 'dig',
                for (final key in ['x', 'y', 'z', 'face'])
                  key: targetBlock[key],
                'duration_ms': 700,
              },
            });
            final dig = await wait(
              (x) => x['id'] == 'dig' && x['status'] == 'completed',
            );
            final dug = await wait(
              (x) =>
                  x['type'] == 'observation' &&
                  x['tick'] >= dig['tick'] &&
                  (x['last_interaction'] as Map?)?['block'] is List &&
                  ((x['last_interaction'] as Map)['block'] as List)[0] ==
                      'minecraft:air',
            );
            final sound = messages
                .where((x) => x['type'] == 'events')
                .expand((x) => x['events'] as List)
                .where((x) => x['kind'] == 'sound_request')
                .toList();
            expect(sound, isNotEmpty);
            final report = {
              'passed': false,
              'functional_passed': true,
              'renderer': host.effectiveRenderer.name,
              'before': before,
              'moved': moved,
              'dug': dug,
              'events': sound,
              'log': host.logPath,
            };
            send({'type': 'stop'});
            await wait((x) => x['type'] == 'stopped');
            heartbeat.cancel();
            agent.destroy();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            final runner = await Process.run('python3', [
              'tools/ai_game/client.py',
              '--descriptor',
              host.aiDescriptorPath!,
              '--test',
              'tools/ai_game/examples/look-test.json',
              '--report',
              p.join(target, 'ai-client-report.json'),
            ]);
            expect(
              runner.exitCode,
              0,
              reason: '${runner.stdout}\n${runner.stderr}',
            );
            final modLog = await File(host.logPath!).readAsString();
            expect(modLog, contains('AI_FIXTURE_MOVED'));
            report['test_runner'] = jsonDecode(runner.stdout as String);
            report['mod_fixture_responded'] = true;
            await File(
              p.join(target, 'ai-live-report.json'),
            ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
            stdout.writeln('AI behavior assertions passed; checking shutdown.');
          } finally {
            heartbeat.cancel();
          }
        }
      } finally {
        agent?.destroy();
        await host.stopGame();
        await lifetime;
        host.dispose();
      }
      final exitLog = await File(host.logPath!).readAsString();
      final crashed = exitLog.contains('游戏发生原生崩溃');
      final exitCode = int.tryParse(
        RegExp(r'游戏进程退出：(-?\d+)').firstMatch(exitLog)?.group(1) ?? '',
      );
      final reportFile = File(
        p.join(
          target,
          baseline
              ? 'ai-baseline-$baselineMode-report.json'
              : 'ai-live-report.json',
        ),
      );
      final finalReport = baseline
          ? <String, dynamic>{'baseline': baselineMode, 'log': host.logPath}
          : jsonDecode(await reportFile.readAsString()) as Map;
      finalReport['passed'] = !crashed && exitCode == 0;
      finalReport['clean_shutdown'] = !crashed && exitCode == 0;
      finalReport['native_crash'] = crashed;
      finalReport['exit_code'] = exitCode;
      finalReport['quiesce_acknowledged'] = exitLog.contains('已确认停止采样与输入');
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(finalReport),
      );
      expect(
        crashed,
        false,
        reason: 'Native crash during shutdown; ${host.logPath}',
      );
      expect(exitCode, 0, reason: 'Unclean shutdown; ${host.logPath}');
      stdout.writeln('AI LIVE PASS including clean shutdown: ${host.logPath}');
    },
    skip: Platform.environment['MCDEV_LIVE_AI_GAME'] != '1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
