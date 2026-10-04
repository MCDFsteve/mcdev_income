import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/lan_patch_io.dart';

class _DiskAssets extends CachingAssetBundle {
  _DiskAssets({this.corrupt = false});
  final bool corrupt;

  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    if (corrupt && key.endsWith(lanInjectorFile)) bytes[0] ^= 1;
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LAN patch rejects other versions and modified game files', () async {
    final temp = await Directory.systemTemp.createTemp('mcdev-lan-guard-');
    addTearDown(() => temp.delete(recursive: true));
    final executable = await File(
      p.join(temp.path, 'game.exe'),
    ).writeAsString('changed');
    expect(supportsLanPatch(lanPatchVersion), isTrue);
    expect(supportsLanPatch('3.10.0.420448'), isFalse);
    expect(supportsLanPatch(null), isFalse);
    for (final version in [lanPatchVersion, '3.8.0.313229']) {
      await expectLater(
        validateLanGame(version, executable),
        throwsA(isA<DevelopmentStorageException>()),
      );
    }
    await expectLater(
      validateLanGame(lanPatchVersion, File(p.join(temp.path, 'missing.exe'))),
      throwsA(isA<DevelopmentStorageException>()),
    );
    expect(await executable.readAsString(), 'changed');
  });

  test(
    'pinned LAN helpers repair a changed cache and can stage concurrently',
    () async {
      final temp = await Directory.systemTemp.createTemp('mcdev-lan-assets-');
      addTearDown(() => temp.delete(recursive: true));
      final dirs = await Future.wait(
        List.generate(
          3,
          (_) => prepareLanPatch(temp.path, bundle: _DiskAssets()),
        ),
      );
      expect(dirs.map((d) => d.path).toSet(), hasLength(1));
      final dll = File(p.join(dirs.first.path, 'lan-patch.dll'));
      await dll.writeAsString('modified');
      await prepareLanPatch(temp.path, bundle: _DiskAssets());
      for (final entry in lanPatchAssets.entries) {
        final file = File(p.join(dirs.first.path, entry.key));
        expect(
          (await sha256.bind(file.openRead()).first).toString(),
          entry.value,
        );
      }
      expect(await dirs.first.list().length, 2);
    },
  );

  test('corrupt bundled helper leaves existing files untouched', () async {
    final temp = await Directory.systemTemp.createTemp('mcdev-lan-corrupt-');
    addTearDown(() => temp.delete(recursive: true));
    final directory = await Directory(
      p.join(temp.path, 'lan-patch-v1'),
    ).create();
    final previous = await File(
      p.join(directory.path, 'lan-patch.dll'),
    ).writeAsString('previous');
    await expectLater(
      prepareLanPatch(temp.path, bundle: _DiskAssets(corrupt: true)),
      throwsA(isA<DevelopmentStorageException>()),
    );
    expect(await previous.readAsString(), 'previous');
    expect(await directory.list().length, 1);
  });
}
