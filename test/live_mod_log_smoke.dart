// Explicit opt-in. Uses isolated 3.10 copies and never the user's projects/saves.
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
    'isolated official mod logging channel probe',
    () async {
      final target = Platform.environment['MCDEV_LIVE_MOD_LOG_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_MOD_LOG_SOURCE'];
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
        final file = File(p.join(assets, key));
        return await file.exists()
            ? ByteData.sublistView(await file.readAsBytes())
            : null;
      });
      final preferences = MemoryPreferences();
      final storage = NativeDevelopmentStorage(
        preferences: preferences,
        defaultRoot: target,
        lockPath: p.join(p.dirname(target), 'logging-storage.lock'),
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
      final fixture = Directory(p.join(target, 'logging-fixture'));
      for (var n = 1; n <= 4; n++) {
        final pack = Directory(p.join(fixture.path, 'BP$n'));
        await pack.create(recursive: true);
        await File(p.join(pack.path, 'manifest.json')).writeAsString(
          jsonEncode({
            'format_version': 2,
            'header': {
              'name': '日志验证$n',
              'description': 'isolated logging fixture',
              'uuid': '75dcc98f-07a9-40d9-b6cc-37fdf127ddd$n',
              'version': [1, 0, 0],
              'min_engine_version': [1, 18, 0],
            },
            'modules': [
              {
                'type': 'data',
                'uuid': 'bdd57eb1-1ff4-478c-9d59-93d9bc396cc$n',
                'version': [1, 0, 0],
              },
            ],
          }),
        );
        final script = Directory(p.join(pack.path, 'logFixture${n}Scripts'));
        await script.create();
        await File(p.join(script.path, '__init__.py')).writeAsString(
          '# -*- coding: utf-8 -*-\n"""original docstring"""\nfrom __future__ import division\nassert 1 / 2 == 0.5\nprint "MCDEV_FIXTURE_INIT_$n"\n',
        );
        final initServerTail = (n == 4
            ? '        serverApi.RegisterSystem("LogFixture4", "Ticker", "logFixture4Scripts.modMain.Ticker")\n'
                  '    @Mod.InitClient()\n'
                  '    def InitClient(self):\n'
                  '        print "MCDEV_FIXTURE_CLIENT_4"\n'
                  'class Ticker(serverApi.GetServerSystemCls()):\n'
                  '    def __init__(self, namespace, name):\n'
                  '        super(Ticker, self).__init__(namespace, name)\n'
                  '        self.ticks = 0\n'
                  '        self.ListenForEvent(serverApi.GetEngineNamespace(), serverApi.GetEngineSystemName(), "OnScriptTickServer", self, self.OnTick)\n'
                  '    def OnTick(self, *args):\n'
                  '        self.ticks += 1\n'
                  '        if self.ticks == 100:\n'
                  '            print "MCDEV_FIXTURE_LATE_4"\n'
                  '            raise RuntimeError("MCDEV_FIXTURE_ERROR_4")\n'
            : '        raise RuntimeError("MCDEV_FIXTURE_ERROR_$n")\n');
        await File(p.join(script.path, 'modMain.py')).writeAsString(
          n == 2
              ? 'def deliberate_syntax_error(:\n    pass\n'
              : n == 3
              ? 'import missing_mcdev_fixture_module\n'
              : '# -*- coding: utf-8 -*-\n'
                    'print "MCDEV_FIXTURE_PRINT_$n 中文 多行\\n第二行"\n'
                    'print "[INFO][Engine] a real mod print must survive"\n'
                    'from mod.common.mod import Mod\n'
                    'import mod.server.extraServerApi as serverApi\n'
                    '@Mod.Binding(name="LogFixture$n", version="1.0.0")\n'
                    'class LogFixture$n(object):\n'
                    '    @Mod.InitServer()\n'
                    '    def InitServer(self):\n'
                    '        print "MCDEV_FIXTURE_SERVER_$n"\n'
                    '        print "MCDEV_FIXTURE_LONG_" + u"中" * 5000\n'
                    '$initServerTail',
        );
      }
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'log-probe',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? lifetime;
      try {
        await host.refresh();
        await host.chooseVersion(version);
        await host.importMods(fixture.path);
        expect(host.selectedPacks.length, 4);
        lifetime = host.launchTest(
          worldName: '模组日志隔离验证',
          creative: true,
          menuOnly: false,
          seed: '20261003',
        );
        var captured = false;
        for (var i = 0; i < 200; i++) {
          if (host.error != null) throw StateError(host.error!);
          if (host.logPath != null && await File(host.logPath!).exists()) {
            final log = await File(host.logPath!).readAsString();
            if (log.contains('MCDEV_FIXTURE_ERROR_4') &&
                log.contains('SyntaxError') &&
                log.contains('MCDEV_FIXTURE_INIT_1') &&
                log.contains('MCDEV_FIXTURE_LATE_4') &&
                log.contains('MCDEV_FIXTURE_CLIENT_4')) {
              captured = true;
              await Future<void>.delayed(const Duration(seconds: 5));
              break;
            }
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        stdout.writeln('LOG_PROBE: captured=$captured; log=${host.logPath}');
        expect(captured, isTrue);
        final content = await File(host.logPath!).readAsString();
        expect(content, contains('中' * 5000));
        expect(
          content,
          contains('[INFO][Engine] a real mod print must survive'),
        );
        expect(content, contains('MCDEV_FIXTURE_INIT_2'));
        for (final noise in [
          'Mobile logger started',
          'MCDEV_LAN_BRIDGE',
          'get_world_record',
          'LoadWindowsAddonPy',
          'Specified image could not be found',
        ]) {
          expect(content, isNot(contains(noise)));
        }
      } finally {
        await host.stopGame();
        await lifetime;
        host.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_MOD_LOGS'] != '1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
