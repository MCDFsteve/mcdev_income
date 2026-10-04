import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/test_world_io.dart';

void main() {
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('mcdev-world-'),
  );
  tearDown(() async => temp.delete(recursive: true));
  TestWorldStore store() => TestWorldStore(temp.path);
  Future<File> saved(String id, String marker) async {
    final file = File(p.join(temp.path, id, 'level.dat'));
    await file.parent.create(recursive: true);
    return file.writeAsString(marker);
  }

  test(
    'existing installations continue their original world without changing it',
    () async {
      final original = await saved('mcdev_test', 'original saved world');
      final world = await store().prepare(fresh: false, seed: 'ignored');
      expect(world.levelId, 'mcdev_test');
      expect(world.seed, isEmpty);
      expect(await original.readAsString(), 'original saved world');
    },
  );

  test(
    'each fresh launch gets a distinct world; resume selects the latest saved world',
    () async {
      final original = await saved('mcdev_test', 'original saved world');
      final first = await store().prepare(
        fresh: true,
        seed: '  -9223372036854775808  ',
      );
      expect(first.seed, '-9223372036854775808');
      expect(first.levelId, isNot('mcdev_test'));
      final firstFile = await saved(
        first.levelId,
        'first world and player inventory',
      );
      // Recreate the store to exercise reopening the launcher / moving its root.
      expect((await store().prepare(fresh: false)).levelId, first.levelId);
      final second = await store().prepare(fresh: true, seed: first.seed);
      expect(second.levelId, isNot(first.levelId));
      await saved(second.levelId, 'second saved world');
      expect((await store().prepare(fresh: false)).levelId, second.levelId);
      expect((await store().prepare(fresh: false)).seed, isEmpty);
      expect(
        await firstFile.readAsString(),
        'first world and player inventory',
      );
      expect(await original.readAsString(), 'original saved world');
    },
  );

  test(
    'failed startup keeps the last saved world; empty seed stays random',
    () async {
      await saved('mcdev_test', 'original saved world');
      final first = await store().prepare(fresh: true);
      expect(first.seed, isEmpty);
      final retry = await store().prepare(fresh: true, seed: '文本种子');
      expect(retry.levelId, isNot(first.levelId));
      expect(retry.seed, '文本种子');
      // A directory alone is not evidence that the game created its world.
      await Directory(p.join(temp.path, retry.levelId)).create();
      expect((await store().prepare(fresh: false)).levelId, 'mcdev_test');
    },
  );

  test(
    'invalid persisted paths cannot select a world outside the world directory',
    () async {
      final state = File(p.join(temp.path, '.mcdev-test-world.json'));
      for (final value in ['../other', '/tmp/other', 'mcdev_test/../other']) {
        await state.writeAsString(jsonEncode({'version': 1, 'active': value}));
        await expectLater(store().prepare(fresh: false), throwsException);
        expect(jsonDecode(await state.readAsString())['active'], value);
      }
    },
  );
}
