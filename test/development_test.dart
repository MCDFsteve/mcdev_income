import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core/preferences.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/mcs_api.dart';
import 'package:mcdev_income/development/download_io.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';

class MemoryPreferences implements PreferenceStore {
  final values = <String, Object>{};
  bool fail = false;
  @override
  String? getString(String key) => values[key] as String?;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<bool> setString(String key, String value) async {
    if (fail) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<void> apply(Map<String, Object?> changes) async {
    for (final row in changes.entries) {
      if (row.value == null) {
        values.remove(row.key);
      } else {
        values[row.key] = row.value!;
      }
    }
  }
}

Uint8List unhex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);
void main() {
  late Directory temp;
  late MemoryPreferences preferences;
  late NativeDevelopmentStorage storage;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-test-');
    temp = Directory(await temp.resolveSymbolicLinks());
    preferences = MemoryPreferences();
    storage = NativeDevelopmentStorage(
      preferences: preferences,
      defaultRoot: p.join(temp.path, 'data'),
      lockPath: p.join(temp.path, 'config', 'lock'),
    );
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test('Dart protocol reproduces official native offline vectors', () async {
    final fixtures = jsonDecode(
      await File('test/fixtures/mcs-protocol.json').readAsString(),
    );
    for (final vector in fixtures['tokens']) {
      expect(
        mcsDynamicToken(
          vector['resource'],
          vector['body'],
          token: vector['session_token'],
        ),
        vector['expected'],
      );
    }
    for (final vector in fixtures['encrypted']) {
      final raw = unhex(vector['envelope_hex']);
      final decoded = decryptMcsEnvelope(raw);
      expect(decoded.bytes, unhex(vector['body_hex']));
      expect(decoded.key, unhex(vector['request_key_hex']));
      final encoded = encryptMcsEnvelope(
        utf8.decode(decoded.bytes),
        index: raw.last >> 4,
        iv: raw.sublist(0, 16),
        key: decoded.key,
      );
      expect(encoded.bytes, raw);
    }
    expect(() => decryptMcsEnvelope(Uint8List(33)), throwsFormatException);
  });
  test(
    'catalog uses server stable version and signs patch and archive paths',
    () {
      final game = GamePackage.fromCatalog({
        'stable_x64': '3.10.0.123',
        'entities': {
          '3.10.0.123': {
            'url': 'https://x19.gdl.netease.com/game/3.10.0.123/patch.json',
            'md5': 'a' * 32,
          },
        },
      });
      expect(game.zipUrl.path, '/game/3.10.0.123.zip');
      final signed = signMcsDownload(
        game.zipUrl,
        now: DateTime.utc(2026, 9, 30),
      );
      expect(signed.queryParameters['key1'], hasLength(32));
      expect(signed.queryParameters['key2'], isNotEmpty);
      expect(
        () => GamePackage.fromCatalog({'stable_x64': '../evil'}),
        throwsA(isA<DevelopmentStorageException>()),
      );
    },
  );
  test(
    'complete catalog includes channels, architectures and other versions without stable fallback',
    () {
      Map<String, dynamic> entry(String version, String architecture) => {
        'url': 'https://x19.gdl.netease.com/$architecture.$version/patch.json',
        'md5': 'a' * 32,
        'size': 1234,
      };
      final catalog = GameCatalog.fromJson({
        'stable_x64': '3.8.0.1',
        'stable_new_x64': '3.9.0.2',
        'beta_x64': '3.9.0.3',
        'test_x64': '3.9.0.4',
        'test': '2.0.0.5',
        'entities': {
          for (final version in [
            '3.8.0.1',
            '3.9.0.2',
            '3.9.0.3',
            '3.9.0.4',
            '3.10.0.1',
          ])
            version: entry(version, 'Win64'),
          '2.0.0.5': entry('2.0.0.5', 'Win32'),
          'PCLauncher_x64': entry('launcher', 'Win64'),
          '../escape': entry('escape', 'Win64'),
          '3.0.0.1': {'url': 'file:///bad/patch.json', 'md5': 'a' * 32},
        },
      });
      expect(catalog.packages.length, 6);
      expect(catalog.skippedEntries, 1);
      expect(catalog.packages.first.version, '3.10.0.1');
      expect(catalog.packages.first.channels, isEmpty);
      expect(catalog.stable!.version, '3.8.0.1');
      expect(
        catalog.packages
            .where((game) => game.channels.contains(GameChannel.beta))
            .single
            .version,
        '3.9.0.3',
      );
      expect(catalog.packages.last.architecture, GameArchitecture.x86);
      expect(catalog.packages.last.channels, [GameChannel.test]);
      final noStable = GameCatalog.fromJson({
        'entities': {'3.9.0.3': entry('3.9.0.3', 'Win64')},
      });
      expect(noStable.packages.single.version, '3.9.0.3');
      expect(noStable.stable, isNull);
    },
  );

  test(
    'install requested beta exactly, keep installed versions and persist active selection',
    () async {
      await storage.initialize();
      const stableVersion = '3.8.0.1', betaVersion = '3.9.0.7';
      final stable = await Directory(
        p.join(storage.paths.games, stableVersion),
      ).create();
      await File(
        p.join(stable.path, 'Minecraft.Windows.exe'),
      ).writeAsString('stable');
      await File(p.join(stable.path, '.mcdev-game.json')).writeAsString('{}');
      final executable = utf8.encode('synthetic beta game');
      final patch = jsonEncode({
        'md5': {'Minecraft.Windows.exe': md5.convert(executable).toString()},
      });
      final archive = Archive()
        ..add(
          ArchiveFile('Minecraft.Windows.exe', executable.length, executable),
        );
      final zip = ZipEncoder().encode(archive);
      final downloads = <String>[];
      final client = MockClient((request) async {
        if (request.url.host == 'mc-launcher.webapp.163.com') {
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
        }
        if (request.url.path == '/serverlist/experience.0.4.json') {
          return http.Response(
            '{"WebServerUrl":"https://x19mclexpr.nie.netease.com"}',
            200,
          );
        }
        if (request.url.path ==
            '/interconn/web/pack-setting/get-for-mcstudio') {
          return http.Response(
            jsonEncode({
              'code': 0,
              'entity': {
                'setting_value': jsonEncode({
                  'stable_x64': stableVersion,
                  'beta_x64': betaVersion,
                  'entities': {
                    for (final version in [stableVersion, betaVersion])
                      version: {
                        'url':
                            'https://x19.gdl.netease.com/Win64.$version/patch.json',
                        'md5': md5.convert(utf8.encode(patch)).toString(),
                      },
                  },
                }),
              },
            }),
            200,
          );
        }
        downloads.add(request.url.path);
        if (request.url.path == '/Win64.$betaVersion/patch.json') {
          return http.Response(patch, 200);
        }
        if (request.url.path == '/Win64.$betaVersion.zip') {
          return http.Response.bytes(zip, 200);
        }
        throw StateError('Unexpected download path');
      });
      final first = NativeDevelopmentLauncher(
        storage,
        preferences,
        client: client,
        cookieProvider: () async => 'P_INFO=synthetic',
      );
      await first.refresh();
      expect(first.selectedVersion, stableVersion);
      await first.installVersion(betaVersion);
      expect(first.error, isNull);
      expect(downloads, [
        '/Win64.$betaVersion/patch.json',
        '/Win64.$betaVersion.zip',
      ]);
      expect(
        first.games.map((game) => game.version),
        containsAll([stableVersion, betaVersion]),
      );
      expect(first.selectedVersion, stableVersion);
      expect(
        await File(p.join(stable.path, 'Minecraft.Windows.exe')).readAsString(),
        'stable',
      );
      expect(first.games.first.channels, [GameChannel.beta]);
      expect(first.games.first.architecture, GameArchitecture.x64);
      final count = downloads.length;
      await first.installVersion('9.9.0.0');
      expect(first.error, contains('不在官方清单'));
      expect(downloads.length, count);
      expect(first.selectedVersion, stableVersion);
      preferences.fail = true;
      await first.chooseVersion(betaVersion);
      expect(first.error, contains('无法保存'));
      expect(first.selectedVersion, stableVersion);
      preferences.fail = false;
      await first.chooseVersion(betaVersion);
      expect(first.error, isNull);
      first.dispose();
      final second = NativeDevelopmentLauncher(storage, preferences);
      await second.refresh();
      expect(second.selectedVersion, betaVersion);
      expect(second.games.length, 2);
      second.dispose();
    },
  );

  test(
    'existing Flutter login exchanges token without SDK and isolates cookies',
    () async {
      final api = McsApi(
        client: MockClient((request) async {
          if (request.url.host == 'mc-launcher.webapp.163.com') {
            expect(request.url.path, '/users/refresh_mcs_user_token');
            expect(request.method, 'POST');
            expect(request.body, '{}');
            expect(request.headers['ACCOUNT-TOKEN'], 'synthetic-web-token');
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
          }
          expect(request.headers.containsKey('Cookie'), false);
          expect(request.headers.containsKey('ACCOUNT-TOKEN'), false);
          expect(request.headers['user-id'], '1234');
          expect(request.headers['user-token'], 'synthetic-game-token');
          return http.Response(
            jsonEncode({
              'code': 0,
              'entity': {
                'setting_value': jsonEncode({
                  'stable_x64': '3.10.0.123',
                  'entities': {
                    '3.10.0.123': {
                      'url':
                          'https://x19.gdl.netease.com/game/3.10.0.123/patch.json',
                      'md5': 'a' * 32,
                    },
                  },
                }),
              },
            }),
            200,
          );
        }),
      )..web = Uri.parse('https://x19mclexpr.nie.netease.com');
      await api.authenticateDeveloper('oversea_authcode=synthetic-web-token');
      expect((await api.latest()).version, '3.10.0.123');
      api.close();
      final rejected = McsApi(
        client: MockClient(
          (_) async => http.Response(
            '{"status":"error","data":{"user_id":1234,"token":"unused","expired_at":0}}',
            200,
          ),
        ),
      );
      await expectLater(
        rejected.authenticateDeveloper('P_INFO=synthetic'),
        throwsA(isA<DevelopmentStorageException>()),
      );
      expect(rejected.session, isNull);
      rejected.close();
    },
  );

  test(
    'mod selection survives launcher recreation and root migration',
    () async {
      await storage.initialize();
      final pack = Directory(p.join(storage.paths.root, 'projects', 'pack'));
      await pack.create(recursive: true);
      await File(p.join(pack.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'header': {
            'name': 'Selected',
            'uuid': '794c9e43-1145-4190-9834-56a9dba88a23',
            'version': [1, 0, 0],
          },
          'modules': [
            {'type': 'data'},
          ],
        }),
      );
      final first = NativeDevelopmentLauncher(storage, preferences);
      await first.importMods(pack.path);
      expect(first.error, isNull);
      final uuid = first.packs.single.uuid;
      first.dispose();
      final second = NativeDevelopmentLauncher(storage, preferences);
      await second.refresh();
      expect(second.selectedPacks, contains(uuid));
      await second.togglePack(uuid, false);
      expect(second.error, isNull);
      second.dispose();
      await storage.migrateTo(p.join(temp.path, 'moved-selected'));
      final third = NativeDevelopmentLauncher(storage, preferences);
      await third.refresh();
      expect(third.selectedPacks, isEmpty);
      expect(
        third.packs.single.directory,
        p.join(storage.paths.root, 'projects', 'pack'),
      );
      third.dispose();
    },
  );

  test(
    'legacy packs group by clean name and source project, with mixed selection',
    () {
      ModPack pack(
        String name,
        String uuid,
        String dir,
        String type, {
        String? root,
      }) => ModPack(
        name: name,
        uuid: uuid,
        directory: dir,
        type: type,
        version: [1, 0, 0],
        projectRoot: root,
      );
      final projects = groupModProjects([
        pack('§l§b盔甲架  ', 'bp', '/mods/armor/BP', 'data'),
        pack('§d盔甲架 ', 'rp', '/mods/armor/RP', 'resources'),
        pack('盔甲架', 'other', '/mods/other/BP', 'data'),
      ]);
      expect(projects.length, 2);
      expect(projects.first.name, '盔甲架');
      expect(projects.first.uuids, ['bp', 'rp']);
      expect(projects.first.selection({}), false);
      expect(projects.first.selection({'bp'}), isNull);
      expect(projects.first.selection({'bp', 'rp'}), true);
      expect(
        groupModProjects([
          pack('Logic', 'logic', '/project/BP', 'data', root: '/project'),
          pack(
            'Textures',
            'textures',
            '/project/RP',
            'resources',
            root: '/project',
          ),
        ]).length,
        1,
      );
    },
  );

  test(
    'project selection and removal persist together through storage migration',
    () async {
      await storage.initialize();
      final root = Directory(p.join(storage.paths.root, 'projects', 'addon'));
      for (final entry in {'BP': 'data', 'RP': 'resources'}.entries) {
        final dir = await Directory(
          p.join(root.path, entry.key),
        ).create(recursive: true);
        await File(p.join(dir.path, 'manifest.json')).writeAsString(
          jsonEncode({
            'header': {
              'name': entry.key == 'BP' ? 'Logic' : 'Textures',
              'uuid': entry.key == 'BP'
                  ? '794c9e43-1145-4190-9834-56a9dba88a23'
                  : '12345678-1234-1234-1234-123456789abc',
              'version': [1, 0, 0],
            },
            'modules': [
              {'type': entry.value},
            ],
          }),
        );
      }
      final first = NativeDevelopmentLauncher(storage, preferences);
      await first.importMods(root.path);
      expect(first.error, isNull);
      expect(first.projects.single.packs.length, 2);
      final uuids = first.projects.single.uuids.toList();
      await first.togglePacks(uuids, false);
      first.dispose();
      await storage.migrateTo(p.join(temp.path, 'moved-project'));
      final second = NativeDevelopmentLauncher(storage, preferences);
      await second.refresh();
      expect(second.projects.single.packs.length, 2);
      expect(
        second.projects.single.packs.first.projectRoot,
        p.join(storage.paths.root, 'projects', 'addon'),
      );
      expect(second.selectedPacks, isEmpty);
      await second.togglePacks(uuids, true);
      second.dispose();
      final third = NativeDevelopmentLauncher(storage, preferences);
      await third.refresh();
      expect(third.selectedPacks, uuids.toSet());
      await third.removePacks(uuids);
      expect(third.error, isNull);
      await third.refresh();
      expect(third.projects, isEmpty);
      expect(third.selectedPacks, isEmpty);
      expect(
        await File(
          p.join(
            storage.paths.root,
            'projects',
            'addon',
            'BP',
            'manifest.json',
          ),
        ).exists(),
        true,
      );
      third.dispose();
    },
  );

  test(
    'failed project registry write rolls back selection and removal',
    () async {
      await storage.initialize();
      final launcher = NativeDevelopmentLauncher(storage, preferences);
      launcher.packs = [
        const ModPack(
          name: 'Project',
          uuid: 'bp',
          version: [1, 0, 0],
          type: 'data',
          directory: '/project/BP',
        ),
        const ModPack(
          name: 'Project',
          uuid: 'rp',
          version: [1, 0, 0],
          type: 'resources',
          directory: '/project/RP',
        ),
      ];
      launcher.selectedPacks.add('bp');
      await Directory(p.join(storage.paths.root, 'projects.json')).create();
      await launcher.togglePacks(['bp', 'rp'], true);
      expect(launcher.error, isNotNull);
      expect(launcher.selectedPacks, {'bp'});
      await launcher.removePacks(['bp', 'rp']);
      expect(launcher.error, isNotNull);
      expect(launcher.packs.length, 2);
      expect(launcher.selectedPacks, {'bp'});
      launcher.dispose();
    },
  );

  test('encrypted service response must correlate with the request', () async {
    final api = McsApi(
      client: MockClient((r) async {
        final outgoing = decryptMcsEnvelope(r.bodyBytes);
        final key = Uint8List.fromList([
          ...outgoing.key.sublist(8),
          ...utf8.encode('response'),
        ]);
        return http.Response.bytes(
          encryptMcsEnvelope('{"code":0,"entity":{"ok":true}}', key: key).bytes,
          200,
        );
      }),
    )..web = Uri.parse('https://test.nie.netease.com');
    expect(await api.request('/test', {}, encrypted: true), {'ok': true});
    api.close();
    final invalid = McsApi(
      client: MockClient(
        (_) async => http.Response.bytes(
          encryptMcsEnvelope(
            '{"code":0,"entity":{}}',
            key: Uint8List(16),
          ).bytes,
          200,
        ),
      ),
    )..web = Uri.parse('https://test.nie.netease.com');
    await expectLater(
      invalid.request('/test', {}, encrypted: true),
      throwsA(isA<DevelopmentStorageException>()),
    );
    invalid.close();
  });
  test(
    'inspect is read only and initialization preserves app configuration',
    () async {
      expect((await storage.inspect()).initialized, false);
      expect(await Directory(storage.paths.root).exists(), false);
      preferences.values['account'] = 'unchanged';
      await storage.initialize();
      expect((await storage.inspect()).initialized, true);
      expect(preferences.getString('account'), 'unchanged');
      await expectLater(
        storage.initialize(root: temp.path),
        throwsA(isA<DevelopmentStorageException>()),
      );
    },
  );
  test(
    'migration preserves executable modes, links, source, and config',
    () async {
      await storage.initialize();
      final source = storage.paths.root;
      final exe = File(p.join(source, 'runtimes', 'run'));
      await exe.writeAsString('executable');
      await Process.run('/bin/chmod', ['700', exe.path]);
      await Link(p.join(source, 'runtimes', 'internal')).create(exe.path);
      await Link(p.join(source, 'prefixes', 'z:')).create('/');
      final target = p.join(temp.path, 'moved');
      await storage.migrateTo(target);
      expect(storage.paths.root, target);
      expect(await exe.readAsString(), 'executable');
      expect(
        (await File(p.join(target, 'runtimes', 'run')).stat()).mode & 0x1ff,
        0x1c0,
      );
      expect(
        await Link(p.join(target, 'runtimes', 'internal')).target(),
        p.join(target, 'runtimes', 'run'),
      );
      expect(await Link(p.join(target, 'prefixes', 'z:')).target(), '/');
      expect((await storage.inspect()).initialized, true);
    },
  );
  test(
    'failed preference commit retains the original and verified destination',
    () async {
      await storage.initialize();
      final original = storage.paths.root;
      preferences.fail = true;
      final target = p.join(temp.path, 'recoverable');
      await expectLater(
        storage.migrateTo(target),
        throwsA(isA<DevelopmentStorageException>()),
      );
      expect(storage.paths.root, original);
      expect(
        await File(
          p.join(target, NativeDevelopmentStorage.markerName),
        ).exists(),
        true,
      );
      expect(
        await File(
          p.join(original, NativeDevelopmentStorage.markerName),
        ).exists(),
        true,
      );
    },
  );
  test(
    'nested migration, nonempty targets, and redirected managed folders are rejected',
    () async {
      await storage.initialize();
      await expectLater(
        storage.migrateTo(p.join(storage.paths.root, 'inner')),
        throwsA(isA<DevelopmentStorageException>()),
      );
      final target = Directory(p.join(temp.path, 'other'));
      await target.create();
      await File(p.join(target.path, 'keep')).writeAsString('keep');
      await expectLater(
        storage.migrateTo(target.path),
        throwsA(isA<DevelopmentStorageException>()),
      );
      await Directory(storage.paths.games).delete();
      await Link(storage.paths.games).create(target.path);
      expect((await storage.inspect()).initialized, false);
      expect(await File(p.join(target.path, 'keep')).readAsString(), 'keep');
    },
  );
  test(
    'downloads resume, reset on full response, verify hashes, and retain cancellation',
    () async {
      final destination = File(p.join(temp.path, 'download'));
      final bytes = utf8.encode('complete contents');
      await File(
        '${destination.path}.part',
      ).writeAsBytes(bytes.take(4).toList());
      final client = MockClient((r) async {
        expect(r.headers['Range'], 'bytes=4-');
        return http.Response.bytes(
          bytes.sublist(4),
          206,
          headers: {
            'content-range': 'bytes 4-${bytes.length - 1}/${bytes.length}',
          },
        );
      });
      await downloadManaged(
        client,
        Uri.parse('https://example.com/a'),
        destination,
        expectedSha256: sha256.convert(bytes).toString(),
      );
      expect(await destination.readAsBytes(), bytes);
      client.close();
      await destination.delete();
      await File('${destination.path}.part').writeAsString('bad');
      final full = MockClient((_) async => http.Response.bytes(bytes, 200));
      await downloadManaged(
        full,
        Uri.parse('https://example.com/a'),
        destination,
        expectedSha256: sha256.convert(bytes).toString(),
      );
      expect(await destination.readAsBytes(), bytes);
      final invalid = MockClient((_) async => http.Response('bad', 200));
      await expectLater(
        downloadManaged(
          invalid,
          Uri.parse('https://example.com/a'),
          File(p.join(temp.path, 'bad')),
          expectedMd5: '0' * 32,
        ),
        throwsA(isA<DevelopmentStorageException>()),
      );
      final control = DownloadControl()..cancelled = true;
      await expectLater(
        downloadManaged(
          full,
          Uri.parse('https://example.com/a'),
          destination,
          control: control,
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      full.close();
      invalid.close();
    },
  );
  test(
    'archive preflight rejects traversal and case duplicates before writing',
    () async {
      for (final names in [
        ['ok', '../escape'],
        ['same', 'SAME'],
      ]) {
        final archive = Archive();
        for (final name in names) {
          archive.addFile(ArchiveFile(name, 1, [1]));
        }
        final target = p.join(temp.path, 'zip');
        await expectLater(
          extractZipSafe(archive, target),
          throwsA(isA<DevelopmentStorageException>()),
        );
        expect(await Directory(target).exists(), false);
      }
    },
  );
  test(
    'game verification rejects ancestor links and removes unlisted payload',
    () async {
      final root = Directory(p.join(temp.path, 'game'));
      await root.create();
      final exe = File(p.join(root.path, 'Minecraft.Windows.exe'));
      await exe.writeAsString('game');
      await File(p.join(root.path, 'unverified.dll')).writeAsString('payload');
      final hashes = parseGamePatch(
        jsonEncode({
          'md5': {
            'Minecraft.Windows.exe': md5
                .convert(utf8.encode('game'))
                .toString(),
          },
        }),
      );
      await verifyGameFiles(root.path, hashes);
      expect(await File(p.join(root.path, 'unverified.dll')).exists(), false);
      await Link(p.join(root.path, 'linked')).create(temp.path);
      await expectLater(
        verifyGameFiles(root.path, hashes),
        throwsA(isA<DevelopmentStorageException>()),
      );
    },
  );
  test(
    'mod discovery supports addons and rejects malformed declarations',
    () async {
      final pack = Directory(p.join(temp.path, 'addon', 'behavior'));
      await pack.create(recursive: true);
      final manifest = File(p.join(pack.path, 'manifest.json'));
      await manifest.writeAsString(
        jsonEncode({
          'header': {
            'name': 'Test',
            'uuid': '12345678-1234-1234-1234-123456789abc',
            'version': [1, 0, 0],
          },
          'modules': [
            {'type': 'data'},
          ],
        }),
      );
      final found = await discoverModPacks(p.dirname(pack.path));
      expect(found.single.name, 'Test');
      expect(found.single.type, 'data');
      await manifest.writeAsString('{"header":{},"modules":[1]}');
      await expectLater(
        discoverModPacks(pack.path),
        throwsA(isA<DevelopmentStorageException>()),
      );
    },
  );
}
