import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/download_io.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/platform/development_capabilities.dart';
import 'package:mcdev_income/development/platform/game_runtime_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/test_world_io.dart';

import 'development_test.dart' show MemoryPreferences;

/// Runs the real launch preparation, but captures its output instead of ever
/// starting a game. The deliberate stop is checked so earlier failures fail tests.
class _ConfigCaptureRuntime extends GameRuntime {
  _ConfigCaptureRuntime(DevelopmentStorage storage) : super(storage, 'default');

  static const stopped = 'Config captured; no game process started';
  Map<String, dynamic>? config;

  @override
  DevelopmentCapabilities get capabilities => DevelopmentCapabilities.windows;
  @override
  String get baseRuntime => prefix;
  @override
  String? get wine => null;
  @override
  String get testDirectory => p.join(prefix, 'test');
  @override
  String gamePath(String path) => path;
  @override
  String testFilePath(String name) => p.join(testDirectory, name);
  @override
  Future<Map<String, Object>> prepareSkin(
    TestPlayerSkin skin,
    String gameDirectory,
  ) async => {'skin': skin.name, 'in_package': true};
  @override
  Future<String> roaming() async => p.join(prefix, 'roaming');
  @override
  Future<bool> ready() async => true;
  @override
  Future<void> install(
    http.Client client,
    DownloadControl? control,
    void Function(StorageMigrationProgress) onProgress,
  ) async => throw UnimplementedError();
  @override
  Future<void> prepare(
    void Function(StorageMigrationProgress) onProgress,
  ) async {
    await Directory(testDirectory).create(recursive: true);
  }

  @override
  Map<String, String> environment({Map<String, String> overrides = const {}}) =>
      overrides;
  @override
  Future<Process> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required String version,
    required String displayName,
    required String renderer,
    required bool fullscreenShortcut,
    Map<String, String> overrides = const {},
  }) async {
    final argument = arguments
        .where((arg) => arg.startsWith('config='))
        .singleOrNull;
    config = argument == null
        ? null
        : jsonDecode(
                await File(argument.substring('config='.length)).readAsString(),
              )
              as Map<String, dynamic>;
    throw StateError(stopped);
  }

  @override
  Future<void> stop(Process child) async => throw UnimplementedError();
  @override
  Future<void> terminateHelpers() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late NativeDevelopmentLauncher launcher;
  late _ConfigCaptureRuntime runtime;
  late String worlds;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-world-type-');
    final preferences = MemoryPreferences();
    final storage = NativeDevelopmentStorage(
      preferences: preferences,
      defaultRoot: p.join(temp.path, 'data'),
      lockPath: p.join(temp.path, 'storage.lock'),
    );
    await storage.initialize();
    runtime = _ConfigCaptureRuntime(storage);
    worlds = p.join(
      await runtime.roaming(),
      'MinecraftPE_Netease',
      'minecraftWorlds',
    );
    final game = Directory(p.join(storage.paths.games, '3.8.0.313229'));
    await game.create(recursive: true);
    await File(
      p.join(game.path, 'Minecraft.Windows.exe'),
    ).writeAsString('fixture only');
    launcher =
        NativeDevelopmentLauncher(
            storage,
            preferences,
            runtimeBackend: runtime,
            cookieProvider: () async => 'oversea_authcode=fixture-only',
            client: MockClient((request) async {
              expect(request.url.path, '/users/refresh_mcs_user_token');
              return http.Response(
                jsonEncode({
                  'status': 'ok',
                  'data': {
                    'user_id': 1234,
                    'token': 'synthetic-game-token',
                    'expired_at':
                        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                  },
                }),
                200,
              );
            }),
          )
          ..selectedVersion = '3.8.0.313229'
          ..games = [LocalGame('3.8.0.313229', game.path)];
  });

  tearDown(() async {
    launcher.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> launch({bool menuOnly = false}) async {
    await launcher.launchTest(
      worldName: '地图类型测试',
      creative: true,
      menuOnly: menuOnly,
      seed: '  12345  ',
    );
    expect(
      launcher.error,
      StateError(_ConfigCaptureRuntime.stopped).toString(),
    );
    expect(launcher.running, isFalse);
    expect(launcher.busy, isFalse);
  }

  for (final (type, configValue) in [
    (TestWorldType.infinite, 1),
    (TestWorldType.flat, 2),
  ]) {
    test(
      'new ${type.name} world writes world_type=$configValue to the launch config',
      () async {
        await launcher.chooseNewWorld(true);
        await launcher.chooseWorldType(type);
        await launch();
        final world = runtime.config!['world_info'] as Map;
        expect(world['world_type'], configValue);
        expect(world['level_id'], startsWith('mcdev_test_'));
        expect(world['name'], '地图类型测试');
        expect(world['seed'], '12345');
      },
    );
  }

  test(
    'resuming ignores new-world type and does not modify the saved world',
    () async {
      final previous = await TestWorldStore(worlds).prepare(fresh: true);
      final level = File(p.join(worlds, previous.levelId, 'level.dat'));
      await level.parent.create(recursive: true);
      await level.writeAsString('saved world with its original generator');
      await launcher.chooseWorldType(TestWorldType.flat);
      await launch();
      final world = runtime.config!['world_info'] as Map;
      expect(world['level_id'], previous.levelId);
      expect(world['world_type'], 1);
      expect(world['seed'], isEmpty);
      expect(
        await level.readAsString(),
        'saved world with its original generator',
      );
      expect(launcher.newWorldType, TestWorldType.flat);
    },
  );

  test('menu-only launch creates no world or world config', () async {
    await launcher.chooseNewWorld(true);
    await launcher.chooseWorldType(TestWorldType.flat);
    await launch(menuOnly: true);
    expect(runtime.config, isNull);
    expect(await Directory(worlds).exists(), isFalse);
  });
}
