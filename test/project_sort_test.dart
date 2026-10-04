import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';

import 'development_test.dart' show MemoryPreferences;

ModPack pack(
  String name, {
  DateTime? imported,
  DateTime? launched,
  String? root,
}) => ModPack(
  name: name,
  uuid: name,
  version: const [1, 0, 0],
  type: 'data',
  directory: '/projects/$name',
  projectRoot: root,
  importedAt: imported,
  lastLaunchedAt: launched,
);

void main() {
  final early = DateTime.utc(2026, 1, 1);
  final later = DateTime.utc(2026, 2, 1);

  test(
    'all sort directions keep unknown launches last and preserve source order',
    () {
      final projects = groupModProjects([
        pack('zulu', imported: early, launched: later),
        pack('Alpha', imported: later, launched: early),
        pack('bravo'),
      ]);
      final expected = {
        ProjectSortOrder.importedNewest: ['Alpha', 'zulu', 'bravo'],
        ProjectSortOrder.importedOldest: ['bravo', 'zulu', 'Alpha'],
        ProjectSortOrder.launchedNewest: ['zulu', 'Alpha', 'bravo'],
        ProjectSortOrder.launchedOldest: ['Alpha', 'zulu', 'bravo'],
        ProjectSortOrder.nameAscending: ['Alpha', 'bravo', 'zulu'],
        ProjectSortOrder.nameDescending: ['zulu', 'bravo', 'Alpha'],
      };
      for (final entry in expected.entries) {
        expect(
          sortModProjects(projects, entry.key).map((item) => item.name),
          entry.value,
        );
      }
      expect(projects.map((item) => item.name), ['zulu', 'Alpha', 'bravo']);
    },
  );

  test(
    'paired packs share first import and latest launch; legacy ties stay deterministic',
    () {
      final projects = groupModProjects([
        pack('Behavior', imported: early, launched: early, root: '/paired'),
        pack('Resources', imported: later, launched: later, root: '/paired'),
        pack('Legacy A'),
        pack('Legacy B'),
      ]);
      expect(projects.first.importedAt, early);
      expect(projects.first.lastLaunchedAt, later);
      expect(
        sortModProjects(
          projects,
          ProjectSortOrder.importedOldest,
        ).map((item) => item.name),
        ['Legacy A', 'Legacy B', 'Behavior'],
      );
      expect(
        sortModProjects(
          projects,
          ProjectSortOrder.launchedNewest,
        ).map((item) => item.name),
        ['Behavior', 'Legacy B', 'Legacy A'],
      );
      final launched = projects.first.packs.first.withLastLaunch(later);
      expect(launched.importedAt, early);
      expect(launched.projectRoot, '/paired');
      expect(launched.lastLaunchedAt, later);
    },
  );

  group('native project registry', () {
    late Directory temp;
    late MemoryPreferences preferences;
    late NativeDevelopmentStorage storage;
    final launchers = <NativeDevelopmentLauncher>[];

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('mcdev-project-sort-');
      temp = Directory(await temp.resolveSymbolicLinks());
      preferences = MemoryPreferences();
      storage = NativeDevelopmentStorage(
        preferences: preferences,
        defaultRoot: p.join(temp.path, 'data'),
        lockPath: p.join(temp.path, 'storage.lock'),
      );
      await storage.initialize();
    });
    tearDown(() async {
      for (final launcher in launchers) {
        launcher.dispose();
      }
      launchers.clear();
      await temp.delete(recursive: true);
    });
    NativeDevelopmentLauncher open([String id = 'default']) {
      final launcher = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: id,
      );
      launchers.add(launcher);
      return launcher;
    }

    Future<String> source(String name, String uuid) async {
      final directory = await Directory(p.join(temp.path, name)).create();
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
      'imports record time, reimports retain history, and another tab does not erase it',
      () async {
        final path = await source(
          'First',
          '794c9e43-1145-4190-9834-56a9dba88a23',
        );
        final first = open();
        final before = DateTime.now().toUtc();
        await first.importMods(path);
        expect(first.error, isNull);
        final imported = first.packs.single.importedAt!;
        expect(imported.isBefore(before), isFalse);
        final registry = File(p.join(storage.paths.root, 'projects.json'));
        final rows = jsonDecode(await registry.readAsString()) as List;
        rows.single['lastLaunchedAt'] = later.toIso8601String();
        await registry.writeAsString(jsonEncode(rows));
        final other = open('other');
        await other.importMods(
          await source('Second', '894c9e43-1145-4190-9834-56a9dba88a23'),
        );
        await first.importMods(path);
        expect(first.error, isNull);
        final saved = first.packs.singleWhere((item) => item.name == 'First');
        expect(saved.importedAt, imported);
        expect(saved.lastLaunchedAt, later);
        final reopened = open();
        await reopened.refresh();
        expect(reopened.packs.length, 2);
        expect(
          reopened.packs
              .singleWhere((item) => item.name == 'First')
              .lastLaunchedAt,
          later,
        );
        await reopened.chooseProjectSortOrder(ProjectSortOrder.launchedNewest);
        expect(reopened.sortedProjects.first.name, 'First');
        // A rejected launch must not turn an imported project into a launched one.
        await reopened.launchTest(
          worldName: 'test',
          creative: true,
          menuOnly: false,
        );
        expect(reopened.error, isNotNull);
        expect(
          reopened.packs
              .singleWhere((item) => item.name == 'Second')
              .lastLaunchedAt,
          isNull,
        );
      },
    );

    test(
      'sort preferences persist per tab, work while running, and survive save failure',
      () async {
        final first = open()..running = true;
        final second = open('other');
        await first.chooseProjectSortOrder(ProjectSortOrder.nameAscending);
        await second.chooseProjectSortOrder(ProjectSortOrder.launchedNewest);
        expect(open().projectSortOrder, ProjectSortOrder.nameAscending);
        expect(open('other').projectSortOrder, ProjectSortOrder.launchedNewest);
        preferences.fail = true;
        await expectLater(
          first.chooseProjectSortOrder(ProjectSortOrder.importedOldest),
          throwsException,
        );
        expect(first.projectSortOrder, ProjectSortOrder.nameAscending);
        first.running = false;
      },
    );

    test(
      'legacy and malformed timestamps remain readable and preserve insertion order',
      () async {
        await File(p.join(storage.paths.root, 'projects.json')).writeAsString(
          jsonEncode([
            for (final name in ['Old', 'New'])
              {
                'name': name,
                'uuid': name,
                'version': [1, 0, 0],
                'type': 'data',
                'path': '/missing/$name',
                'importedAt': 'invalid',
                'lastLaunchedAt': null,
              },
          ]),
        );
        final launcher = open();
        await launcher.refresh();
        expect(launcher.packs, hasLength(2));
        expect(
          launcher.projects.every(
            (item) => item.importedAt == null && item.lastLaunchedAt == null,
          ),
          isTrue,
        );
        expect(launcher.sortedProjects.map((item) => item.name), [
          'New',
          'Old',
        ]);
        await launcher.chooseProjectSortOrder(ProjectSortOrder.importedOldest);
        expect(launcher.sortedProjects.map((item) => item.name), [
          'Old',
          'New',
        ]);
      },
    );
  });
}
