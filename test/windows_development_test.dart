import 'dart:convert';
import 'dart:io';
import 'package:mcdev_income/development/platform/game_window_backend.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/lan_endpoint_io.dart';
import 'package:mcdev_income/development/platform/windows_game_runtime.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/test_session_io.dart';
import 'development_test.dart' show MemoryPreferences;

void main() {
  late Directory temp;
  late NativeDevelopmentStorage storage;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-windows-');
    storage = NativeDevelopmentStorage(
      preferences: MemoryPreferences(),
      defaultRoot: p.join(temp.path, '中文 data'),
      lockPath: p.join(temp.path, 'lock'),
    );
    await storage.initialize();
  });
  tearDown(() => temp.delete(recursive: true));

  test(
    'Windows runtime needs no Wine and isolates native known folders per tab',
    () async {
      final first = WindowsGameRuntime(
        storage,
        'default',
        window: const HeadlessGameWindow(),
      );
      final second = WindowsGameRuntime(
        storage,
        'second',
        window: const HeadlessGameWindow(),
      );
      expect(await first.ready(), isTrue);
      expect(first.wine, isNull);
      expect(first.capabilities.requiresWine, isFalse);
      expect(
        first.environment().keys.any((key) => key.startsWith('WINE')),
        isFalse,
      );
      expect(
        first.environment()['APPDATA'],
        isNot(second.environment()['APPDATA']),
      );
      await first.prepare((_) {});
      addTearDown(first.terminateHelpers);
      final child = await first.start(
        executable: 'powershell.exe',
        arguments: [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"[Console]::OutputEncoding = [Text.UTF8Encoding]::new(); [Environment]::GetFolderPath('ApplicationData')",
        ],
        workingDirectory: first.prefix,
        version: 'test',
        displayName: 'test',
        renderer: 'test',
        fullscreenShortcut: false,
      );
      final result = utf8
          .decode(await child.stdout.expand((bytes) => bytes).toList())
          .trim();
      await child.stderr.drain<void>();
      expect(await child.exitCode, 0);
      expect(p.equals(result, first.gamePath(await first.roaming())), isTrue);
      expect(
        first.gamePath(await first.roaming()),
        matches(r'^[A-Z]:\\users\\Developer\\AppData\\Roaming$'),
      );
      await second.prepare((_) {});
      addTearDown(second.terminateHelpers);
      expect(
        second.gamePath(await second.roaming()),
        isNot(first.gamePath(await first.roaming())),
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'nested game files survive manifest verification, import and migration',
    () async {
      final source = Directory(p.join(temp.path, '3.10.0.420447'));
      final files = {
        'Minecraft.Windows.exe': 'fixture',
        'data/nested/file.txt': 'content',
      };
      for (final entry in files.entries) {
        final file = File(p.join(source.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
      }
      final manifest = {
        for (final entry in files.entries)
          entry.key: md5.convert(utf8.encode(entry.value)).toString(),
      };
      await File(
        p.join(source.path, 'patch.json'),
      ).writeAsString(jsonEncode({'md5': manifest}));
      final launcher = NativeDevelopmentLauncher(
        storage,
        MemoryPreferences(),
        runtimeBackend: WindowsGameRuntime(
          storage,
          'default',
          window: const HeadlessGameWindow(),
        ),
      );
      addTearDown(launcher.dispose);
      await launcher.importGame(source.path);
      expect(launcher.error, isNull);
      expect(launcher.games.single.version, '3.10.0.420447');
      final game = launcher.games.single.directory;
      final first = await prepareSessionGame(
        source: game,
        prefix: p.join(storage.paths.prefixes, 'a'),
        version: launcher.games.single.version,
      );
      final second = await prepareSessionGame(
        source: game,
        prefix: p.join(storage.paths.prefixes, 'b'),
        version: launcher.games.single.version,
      );
      await File(
        p.join(first, 'data/nested/file.txt'),
      ).writeAsString('changed');
      expect(
        await File(p.join(second, 'data/nested/file.txt')).readAsString(),
        'content',
      );
      final oldRoot = storage.paths.root;
      final destination = p.join(temp.path, '迁移 target');
      await storage.migrateTo(destination);
      expect((await storage.inspect()).initialized, isTrue);
      expect(
        await File(
          p.join(destination, 'games/3.10.0.420447/data/nested/file.txt'),
        ).readAsString(),
        'content',
      );
      expect(await Directory(oldRoot).exists(), isTrue);
    },
  );

  test(
    'Windows profile upgrade preserves existing worlds and releases its alias',
    () async {
      final runtime = WindowsGameRuntime(
        storage,
        'legacy',
        window: const HeadlessGameWindow(),
      );
      final oldWorld = File(
        p.join(
          runtime.prefix,
          'profile/AppData/Roaming/MinecraftPE_Netease/minecraftWorlds/test/level.dat',
        ),
      );
      await oldWorld.parent.create(recursive: true);
      await oldWorld.writeAsString('saved world');
      await runtime.prepare((_) {});
      addTearDown(runtime.terminateHelpers);
      final newWorld = File(
        p.join(
          await runtime.roaming(),
          'MinecraftPE_Netease/minecraftWorlds/test/level.dat',
        ),
      );
      expect(await newWorld.readAsString(), 'saved world');
      final alias = runtime.gamePath(newWorld.path);
      expect(await File(alias).readAsString(), 'saved world');
      await runtime.terminateHelpers();
      expect(await File(alias).exists(), isFalse);
      expect(await newWorld.readAsString(), 'saved world');
    },
    skip: !Platform.isWindows,
  );

  test(
    'Windows selects packaged Steve and Alex without PNG import metadata',
    () async {
      final game = p.join(temp.path, '中文 game');
      final runtime = WindowsGameRuntime(
        storage,
        'skin',
        window: const HeadlessGameWindow(),
      );
      for (final skin in TestPlayerSkin.values) {
        expect(await runtime.prepareSkin(skin, game), {
          'skin': skin.name,
          'in_package': true,
        });
      }
    },
  );

  test(
    'Windows LAN probes only IPv4 ports belonging to the requested PID',
    () async {
      const listing =
          '  UDP    0.0.0.0:19132    *:*    100\n'
          '  UDP    127.0.0.1:19133    *:*    200\n'
          '  UDP    [::]:19134    *:*    100\n'
          '  UDP    192.168.1.2:19135    *:*    100\n';
      expect(parseWindowsLanProcessPorts(listing, 100), [19132]);
      final probed = <int>[];
      await discoverLanEndpointForProcess(
        100,
        windows: true,
        socketRunner: (_) async => ProcessResult(1, 0, listing, ''),
        portProbe: (port, {required timeout, required allowBarePong}) async {
          probed.add(port);
          return null;
        },
      );
      expect(probed, [19132]);
    },
  );
}
