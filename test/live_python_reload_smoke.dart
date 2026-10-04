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
    'DLL Python reload updates live callbacks and preserves instances',
    () async {
      final target = Platform.environment['MCDEV_LIVE_PYTHON_RELOAD_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_PYTHON_RELOAD_SOURCE'];
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
        lockPath: p.join(p.dirname(target), 'python-reload-storage.lock'),
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
      final fixture = Directory(p.join(target, 'reload-fixture'));
      await fixture.create(recursive: true);
      await File(p.join(fixture.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'format_version': 2,
          'header': {
            'name': 'Python reload probe',
            'description': 'isolated probe',
            'uuid': '65a39e71-358c-4530-9da3-f6ee1b066ac6',
            'version': [1, 0, 0],
            'min_engine_version': [1, 18, 0],
          },
          'modules': [
            {
              'type': 'data',
              'uuid': '3a1aef39-cc37-42dd-9524-981713797a10',
              'version': [1, 0, 0],
            },
          ],
        }),
      );
      final scripts = Directory(p.join(fixture.path, 'reloadProbeScripts'));
      await scripts.create(recursive: true);
      await File(p.join(scripts.path, '__init__.py')).writeAsString('');
      final logic = File(p.join(scripts.path, 'logic.py'));
      await logic.writeAsString('VALUE = 1\ndef value():\n    return VALUE\n');
      final systems = File(p.join(scripts.path, 'systems.py'));
      String systemCode(int revision) =>
          '''# -*- coding: utf-8 -*-
import mod.server.extraServerApi as serverApi
import mod.client.extraClientApi as clientApi
from reloadProbeScripts.logic import value
class Server(serverApi.GetServerSystemCls()):
    def __init__(self, namespace, name):
        super(Server, self).__init__(namespace, name)
        self.counter = 0
        self.ListenForEvent(serverApi.GetEngineNamespace(), serverApi.GetEngineSystemName(), "OnScriptTickServer", self, self.OnTick)
    def OnTick(self, *args):
        self.counter += 1
        if self.counter % 30 == 0:
            print("MCDEV_HOT_SERVER rev=$revision value=%d counter=%d" % (value(), self.counter))
    def Destroy(self):
        self.UnListenForEvent(serverApi.GetEngineNamespace(), serverApi.GetEngineSystemName(), "OnScriptTickServer", self, self.OnTick)
class Client(clientApi.GetClientSystemCls()):
    def __init__(self, namespace, name):
        super(Client, self).__init__(namespace, name)
        self.counter = 0
        self.ListenForEvent(clientApi.GetEngineNamespace(), clientApi.GetEngineSystemName(), "OnScriptTickClient", self, self.OnTick)
    def OnTick(self, *args):
        self.counter += 1
        if self.counter % 30 == 0:
            print("MCDEV_HOT_CLIENT rev=$revision value=%d counter=%d" % (value(), self.counter))
    def Destroy(self):
        self.UnListenForEvent(clientApi.GetEngineNamespace(), clientApi.GetEngineSystemName(), "OnScriptTickClient", self, self.OnTick)
''';
      await systems.writeAsString(systemCode(1));
      await File(p.join(scripts.path, 'modMain.py')).writeAsString(
        r'''# -*- coding: utf-8 -*-
from mod.common.mod import Mod
import mod.server.extraServerApi as serverApi
import mod.client.extraClientApi as clientApi
@Mod.Binding(name="ReloadProbe", version="1.0.0")
class Probe(object):
    @Mod.InitServer()
    def server(self):
        serverApi.RegisterSystem("ReloadProbe", "Server", "reloadProbeScripts.systems.Server")
    @Mod.InitClient()
    def client(self):
        clientApi.RegisterSystem("ReloadProbe", "Client", "reloadProbeScripts.systems.Client")
''',
      );
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'python-reload',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? lifetime;
      try {
        await host.refresh();
        await host.chooseVersion(version);
        await host.importMods(fixture.path);
        expect(host.selectedPacks.length, 1);
        lifetime = host.launchTest(
          worldName: 'Python 热重载隔离验证',
          creative: true,
          menuOnly: false,
          seed: '20261003',
        );
        Future<String> waitFor(bool Function(String) predicate) async {
          for (var i = 0; i < 420; i++) {
            final log =
                host.logPath != null && await File(host.logPath!).exists()
                ? await File(host.logPath!).readAsString()
                : '';
            if (predicate(log)) return log;
            if (i % 30 == 0) {
              stdout.writeln(
                'RELOAD: waiting $i: ${host.pythonReloadUnavailableReason}; ${host.error}',
              );
            }
            if (!host.running && host.error != null) {
              throw StateError(host.error!);
            }
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          throw StateError(
            'Probe timed out: ${host.pythonReloadUnavailableReason}; ${host.error}; ${host.logPath}',
          );
        }

        final before = await waitFor(
          (log) =>
              host.pythonReloadAvailable &&
              log.contains('MCDEV_HOT_SERVER rev=1 value=1') &&
              log.contains('MCDEV_HOT_CLIENT rev=1 value=1'),
        );
        stdout.writeln('RELOAD: DLL safe point is live.');
        final oldCounter = RegExp(
          r'MCDEV_HOT_SERVER rev=1 value=1 counter=(\d+)',
        ).allMatches(before).last.group(1)!;
        await logic.writeAsString('def broken(:\n');
        await host.reloadPython();
        expect(host.error, contains('语法检查失败'));
        expect(host.pythonReloadAvailable, isTrue);
        await logic.writeAsString(
          'VALUE = 27\ndef value():\n    return VALUE\n',
        );
        await systems.writeAsString(systemCode(2));
        await host.reloadPython();
        expect(host.error, isNull, reason: host.error);
        expect(host.notice, contains('热重载完成'));
        final after = await waitFor(
          (log) =>
              log.contains('MCDEV_HOT_SERVER rev=2 value=27') &&
              log.contains('MCDEV_HOT_CLIENT rev=2 value=27'),
        );
        final newCounter = RegExp(
          r'MCDEV_HOT_SERVER rev=2 value=27 counter=(\d+)',
        ).allMatches(after).first.group(1)!;
        expect(int.parse(newCounter), greaterThan(int.parse(oldCounter)));
        await host.reloadPython();
        expect(host.notice, 'Python 源码没有变化。');
        stdout.writeln(
          'RELOAD: server/client callbacks updated, instance counter $oldCounter -> $newCounter, syntax error recovered; ${host.logPath}',
        );
      } finally {
        await host.stopGame();
        await lifetime;
        host.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_PYTHON_RELOAD'] != '1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
