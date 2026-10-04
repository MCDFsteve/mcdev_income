import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:path/path.dart' as p;

import 'development_test.dart' show MemoryPreferences;

const bpId = '11111111-1111-4111-8111-111111111111';
const rpId = '22222222-2222-4222-8222-222222222222';
const bpModule = '33333333-3333-4333-8333-333333333333';
const rpModule = '44444444-4444-4444-8444-444444444444';
const externalId = '55555555-5555-4555-8555-555555555555';
const selectionKey = 'development_selected_packs_v1';

class FailingBatchPreferences extends MemoryPreferences {
  bool failBatch = false;
  @override
  Future<void> apply(Map<String, Object?> changes) async {
    if (failBatch) throw StateError('selection write failed');
    await super.apply(changes);
  }
}

void main() {
  late Directory temp;
  late FailingBatchPreferences preferences;
  late NativeDevelopmentStorage storage;
  final launchers = <NativeDevelopmentLauncher>[];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-manifests-');
    temp = Directory(await temp.resolveSymbolicLinks());
    preferences = FailingBatchPreferences();
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

  NativeDevelopmentLauncher launcher([String sessionId = 'default']) {
    final result = NativeDevelopmentLauncher(
      storage,
      preferences,
      sessionId: sessionId,
    );
    launchers.add(result);
    return result;
  }

  Future<String> fixture({
    bool duplicateHeaders = false,
    bool duplicateModules = false,
  }) async {
    final root = p.join(temp.path, 'addon');
    for (final resource in [false, true]) {
      final dir = await Directory(
        p.join(root, resource ? 'RP' : 'BP'),
      ).create(recursive: true);
      await File(p.join(dir.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'format_version': 2,
          'header': {
            'name': resource ? 'Textures' : 'Logic',
            'description': 'keep this description',
            'uuid': resource && !duplicateHeaders ? rpId : bpId,
            'version': resource ? [2, 3, 4] : [1, 0, 0],
            'min_engine_version': [1, 20, 0],
          },
          'modules': [
            {
              'type': resource ? 'resources' : 'data',
              'uuid': resource && !duplicateModules ? rpModule : bpModule,
              'version': resource ? [2, 3, 4] : [1, 0, 0],
            },
            if (!resource)
              {
                'type': 'script',
                'uuid': '66666666-6666-4666-8666-666666666666',
                'version': [1, 0, 0],
                'entry': 'scripts/main.js',
              },
          ],
          'dependencies': [
            {
              'uuid': resource || duplicateHeaders ? bpId : rpId,
              'version': resource ? [1, 0, 0] : [2, 3, 4],
            },
            {
              'uuid': externalId,
              'version': [9, 8, 7],
            },
            {'module_name': '@minecraft/server', 'version': '1.10.0'},
          ],
          'metadata': {
            'authors': ['Author'],
          },
        }),
      );
    }
    return root;
  }

  Future<Map<String, dynamic>> manifest(String directory) async =>
      jsonDecode(await File(p.join(directory, 'manifest.json')).readAsString())
          as Map<String, dynamic>;

  Future<Map<String, String>> sources(String root) async => {
    for (final name in ['BP', 'RP'])
      name: await File(p.join(root, name, 'manifest.json')).readAsString(),
  };

  Future<void> verifyPair(NativeDevelopmentLauncher host) async {
    final bp = host.packs.singleWhere((pack) => pack.type == 'data');
    final rp = host.packs.singleWhere((pack) => pack.type == 'resources');
    final ids = <String>[];
    for (final (pack, other) in [(bp, rp), (rp, bp)]) {
      final value = await manifest(pack.directory);
      expect(value['header']['uuid'], pack.uuid);
      expect(value['header']['version'], pack.version);
      expect(value['dependencies'][0]['uuid'], other.uuid);
      expect(value['dependencies'][0]['version'], other.version);
      expect(value['dependencies'][1], {
        'uuid': externalId,
        'version': [9, 8, 7],
      });
      expect(value['dependencies'][2], {
        'module_name': '@minecraft/server',
        'version': '1.10.0',
      });
      expect(value['header']['min_engine_version'], [1, 20, 0]);
      expect(value['metadata'], {
        'authors': ['Author'],
      });
      ids.add(pack.uuid);
      for (final module in value['modules']) {
        ids.add(module['uuid'] as String);
        expect(module['version'], pack.version);
      }
    }
    expect(ids.toSet().length, ids.length);
    expect(
      await discoverModPacks(host.projects.single.packs.first.projectRoot!),
      hasLength(2),
    );
  }

  test(
    'project import only reads immediate pack folders and ignores nested backups',
    () async {
      final root = await fixture();
      final original = await sources(root);
      final backups = await Directory(
        p.join(root, 'backup', 'old-addon', 'BP'),
      ).create(recursive: true);
      final backup = File(p.join(backups.path, 'manifest.json'));
      await backup.writeAsString(original['BP']!);
      final broken = await Directory(
        p.join(root, 'backup', 'broken'),
      ).create(recursive: true);
      await File(p.join(broken.path, 'manifest.json')).writeAsString('{');
      // Names are arbitrary; identify the packs from their direct manifests.
      await Directory(p.join(root, 'BP')).rename(p.join(root, 'LogicSource'));
      await Directory(p.join(root, 'RP')).rename(p.join(root, 'TextureSource'));
      final host = launcher();
      await host.importMods(
        root,
        confirmUuidRefresh: () async {
          fail('Nested backup UUIDs must never trigger the refresh dialog');
        },
      );
      expect(host.error, isNull);
      expect(host.projects, hasLength(1));
      expect(host.projects.single.uuids.toSet(), {bpId, rpId});
      expect(
        host.projects.single.packs
            .map((pack) => p.basename(pack.directory))
            .toSet(),
        {'LogicSource', 'TextureSource'},
      );
      expect(
        host.projects.single.packs.map((pack) => pack.projectRoot),
        everyElement(root),
      );
      expect(await backup.readAsString(), original['BP']);
    },
  );

  for (final resource in [false, true]) {
    test(
      'selected single pack takes precedence over all nested manifests ($resource)',
      () async {
        final root = await fixture();
        final pack = p.join(root, resource ? 'RP' : 'BP');
        final backup = await Directory(
          p.join(pack, 'backup', 'pack'),
        ).create(recursive: true);
        await File(p.join(backup.path, 'manifest.json')).writeAsString('{');
        final host = launcher();
        await host.importMods(pack);
        expect(host.error, isNull);
        expect(host.packs, hasLength(1));
        expect(host.packs.single.uuid, resource ? rpId : bpId);
        expect(host.packs.single.directory, pack);
      },
    );
  }

  test(
    'importing a parent of a project never searches through the project',
    () async {
      await fixture();
      final host = launcher();
      await host.importMods(temp.path);
      expect(host.packs, isEmpty);
      expect(host.error, contains('直接子目录中没有找到'));
    },
  );

  test(
    'multiple direct packs of one type require a more specific selection',
    () async {
      final root = await fixture();
      final original = await sources(root);
      final backup = await Directory(p.join(root, 'BP-backup')).create();
      await File(
        p.join(backup.path, 'manifest.json'),
      ).writeAsString(original['BP']!);
      final host = launcher();
      await host.importMods(
        root,
        confirmUuidRefresh: () async {
          fail('Ambiguous sibling packs must not be randomized or imported');
        },
      );
      expect(host.packs, isEmpty);
      expect(host.error, contains('包含多个行为包或资源包'));
      expect(await sources(root), original);
      expect(
        await File(p.join(backup.path, 'manifest.json')).readAsString(),
        original['BP'],
      );
    },
  );

  test(
    'duplicate UUID import can be declined without modifying sources',
    () async {
      final root = await fixture(duplicateHeaders: true);
      final original = await sources(root);
      final host = launcher();
      await host.importMods(root);
      expect(host.error, '项目中存在重复 UUID。');
      var confirmations = 0;
      await host.importMods(
        root,
        confirmUuidRefresh: () async {
          confirmations++;
          return false;
        },
      );
      expect(confirmations, 1);
      expect(host.error, isNull);
      expect(host.packs, isEmpty);
      expect(await sources(root), original);
    },
  );

  for (final duplicateHeaders in [true, false]) {
    test(
      'refresh and import repairs header/module duplicates ($duplicateHeaders)',
      () async {
        final root = await fixture(
          duplicateHeaders: duplicateHeaders,
          duplicateModules: true,
        );
        final host = launcher();
        var confirmations = 0;
        await host.importMods(
          root,
          confirmUuidRefresh: () async {
            confirmations++;
            return true;
          },
        );
        expect(confirmations, 1);
        expect(host.error, isNull);
        expect(host.projects, hasLength(1));
        expect(host.selectedPacks, host.projects.single.uuids.toSet());
        await verifyPair(host);
        for (final pack in host.packs) {
          expect(
            pack.uuid,
            matches(
              RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              ),
            ),
          );
          expect(pack.uuid, isNot(isIn([bpId, rpId])));
        }
        final reopened = launcher();
        await reopened.refresh();
        expect(reopened.selectedPacks, host.selectedPacks);
        await verifyPair(reopened);
      },
    );
  }

  test(
    'archive repair commits extracted manifests and preserves the archive',
    () async {
      final root = await fixture(duplicateHeaders: true);
      final original = await sources(root);
      final archive = Archive();
      for (final entry in original.entries) {
        final data = utf8.encode(entry.value);
        archive.addFile(
          ArchiveFile('${entry.key}/manifest.json', data.length, data),
        );
      }
      final input = File(p.join(temp.path, 'addon.mcaddon'));
      final bytes = ZipEncoder().encode(archive);
      await input.writeAsBytes(bytes);
      final host = launcher();
      await host.importMods(input.path, confirmUuidRefresh: () async => true);
      expect(host.error, isNull);
      await verifyPair(host);
      expect(await input.readAsBytes(), bytes);
      expect(await sources(root), original);
      expect(
        await Directory(
          p.join(storage.paths.root, 'projects'),
        ).list().map((entry) => p.basename(entry.path)).toList(),
        everyElement(isNot(startsWith('.import-'))),
      );
    },
  );

  test(
    'detail actions preserve project identity and selections in every tab',
    () async {
      final root = await fixture();
      final host = launcher();
      await host.importMods(root);
      final project = host.projects.single;
      final importedAt = project.importedAt;
      await host.togglePack(rpId, false);
      final second = launcher('second');
      await second.refresh();
      await second.togglePack(rpId, true);
      await host.randomizeProjectUuids(project.id);
      expect(host.error, isNull);
      expect(host.projects.single.id, project.id);
      expect(host.projects.single.importedAt, importedAt);
      final newBp = host.packs.singleWhere((pack) => pack.type == 'data').uuid;
      final newRp = host.packs
          .singleWhere((pack) => pack.type == 'resources')
          .uuid;
      expect(host.selectedPacks, {newBp});
      await second.refresh();
      expect(second.selectedPacks, {newRp});
      await verifyPair(host);
      await host.upgradeProjectVersion(project.id);
      await host.upgradeProjectVersion(project.id);
      expect(host.error, isNull);
      expect(host.packs.singleWhere((p) => p.type == 'data').version, [
        1,
        0,
        2,
      ]);
      expect(host.packs.singleWhere((p) => p.type == 'resources').version, [
        2,
        3,
        6,
      ]);
      expect(host.selectedPacks, {newBp});
      await verifyPair(host);
      final reopened = launcher();
      await reopened.refresh();
      await verifyPair(reopened);
    },
  );

  test('version upgrade uses the latest source version', () async {
    final root = await fixture();
    final host = launcher();
    await host.importMods(root);
    final bp = await manifest(p.join(root, 'BP'));
    bp['header']['version'] = [3, 2, 9];
    await File(
      p.join(root, 'BP', 'manifest.json'),
    ).writeAsString(jsonEncode(bp));
    await host.upgradeProjectVersion(host.projects.single.id);
    expect(host.error, isNull);
    expect(host.packs.singleWhere((p) => p.type == 'data').version, [3, 2, 10]);
    await verifyPair(host);
  });

  test(
    'detail UUID refresh repairs edited UUIDs and retains registered references',
    () async {
      final root = await fixture();
      final host = launcher();
      await host.importMods(root);
      await host.togglePack(rpId, false);
      final id = host.projects.single.id;
      final rpFile = File(p.join(root, 'RP', 'manifest.json'));
      final rp = await manifest(p.join(root, 'RP'));
      rp['header']['uuid'] = bpId;
      rp['modules'][0]['uuid'] = bpModule;
      await rpFile.writeAsString(jsonEncode(rp));
      await host.upgradeProjectVersion(id);
      expect(host.error, '项目中存在重复 UUID。');
      await host.randomizeProjectUuids(id);
      expect(host.error, isNull);
      expect(host.selectedPacks, {
        host.packs.singleWhere((pack) => pack.type == 'data').uuid,
      });
      await verifyPair(host);
    },
  );

  test(
    'selection write failure rolls back UUID files, registry and selections',
    () async {
      final root = await fixture();
      final host = launcher();
      await host.importMods(root);
      final original = await sources(root);
      final registry = File(p.join(storage.paths.root, 'projects.json'));
      final registered = await registry.readAsString();
      final selected = preferences.getString(selectionKey);
      preferences.failBatch = true;
      await host.randomizeProjectUuids(host.projects.single.id);
      expect(host.error, contains('selection write failed'));
      expect(await sources(root), original);
      expect(await registry.readAsString(), registered);
      expect(preferences.getString(selectionKey), selected);
      expect(host.selectedPacks, {bpId, rpId});
    },
  );

  test(
    'failed repaired import restores source manifests and registry',
    () async {
      final root = await fixture(duplicateHeaders: true);
      final original = await sources(root);
      final host = launcher();
      await host.refresh();
      preferences.fail = true;
      await host.importMods(root, confirmUuidRefresh: () async => true);
      expect(host.error, contains('无法保存项目选择'));
      expect(await sources(root), original);
      expect(host.packs, isEmpty);
      preferences.fail = false;
      await host.refresh();
      expect(host.packs, isEmpty);
    },
  );

  test('invalid companion and running game prevent any source edits', () async {
    final root = await fixture();
    final host = launcher();
    await host.importMods(root);
    final original = await sources(root);
    final id = host.projects.single.id;
    host.running = true;
    await expectLater(host.randomizeProjectUuids(id), throwsException);
    expect(await sources(root), original);
    host.running = false;
    final rp = File(p.join(root, 'RP', 'manifest.json'));
    await rp.writeAsString('{');
    await host.upgradeProjectVersion(id);
    expect(host.error, isNotNull);
    expect(
      await File(p.join(root, 'BP', 'manifest.json')).readAsString(),
      original['BP'],
    );
    expect(await rp.readAsString(), '{');
  });
}
