import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/wine_game_app_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unsupported Wine loader cannot create a game application', () async {
    final temp = await Directory.systemTemp.createTemp('mcdev-game-app-guard-');
    try {
      final source = File(p.join(temp.path, 'lib/wine/x86_64-unix/wine'));
      await source.parent.create(recursive: true);
      await source.writeAsString('unsupported loader');
      await File(
        p.join(source.parent.path, 'ntdll.so'),
      ).writeAsString('fixture');
      await expectLater(
        prepareWineGameApplication(temp.path, metal: false),
        throwsA(isA<DevelopmentStorageException>()),
      );
      expect(await Directory(p.join(temp.path, '我的世界测试.app')).exists(), false);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  // Opt in to Apple's real signing tools with the already downloaded Wine 11
  // loader. No game, login, prefix, or user settings are accessed.
  final runtime = Platform.environment['MCDEV_TEST_WINE_RUNTIME'];
  test(
    'signed application survives migration, repairs tampering and protects collisions',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'mcdev-game-app-signing-',
      );
      try {
        var root = p.join(temp.path, 'Wine runtime with spaces');
        final lib = p.join(root, 'lib/wine/x86_64-unix');
        await Directory(lib).create(recursive: true);
        for (final name in ['wine', 'ntdll.so']) {
          await File(
            p.join(runtime!, 'lib/wine/x86_64-unix', name),
          ).copy(p.join(lib, name));
        }
        var app = await prepareWineGameApplication(root, metal: true);
        final icon = File(
          p.join(app.path, 'Contents/Resources/MinecraftBedrock.icns'),
        );
        expect(
          sha256.convert(await icon.readAsBytes()).toString(),
          wineGameIconHash,
        );
        expect(
          await File(p.join(app.path, 'Contents/Info.plist')).readAsString(),
          contains(
            '<key>CFBundleIconFile</key><string>MinecraftBedrock.icns</string>',
          ),
        );
        final ntdll = Link(p.join(app.path, 'Contents/MacOS/ntdll.so'));
        expect(
          await ntdll.resolveSymbolicLinks(),
          await File(p.join(lib, 'ntdll.so')).resolveSymbolicLinks(),
        );
        final modified = await File(app.loader).lastModified();
        await prepareWineGameApplication(root, metal: true);
        expect(await File(app.loader).lastModified(), modified);
        await icon.writeAsString('damaged icon');
        await prepareWineGameApplication(root, metal: true);
        expect(
          sha256.convert(await icon.readAsBytes()).toString(),
          wineGameIconHash,
        );
        final repairedModified = await File(app.loader).lastModified();
        root = (await Directory(
          root,
        ).rename(p.join(temp.path, 'Migrated Wine'))).path;
        app = await prepareWineGameApplication(root, metal: true);
        expect(
          await Link(
            p.join(app.path, 'Contents/MacOS/ntdll.so'),
          ).resolveSymbolicLinks(),
          await File(
            p.join(root, 'lib/wine/x86_64-unix/ntdll.so'),
          ).resolveSymbolicLinks(),
        );
        expect(await File(app.loader).lastModified(), repairedModified);
        await File(app.loader).writeAsString('damaged cached application');
        app = await prepareWineGameApplication(root, metal: true);
        expect(await File(app.loader).length(), greaterThan(1000));
        final signature = await Process.run('/usr/bin/codesign', [
          '--verify',
          '--strict=sideband',
          app.path,
        ]);
        expect(signature.exitCode, 0, reason: signature.stderr.toString());
        app = await prepareWineGameApplication(root, metal: false);
        expect(
          await File(p.join(app.path, 'Contents/Info.plist')).readAsString(),
          contains('winegame.opengl'),
        );
        expect(app.environment['WINELOADER'], app.loader);
        expect(app.environment['WINELOADERNOEXEC'], '1');
        await Directory(app.path).delete(recursive: true);
        await File(app.path).writeAsString('user file');
        await expectLater(
          prepareWineGameApplication(root, metal: false),
          throwsA(isA<DevelopmentStorageException>()),
        );
        expect(await File(app.path).readAsString(), 'user file');
        expect(
          await Directory(root)
              .list()
              .where(
                (entry) =>
                    p.basename(entry.path).startsWith('.mcdev-game-app-'),
              )
              .toList(),
          isEmpty,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
    skip: !Platform.isMacOS || runtime == null,
  );
}
