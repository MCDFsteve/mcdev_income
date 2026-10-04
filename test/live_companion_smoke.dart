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
    '3.10 companion launch flag disables, restores and disables on the same save',
    () async {
      final target = Platform.environment['MCDEV_LIVE_COMPANION_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_COMPANION_SOURCE'];
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
        final localAsset = File(key);
        final file = await localAsset.exists()
            ? localAsset
            : File(p.join(assets, key));
        return await file.exists()
            ? ByteData.sublistView(await file.readAsBytes())
            : null;
      });
      final preferences = MemoryPreferences();
      final storage = NativeDevelopmentStorage(
        preferences: preferences,
        defaultRoot: target,
        lockPath: p.join(p.dirname(target), 'companion-storage.lock'),
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
      final fixture = Directory(p.join(target, 'companion-fixture'));
      await fixture.create(recursive: true);
      await File(p.join(fixture.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'format_version': 2,
          'header': {
            'name': 'Companion reverse probe',
            'description': 'Isolated 3.10 probe',
            'uuid': 'd23616b4-e6c7-45cf-813c-d5c9acdf1966',
            'version': [1, 0, 0],
            'min_engine_version': [1, 18, 0],
          },
          'modules': [
            {
              'type': 'data',
              'uuid': 'fd817edf-8b3a-42b1-9c31-9266ba45625f',
              'version': [1, 0, 0],
            },
          ],
        }),
      );
      final script = Directory(p.join(fixture.path, 'companionProbeScripts'));
      await script.create(recursive: true);
      await File(p.join(script.path, '__init__.py')).writeAsString('');
      await File(p.join(script.path, 'modMain.py')).writeAsString(_probeScript);
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'companion-probe',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? lifetime;
      try {
        await host.refresh();
        await host.chooseVersion(version);
        await host.importMods(fixture.path);
        expect(host.selectedPacks.length, 1);
        final report = File(
          p.join(host.gamePrefix, 'drive_c/MCDevTests/companion-state.json'),
        );
        for (final disabled in [true, false, true]) {
          // The first run exercises the default without writing a preference.
          if (host.disableCompanion != disabled) {
            await host.chooseDisableCompanion(disabled);
          }
          if (await report.exists()) await report.delete();
          lifetime = host.launchTest(
            worldName: '伙伴开关隔离验证',
            creative: true,
            menuOnly: false,
            seed: '20261003',
          );
          Map<String, dynamic>? verified;
          for (var i = 0; i < 300; i++) {
            if (host.error != null) throw StateError(host.error!);
            if (await report.exists()) {
              try {
                final data =
                    jsonDecode(await report.readAsString())
                        as Map<String, dynamic>;
                if (data['error'] != null) {
                  throw StateError(data['error'].toString());
                }
                if (data['ready_seconds'] >= 10 &&
                    data['launch_close_pet_addon'] == disabled &&
                    data['manual_closed'] == disabled &&
                    data['client_enabled'] == !disabled &&
                    data['ui_initialized'] == !disabled &&
                    data['summoned'] == !disabled) {
                  verified = data;
                  break;
                }
              } on FormatException {
                // A report can be read while the game is replacing its contents.
              }
            }
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          stdout.writeln('COMPANION_STATE disabled=$disabled $verified');
          expect(verified, isNotNull);
          final config = jsonDecode(
            await File(
              p.join(host.gamePrefix, 'drive_c/MCDevTests/test.cppconfig'),
            ).readAsString(),
          );
          expect(config['launch_params']['close_pet_addon'], disabled);
          await host.stopGame();
          await lifetime;
          lifetime = null;
          expect(host.error, isNull);
        }
      } finally {
        await host.stopGame();
        await lifetime;
        host.dispose();
      }
    },
    skip: Platform.environment['MCDEV_LIVE_COMPANIONS'] != '1',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

// Read-only inspection of the exact 3.10 runtime path found by reverse
// engineering. The fixture never changes companion state or launch parameters.
const _probeScript = r'''# -*- coding: utf-8 -*-
import json
import time
from mod.common.mod import Mod
import mod.client.extraClientApi as clientApi

_ready_since = None

def report(game):
    global _ready_since
    try:
        from sunshine.sunshine_manager import instance
        pet = clientApi.GetSystem('Minecraft', 'pet')
        ready = pet.mUiInitFinishedReceived
        if ready and _ready_since is None:
            _ready_since = time.time()
        data = {
            'ready_seconds': time.time() - _ready_since if _ready_since else 0,
            'launch_close_pet_addon': instance.get_launch_param('close_pet_addon', None),
            'manual_closed': pet.IsClosePetAddonManual(),
            'client_enabled': pet.mEnable,
            'summoned': pet.mPetEntity.IsSummon(),
            'ui_initialized': pet.mHasInitUI,
        }
    except Exception as error:
        data = {'error': repr(error)}
    with open('C:/MCDevTests/companion-state.json', 'w') as output:
        json.dump(data, output)
    game.AddTimer(2, report, game)

@Mod.Binding(name='CompanionProbe', version='1.0.0')
class Probe(object):
    @Mod.InitClient()
    def client(self):
        game = clientApi.GetEngineCompFactory().CreateGame(clientApi.GetLevelId())
        game.AddTimer(5, report, game)
''';
