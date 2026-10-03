import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/player_skin_io.dart';

void main() {
  late Directory temp;
  late String game;
  late String prefix;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-skin-');
    game = p.join(temp.path, 'Application Support', '游戏', '3.10');
    prefix = p.join(temp.path, 'Application Support', 'Windows 容器');
  });
  tearDown(() => temp.delete(recursive: true));

  Future<File> writeSkin(TestPlayerSkin skin, int red) async {
    final file = File(
      p.join(game, 'data', 'skin_packs', 'vanilla', skin.textureFile),
    );
    await file.parent.create(recursive: true);
    final image = img.Image(width: 64, height: 64, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(red, 80, 120, 255));
    return file.writeAsBytes(img.encodePng(image));
  }

  test(
    'stages the selected PNG through C: with spaces and Unicode in host paths',
    () async {
      final sources = {
        TestPlayerSkin.steve: await writeSkin(TestPlayerSkin.steve, 30),
        TestPlayerSkin.alex: await writeSkin(TestPlayerSkin.alex, 200),
      };
      for (final skin in [
        TestPlayerSkin.alex,
        TestPlayerSkin.steve,
        TestPlayerSkin.alex,
      ]) {
        final config = await prepareTestPlayerSkin(
          skin: skin,
          gameDirectory: game,
          gamePrefix: prefix,
        );
        final windowsPath = config['skin']! as String;
        expect(
          windowsPath,
          p.windows.join(r'C:\MCDevTests\skins', skin.textureFile),
        );
        expect(windowsPath, isNot(contains(' ')));
        final staged = File(
          p.joinAll([
            prefix,
            'drive_c',
            ...p.windows.split(windowsPath).skip(1),
          ]),
        );
        expect(await staged.readAsBytes(), await sources[skin]!.readAsBytes());
        expect(config['slim'], skin == TestPlayerSkin.alex);
        expect(config['skin_iid'], skin == TestPlayerSkin.alex ? '-2' : '-1');
      }
    },
  );

  test('refreshes staged textures from the selected game version', () async {
    await writeSkin(TestPlayerSkin.alex, 30);
    await prepareTestPlayerSkin(
      skin: TestPlayerSkin.alex,
      gameDirectory: game,
      gamePrefix: prefix,
    );
    game = p.join(temp.path, 'Another Version');
    final source = await writeSkin(TestPlayerSkin.alex, 200);
    await prepareTestPlayerSkin(
      skin: TestPlayerSkin.alex,
      gameDirectory: game,
      gamePrefix: prefix,
    );
    final staged = File(
      p.join(prefix, 'drive_c', 'MCDevTests', 'skins', 'alex.png'),
    );
    expect(await staged.readAsBytes(), await source.readAsBytes());
    expect(await staged.parent.list().length, 1);
  });

  test(
    'missing Alex fails instead of silently using Steve or an older texture',
    () async {
      await writeSkin(TestPlayerSkin.steve, 30);
      final stale = File(
        p.join(prefix, 'drive_c', 'MCDevTests', 'skins', 'alex.png'),
      );
      await stale.parent.create(recursive: true);
      await stale.writeAsBytes([1, 2, 3]);
      await expectLater(
        prepareTestPlayerSkin(
          skin: TestPlayerSkin.alex,
          gameDirectory: game,
          gamePrefix: prefix,
        ),
        throwsA(isA<DevelopmentStorageException>()),
      );
      expect(await stale.readAsBytes(), [1, 2, 3]);
    },
  );
}
