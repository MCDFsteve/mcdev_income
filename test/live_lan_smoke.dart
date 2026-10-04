// Explicit opt-in, isolated LAN integration check. Never uses live saves.
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
import 'development_test.dart' show MemoryPreferences;
import 'live_lan_fixture.dart' show installLiveLanFixtureServer;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'real 3.10 LAN host accepts two named players with independent skins',
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
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'lan-host',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? launched;
      Future<void> waitFor(bool Function() ready, String stage) async {
        final deadline = DateTime.now().add(const Duration(minutes: 8));
        String? previousRoster;
        while (!ready() && DateTime.now().isBefore(deadline)) {
          final abort = Platform.environment['MCDEV_LIVE_SESSIONS_ABORT'];
          if (abort != null && await File(abort).exists()) {
            throw StateError('Diagnostic aborted during $stage');
          }
          final roster = host.players
              .map((player) => '${player.name}:${player.status.name}')
              .join(', ');
          if (roster != previousRoster) {
            previousRoster = roster;
            stdout.writeln('LAN: roster [$roster]');
          }
          if (host.error != null) {
            throw StateError('Host failed during $stage; details withheld');
          }
          final failed = host.players.where(
            (p) => p.status == DevelopmentPlayerStatus.failed,
          );
          if (failed.isNotEmpty) {
            final message = failed.first.error ?? '';
            const categories = [
              '房主世界已退出',
              '房主的局域网连接已变化',
              '无法读写开发目录',
              'Wine 游戏窗口组件',
              '此测试页已经在运行',
              '局域网连接兼容组件',
              '游戏启动已取消',
              '皮肤',
              '校验',
              '登录',
              '测试游戏退出',
            ];
            final category = categories.where(message.contains).join(', ');
            throw StateError(
              'Guest failed during $stage: '
              '${category.isEmpty ? "unclassified" : category}',
            );
          }
          if (!host.running && !host.busy) {
            throw StateError('Host exited during $stage');
          }
          if (host.players.any(
            (p) =>
                !p.host &&
                p.status == DevelopmentPlayerStatus.disconnected &&
                !p.canStop,
          )) {
            throw StateError('Guest exited during $stage');
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(ready(), isTrue, reason: stage);
        stdout.writeln('LAN: $stage');
      }

      bool joined(String name) => host.players.any(
        (p) => p.name == name && p.status == DevelopmentPlayerStatus.connected,
      );
      try {
        await host.refresh();
        await host.chooseVersion(version);
        await host.chooseNewWorld(true);
        final fixture = Directory(p.join(target, 'lan-verification-project'));
        for (final resource in [false, true]) {
          final pack = Directory(p.join(fixture.path, resource ? 'RP' : 'BP'));
          await pack.create(recursive: true);
          await File(p.join(pack.path, 'manifest.json')).writeAsString(
            jsonEncode({
              'format_version': 2,
              'header': {
                'name': 'LAN 联机验证',
                'description': 'Isolated LAN smoke test fixture',
                'uuid': resource
                    ? 'e8cb1abf-174f-4f48-aafd-08cb2e5a8711'
                    : '7418349e-d608-4aec-81d4-26c8a9bb895e',
                'version': [1, 0, 0],
                'min_engine_version': [1, 18, 0],
              },
              'modules': [
                {
                  'type': resource ? 'resources' : 'data',
                  'uuid': resource
                      ? '4aef664e-25cf-4f75-bafa-b6b06c0f8b39'
                      : 'bca9bd4f-ad93-48d3-b330-94acdcf3dccd',
                  'version': [1, 0, 0],
                },
              ],
            }),
          );
          if (resource) {
            final texts = Directory(p.join(pack.path, 'texts'));
            await texts.create();
            for (final locale in ['en_US', 'zh_CN']) {
              await File(
                p.join(texts.path, '$locale.lang'),
              ).writeAsString('tile.gold_block.name=LAN shared marker\n');
            }
          } else {
            final function = File(
              p.join(pack.path, 'functions', 'mcdev_lan_verify.mcfunction'),
            );
            await function.parent.create();
            await function.writeAsString(
              'say MCDev LAN behavior pack is loaded\n'
              'give @s gold_block 1\n',
            );
          }
        }
        final fixtureNonce = await installLiveLanFixtureServer(
          Directory(p.join(fixture.path, 'BP')),
        );
        await host.importMods(fixture.path);
        launched = host.launchTest(
          worldName: '局域网自动验证',
          creative: true,
          menuOnly: false,
          seed: '20261002',
        );
        await waitFor(() => host.running, 'host process running');
        await waitFor(() => host.lanAvailable, 'host world and LAN port ready');
        await host.launchLanPlayer(name: '测试史蒂夫', skin: TestPlayerSkin.steve);
        await waitFor(
          () => joined('测试史蒂夫'),
          'guest Steve connected in host roster',
        );
        await host.launchLanPlayer(name: '测试艾莉', skin: TestPlayerSkin.alex);
        await waitFor(
          () => joined('测试艾莉'),
          'guest Alex connected in host roster',
        );
        expect(
          host.players
              .where((p) => p.status == DevelopmentPlayerStatus.connected)
              .length,
          3,
        );
        stdout.writeln('LAN_THREE_PLAYERS_READY');
        final reportFile = File(
          p.join(host.gamePrefix, 'drive_c', 'MCDevTests', 'lan-fixture.json'),
        );
        Map<String, dynamic>? fixtureReport;
        final reportDeadline = DateTime.now().add(const Duration(minutes: 3));
        while (DateTime.now().isBefore(reportDeadline)) {
          if (await reportFile.exists()) {
            try {
              final report = jsonDecode(await reportFile.readAsString());
              if (report is Map<String, dynamic> &&
                  report['nonce'] == fixtureNonce &&
                  report['status'] == 'complete') {
                fixtureReport = report;
                break;
              }
            } on FormatException {
              // The native server may be in the middle of a report write.
            }
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        stdout.writeln(
          fixtureReport?['success'] == true
              ? 'LAN_FIXTURE_COMMANDS_VERIFIED'
              : 'LAN_FIXTURE_COMMANDS_FAILED',
        );
        final stop = Platform.environment['MCDEV_LIVE_SESSIONS_STOP'];
        final deadline = DateTime.now().add(const Duration(minutes: 10));
        while (stop != null &&
            !await File(stop).exists() &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(
          fixtureReport?['success'],
          isTrue,
          reason: 'selected behavior pack commands execute for all players',
        );
        final first = host.players.singleWhere((p) => p.name == '测试史蒂夫');
        await host.stopLanPlayer(first.id);
        await waitFor(
          () => !joined('测试史蒂夫') && joined('测试艾莉'),
          'one guest stopped while host and second remain',
        );
        expect(host.running, isTrue);
        await host.launchLanPlayer(name: '测试史蒂夫', skin: TestPlayerSkin.alex);
        await waitFor(() => joined('测试史蒂夫'), 'stopped guest slot rejoins');
        expect(
          host.players.singleWhere((p) => p.name == '测试史蒂夫').skin,
          TestPlayerSkin.alex,
        );
        await host.stopGame();
        await launched;
        expect(
          host.players.where(
            (p) => p.status == DevelopmentPlayerStatus.connected,
          ),
          isEmpty,
        );
        expect(host.error, isNull);
      } finally {
        await host.stopGame();
        await launched;
        host.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_LAN'] != '1',
    timeout: const Timeout(Duration(minutes: 35)),
  );
}
