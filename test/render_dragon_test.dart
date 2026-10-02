import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/render_dragon.dart';
import 'package:mcdev_income/development/render_dragon_io.dart';
import 'development_test.dart' show MemoryPreferences;

class DiskAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('leaving RenderDragon restores GL settings without losing game changes', () {
    const original =
        '# settings\r\ngraphics_mode:0\r\ngfx_msaa:4\r\ngfx_viewdistance:96\r\n';
    const current =
        '# settings\r\nnew_setting:yes\r\ngraphics_mode:2\r\ngraphics_mode:2\r\ngfx_msaa:1\r\ngfx_viewdistance:112\r\n';
    final restored = restoreRenderDragonOptions(current, original);
    expect(restored, contains('graphics_mode:0\r\n'));
    expect(restored, contains('gfx_msaa:4\r\n'));
    expect(restored, contains('gfx_viewdistance:112\r\n'));
    expect(restored, contains('new_setting:yes\r\n'));
    expect('graphics_mode:'.allMatches(restored).length, 1);
    expect(
      restoreRenderDragonOptions(current, ''),
      isNot(contains('graphics_mode:')),
    );
    expect(
      restoreRenderDragonOptions(current, ''),
      isNot(contains('gfx_msaa:')),
    );
  });
  test(
    'renderer settings persist per version and reject unsupported/active changes',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'mcdev-renderer-test-',
      );
      final prefs = MemoryPreferences();
      final storage = NativeDevelopmentStorage(
        preferences: prefs,
        defaultRoot: p.join(temp.path, 'data'),
        lockPath: p.join(temp.path, 'lock'),
      );
      await storage.initialize();
      final launcher = NativeDevelopmentLauncher(storage, prefs);
      launcher.games = [
        const LocalGame(renderDragonPatchVersion, '/test/dragon'),
        const LocalGame('3.8.0.313229', '/test/gl'),
      ];
      try {
        await launcher.chooseVersion(renderDragonPatchVersion);
        await launcher.chooseRenderer(GameRenderer.renderDragon);
        await launcher.chooseVibrantVisuals(true);
        expect(launcher.vibrantVisualsSupported, isTrue);
        launcher.running = true;
        await expectLater(
          launcher.chooseVibrantVisuals(false),
          throwsA(isA<DevelopmentStorageException>()),
        );
        expect(launcher.vibrantVisuals, isTrue);
        launcher.running = false;
        await launcher.chooseVersion('3.8.0.313229');
        expect(launcher.effectiveRenderer, GameRenderer.openGL);
        expect(launcher.vibrantVisualsSupported, isFalse);
        expect(launcher.vibrantVisuals, isFalse);
        await expectLater(
          launcher.chooseVibrantVisuals(true),
          throwsA(isA<DevelopmentStorageException>()),
        );
        await launcher.chooseVersion(renderDragonPatchVersion);
        final reopened = NativeDevelopmentLauncher(storage, prefs);
        expect(reopened.renderer, GameRenderer.renderDragon);
        expect(reopened.vibrantVisuals, isTrue);
        reopened.dispose();
      } finally {
        launcher.dispose();
        await temp.delete(recursive: true);
      }
    },
  );
  test(
    'changed game and Metal files cannot reach injection or replace prefix DLL',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'mcdev-renderer-guard-',
      );
      try {
        final game = await File(
          p.join(temp.path, 'game.exe'),
        ).writeAsString('changed');
        await expectLater(
          validateRenderDragonGame(renderDragonPatchVersion, game),
          throwsA(isA<DevelopmentStorageException>()),
        );
        await expectLater(
          validateRenderDragonGame('3.8.0.313229', game),
          throwsA(isA<DevelopmentStorageException>()),
        );
        final source = File(
          p.join(temp.path, 'runtime/lib/wine/x86_64-windows/winemetal.dll'),
        );
        await source.parent.create(recursive: true);
        await source.writeAsString('corrupt');
        final target = File(
          p.join(temp.path, 'prefix/drive_c/windows/system32/winemetal.dll'),
        );
        await target.parent.create(recursive: true);
        await target.writeAsString('keep');
        await expectLater(
          prepareWineMetalPrefix(
            p.join(temp.path, 'runtime'),
            p.join(temp.path, 'prefix'),
          ),
          throwsA(isA<DevelopmentStorageException>()),
        );
        expect(await target.readAsString(), 'keep');
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  test(
    'shipped renderer patch hashes match and a modified cached DLL is repaired',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'mcdev-renderer-assets-',
      );
      try {
        final directory = await prepareRendererPatch(
          temp.path,
          bundle: DiskAssets(),
        );
        final dll = File(p.join(directory.path, 'renderer-patch.dll'));
        await dll.writeAsString('modified');
        await prepareRendererPatch(temp.path, bundle: DiskAssets());
        expect(
          await dll.readAsBytes(),
          await File('assets/development/renderer-patch.dll').readAsBytes(),
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
}
