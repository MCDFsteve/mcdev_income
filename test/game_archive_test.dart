import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/download_io.dart';
import 'package:mcdev_income/development/game_archive_io.dart';
import 'package:mcdev_income/development/platform/host_files_io.dart';

void main() {
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('game-archive-'),
  );
  tearDown(
    () => Directory(nativeFileSystemPath(temp.path)).delete(recursive: true),
  );

  test(
    'official build wrapper is removed before extracting and verifying',
    () async {
      final wrapper = 'Win64.${'official_build_' * 6}';
      final files = {
        'Minecraft.Windows.exe': utf8.encode('game'),
        'data/resource_packs/vanilla_netease/models/${'effect_' * 10}/animation.json':
            utf8.encode('animation'),
      };
      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(
          ArchiveFile('$wrapper/${entry.key}', entry.value.length, entry.value),
        );
      }
      archive.addFile(ArchiveFile('$wrapper/extra.dll', 1, [1]));
      final target = p.join(temp.path, 'game');
      await extractGameZipSafe(archive, target);
      await verifyGameFiles(target, {
        for (final entry in files.entries)
          entry.key: md5.convert(entry.value).toString(),
      });
      expect(
        await File(p.join(target, 'Minecraft.Windows.exe')).readAsString(),
        'game',
      );
      expect(await Directory(p.join(target, wrapper)).exists(), false);
      expect(await File(p.join(target, 'extra.dll')).exists(), false);
      expect(
        (await Directory(
          target,
        ).list(recursive: true).where((e) => e is File).toList()),
        hasLength(2),
      );
    },
  );

  test(
    'long Windows trees are fully enumerated for verification',
    () async {
      final root = p.join(
        temp.path,
        List.filled(6, 'long_directory_name').join(p.separator),
      );
      final nested =
          '${List.filled(5, 'resource_directory').join('/')}/asset.json';
      expect(p.join(root, nested).length, greaterThan(260));
      final archive = Archive()
        ..addFile(ArchiveFile('Minecraft.Windows.exe', 1, [1]))
        ..addFile(ArchiveFile(nested, 1, [2]))
        ..addFile(ArchiveFile('$nested.extra', 1, [3]));
      await extractGameZipSafe(archive, root);
      await verifyGameFiles(root, {
        'Minecraft.Windows.exe': md5.convert([1]).toString(),
        nested: md5.convert([2]).toString(),
      });
      expect(
        await File(nativeFileSystemPath(p.join(root, nested))).readAsBytes(),
        [2],
      );
      expect(
        await File(
          nativeFileSystemPath(p.join(root, '$nested.extra')),
        ).exists(),
        false,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'wrapped archives still reject unsafe siblings and ambiguous games',
    () async {
      for (final sibling in ['../escape', 'other/Minecraft.Windows.exe']) {
        final archive = Archive()
          ..addFile(ArchiveFile('game/Minecraft.Windows.exe', 1, [1]))
          ..addFile(ArchiveFile(sibling, 1, [2]));
        final target = p.join(temp.path, 'rejected');
        await expectLater(
          extractGameZipSafe(archive, target),
          throwsA(isA<DevelopmentStorageException>()),
        );
        expect(await Directory(target).exists(), false);
      }
    },
  );

  test(
    'completed archive reuse avoids downloading again; partial and hashed files are checked',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('valid', 200);
      });
      addTearDown(client.close);
      final file = File(p.join(temp.path, 'game.zip'));
      final url = Uri.parse('https://example.com/game.zip');
      await downloadManaged(client, url, file, reuseCompleted: true);
      await downloadManaged(client, url, file, reuseCompleted: true);
      expect(requests, 1);
      await file.writeAsString('changed');
      await downloadManaged(
        client,
        url,
        file,
        reuseCompleted: true,
        expectedMd5: md5.convert(utf8.encode('valid')).toString(),
      );
      expect(requests, 2);
      expect(await file.readAsString(), 'valid');
      await file.delete();
      await File('${file.path}.part').writeAsString('va');
      await downloadManaged(client, url, file, reuseCompleted: true);
      expect(requests, 3);
      expect(await file.readAsString(), 'valid');
    },
  );
}
