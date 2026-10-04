import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/test_session_io.dart';
import 'package:mcdev_income/storage/file_lock.dart';
import 'development_test.dart' show MemoryPreferences;

void main() {
  late Directory temporary;
  late MemoryPreferences preferences;
  late NativeDevelopmentStorage storage;
  final launchers = <NativeDevelopmentLauncher>[];

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mcdev-sessions-');
    temporary = Directory(await temporary.resolveSymbolicLinks());
    preferences = MemoryPreferences();
    storage = NativeDevelopmentStorage(
      preferences: preferences,
      defaultRoot: p.join(temporary.path, 'data'),
      lockPath: p.join(temporary.path, 'config', 'storage.lock'),
    );
    await storage.initialize();
  });

  tearDown(() async {
    for (final launcher in launchers) {
      launcher.dispose();
    }
    launchers.clear();
    await temporary.delete(recursive: true);
  });

  NativeDevelopmentLauncher launcher([String id = 'default']) {
    final result = NativeDevelopmentLauncher(
      storage,
      preferences,
      sessionId: id,
    );
    launchers.add(result);
    return result;
  }

  Future<void> installFixture(String version) async {
    final directory = await Directory(
      p.join(storage.paths.games, version),
    ).create();
    await File(
      p.join(directory.path, 'Minecraft.Windows.exe'),
    ).writeAsString('fixture');
    await File(p.join(directory.path, '.mcdev-game.json')).writeAsString('{}');
  }

  Future<String> createProject(String name, String uuid) async {
    final directory = await Directory(p.join(temporary.path, name)).create();
    await File(p.join(directory.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'header': {
          'name': name,
          'uuid': uuid,
          'version': [1, 0, 0],
        },
        'modules': [
          {'type': 'data'},
        ],
      }),
    );
    return directory.path;
  }

  test(
    'the first tab retains legacy preferences and its existing prefix',
    () async {
      preferences.values.addAll({
        'development_game_version_v1': '3.9.0.1',
        'development_player_skin_v1': 'alex',
        'development_show_developer_console_v1': 1,
        'development_new_world_v1': 1,
        'development_world_seed_v1': 'previous seed',
      });
      final first = launcher();
      final second = launcher('second');
      expect(first.gamePrefix, p.join(storage.paths.prefixes, 'game'));
      expect(second.gamePrefix, p.join(storage.paths.prefixes, 'game-second'));
      expect(first.selectedVersion, '3.9.0.1');
      expect(first.playerSkin, TestPlayerSkin.alex);
      expect(first.showDeveloperConsole, isTrue);
      expect(first.useNewWorld, isTrue);
      expect(first.newWorldSeed, 'previous seed');
      expect(second.selectedVersion, isNull);
      expect(second.playerSkin, TestPlayerSkin.steve);
      expect(second.showDeveloperConsole, isFalse);
      expect(second.useNewWorld, isFalse);
      expect(second.newWorldSeed, isEmpty);
    },
  );

  test(
    'version, renderer, and test settings persist independently for each tab',
    () async {
      await installFixture('3.9.0.1');
      await installFixture('3.10.0.420447');
      final first = launcher();
      final second = launcher('second');
      await first.refresh();
      await second.refresh();
      await first.chooseVersion('3.9.0.1');
      await first.chooseRenderer(GameRenderer.renderDragon);
      await first.choosePlayerSkin(TestPlayerSkin.alex);
      await first.chooseFrameLimit(false);
      await first.chooseNewWorld(true);
      await first.chooseDeveloperConsole(true);
      await first.chooseFullscreenShortcut(true);
      await first.chooseDisableCompanion(false);
      await second.chooseVersion('3.10.0.420447');
      await second.choosePerformanceOptimization(false);
      expect(first.error, isNull);
      expect(second.error, isNull);
      final reopenedFirst = launcher();
      final reopenedSecond = launcher('second');
      expect(reopenedFirst.selectedVersion, '3.9.0.1');
      expect(reopenedFirst.renderer, GameRenderer.renderDragon);
      expect(reopenedFirst.playerSkin, TestPlayerSkin.alex);
      expect(reopenedFirst.limit60Fps, isFalse);
      expect(reopenedFirst.useNewWorld, isTrue);
      expect(reopenedFirst.showDeveloperConsole, isTrue);
      expect(reopenedFirst.fullscreenShortcut, isTrue);
      expect(reopenedFirst.disableCompanion, isFalse);
      expect(reopenedFirst.performanceOptimization, isTrue);
      expect(reopenedSecond.selectedVersion, '3.10.0.420447');
      expect(reopenedSecond.renderer, GameRenderer.openGL);
      expect(reopenedSecond.playerSkin, TestPlayerSkin.steve);
      expect(reopenedSecond.limit60Fps, isTrue);
      expect(reopenedSecond.useNewWorld, isFalse);
      expect(reopenedSecond.showDeveloperConsole, isFalse);
      expect(reopenedSecond.fullscreenShortcut, isFalse);
      expect(reopenedSecond.disableCompanion, isTrue);
      expect(reopenedSecond.performanceOptimization, isFalse);
    },
  );

  test(
    'legacy project selection migrates only to the first tab and stays independent',
    () async {
      await File(p.join(storage.paths.root, 'projects.json')).writeAsString(
        jsonEncode([
          {
            'name': 'Legacy',
            'uuid': 'legacy',
            'version': [1, 0, 0],
            'type': 'data',
            'path': '/fixture/legacy',
            'selected': true,
          },
        ]),
      );
      final first = launcher();
      final second = launcher('second');
      await first.refresh();
      await second.refresh();
      expect(first.selectedPacks, {'legacy'});
      expect(second.selectedPacks, isEmpty);
      await second.togglePacks(['legacy'], true);
      await first.togglePacks(['legacy'], false);
      await second.refresh();
      expect(second.selectedPacks, {'legacy'});
      final reopened = launcher();
      await reopened.refresh();
      expect(reopened.selectedPacks, isEmpty);
      expect(first.error, isNull);
      expect(second.error, isNull);
    },
  );

  test(
    'stale tabs import and remove projects without losing newer shared registry entries',
    () async {
      const firstId = '11111111-1111-4111-8111-111111111111';
      const secondId = '22222222-2222-4222-8222-222222222222';
      const thirdId = '33333333-3333-4333-8333-333333333333';
      final firstSource = await createProject('First', firstId);
      final secondSource = await createProject('Second', secondId);
      final thirdSource = await createProject('Third', thirdId);
      final first = launcher();
      final second = launcher('second');
      await first.refresh();
      await second.refresh();
      await first.importMods(firstSource);
      await second.importMods(secondSource);
      expect(
        second.packs.map((pack) => pack.uuid),
        containsAll([firstId, secondId]),
      );
      expect(second.selectedPacks, {secondId});
      await first.importMods(thirdSource);
      expect(first.selectedPacks, {firstId, thirdId});
      // Second has not refreshed since Third was imported.
      await second.removePacks([firstId]);
      await first.refresh();
      expect(first.packs.map((pack) => pack.uuid).toSet(), {secondId, thirdId});
      expect(first.selectedPacks, {thirdId});
      expect(second.selectedPacks, {secondId});
      expect(await Directory(firstSource).exists(), isTrue);
      expect(first.error, isNull);
      expect(second.error, isNull);
    },
  );

  test(
    'a secondary tab can edit projects before the legacy tab first opens',
    () async {
      const legacySelected = '11111111-1111-4111-8111-111111111111';
      const legacyUnselected = '22222222-2222-4222-8222-222222222222';
      const imported = '33333333-3333-4333-8333-333333333333';
      await File(p.join(storage.paths.root, 'projects.json')).writeAsString(
        jsonEncode([
          for (final id in [legacySelected, legacyUnselected])
            {
              'name': 'Legacy $id',
              'uuid': id,
              'version': [1, 0, 0],
              'type': 'data',
              'path': '/fixture/$id',
              'selected': id == legacySelected,
            },
        ]),
      );
      final second = launcher('second');
      await second.refresh();
      expect(second.selectedPacks, isEmpty);
      await second.importMods(await createProject('New', imported));
      await second.removePacks([legacyUnselected]);
      expect(second.error, isNull);
      expect(second.selectedPacks, {imported});
      // Both edits rewrote the registry without its old selection flags. The
      // original selection must already be migrated for the unopened first tab.
      final first = launcher();
      await first.refresh();
      expect(first.selectedPacks, {legacySelected});
      expect(first.packs.map((pack) => pack.uuid).toSet(), {
        legacySelected,
        imported,
      });
    },
  );

  test('session IDs cannot escape their container or preference scope', () {
    for (final id in ['', '../another', '/absolute', 'two.tabs', 'x' * 65]) {
      expect(() => launcher(id), throwsArgumentError);
    }
  });

  Future<void> runSession(
    String id,
    Future<void> Function(void Function()) run,
  ) => withTestSessionLocks(
    storageLock: storage.lockPath,
    prefixes: storage.paths.prefixes,
    sessionId: id,
    run: run,
  );

  test(
    'game lifetimes overlap while preparation serializes and duplicate tabs stay locked',
    () async {
      final firstEntered = Completer<void>();
      final firstPrepared = Completer<void>();
      final stopFirst = Completer<void>();
      final secondEntered = Completer<void>();
      final stopSecond = Completer<void>();
      final first = runSession('first', (release) async {
        firstEntered.complete();
        await firstPrepared.future;
        release();
        await stopFirst.future;
      });
      await firstEntered.future;
      final second = runSession('second', (release) async {
        secondEntered.complete();
        release();
        await stopSecond.future;
      });
      // Give the second caller an event turn to attempt the shared preparation.
      await Future<void>.delayed(Duration.zero);
      expect(secondEntered.isCompleted, isFalse);
      firstPrepared.complete();
      await secondEntered.future.timeout(const Duration(seconds: 5));
      expect(stopFirst.isCompleted, isFalse);
      await expectLater(
        runSession('first', (_) async {}),
        throwsA(isA<FileSystemException>()),
      );
      await withFileLock(storage.lockPath, () async {}, wait: false);
      stopFirst.complete();
      await first;
      expect(stopSecond.isCompleted, isFalse);
      await runSession('first', (release) async => release());
      stopSecond.complete();
      await second;
    },
  );

  for (final releaseFirst in [false, true]) {
    test(
      'failed session releases both locks (${releaseFirst ? 'running' : 'preparing'})',
      () async {
        final failure = StateError('synthetic launch failure');
        await expectLater(
          runSession('failed', (release) async {
            if (releaseFirst) release();
            throw failure;
          }),
          throwsA(same(failure)),
        );
        await runSession('failed', (release) async => release());
        await withFileLock(storage.lockPath, () async {}, wait: false);
      },
    );
  }

  test(
    'session game copies isolate SDK state and refresh after source changes',
    () async {
      await installFixture('3.10.0.420447');
      final source = p.join(storage.paths.games, '3.10.0.420447');
      await File(p.join(source, 'netease_data.json')).writeAsString('original');
      Future<String> clone(String id) => prepareSessionGame(
        source: source,
        prefix: p.join(storage.paths.prefixes, id),
        version: '3.10.0.420447',
      );
      final first = await clone('first');
      final second = await clone('second');
      await File(
        p.join(first, 'netease_data.json'),
      ).writeAsString('first account');
      await File(
        p.join(first, 'Minecraft.Windows.exe'),
      ).writeAsString('first mutable executable');
      expect(
        await File(p.join(second, 'netease_data.json')).readAsString(),
        'original',
      );
      expect(
        await File(p.join(source, 'netease_data.json')).readAsString(),
        'original',
      );
      expect(
        await File(p.join(second, 'Minecraft.Windows.exe')).readAsString(),
        'fixture',
      );
      expect(await clone('first'), first);
      expect(
        await File(p.join(first, 'netease_data.json')).readAsString(),
        'first account',
      );
      await File(
        p.join(source, 'Minecraft.Windows.exe'),
      ).writeAsString('new source executable');
      await clone('first');
      expect(
        await File(p.join(first, 'Minecraft.Windows.exe')).readAsString(),
        'new source executable',
      );
      expect(
        await File(p.join(second, 'Minecraft.Windows.exe')).readAsString(),
        'fixture',
      );
    },
    skip: !Platform.isMacOS,
  );
}
