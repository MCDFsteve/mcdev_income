import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/input_guard_io.dart';
import 'performance_patch_test.dart' show LocalPatchBundle;

void main() {
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('mcdev-input-'),
  );
  tearDown(() async => temp.delete(recursive: true));

  test(
    'verified input helper repairs damage and survives paths with spaces',
    () async {
      final root = p.join(temp.path, 'Wine runtimes');
      var library = await prepareFullscreenShortcutGuard(
        root,
        bundle: LocalPatchBundle(),
      );
      final modified = await library.lastModified();
      await prepareFullscreenShortcutGuard(
        root,
        bundle: LocalPatchBundle(corrupt: true),
      );
      expect(await library.lastModified(), modified);
      await library.writeAsString('damaged');
      library = await prepareFullscreenShortcutGuard(
        root,
        bundle: LocalPatchBundle(),
      );
      expect(
        sha256.convert(await library.readAsBytes()).toString(),
        fullscreenShortcutGuardHash,
      );
      final moved = await Directory(
        root,
      ).rename(p.join(temp.path, 'Moved runtimes'));
      library = await prepareFullscreenShortcutGuard(
        moved.path,
        bundle: LocalPatchBundle(corrupt: true),
      );
      expect(await library.exists(), isTrue);
      expect(
        sha256.convert(await library.readAsBytes()).toString(),
        fullscreenShortcutGuardHash,
      );
    },
    skip: Platform.isWindows, // DYLD paths are Unix-only.
  );

  test(
    'corrupted bundled input helper is rejected before writing the cache',
    () async {
      await expectLater(
        prepareFullscreenShortcutGuard(
          temp.path,
          bundle: LocalPatchBundle(corrupt: true),
        ),
        throwsException,
      );
      expect(
        await Directory(p.join(temp.path, 'input-guard-v1')).exists(),
        isFalse,
      );
    },
  );

  test('game input environment preserves inherited libraries and spaces', () {
    const library =
        '/Data with spaces/input-guard-v1/fullscreen-shortcut.dylib';
    expect(fullscreenShortcutEnvironment(library, inherited: {}), {
      'DYLD_INSERT_LIBRARIES': library,
      'MCDEV_FULLSCREEN_SHORTCUT': '0',
    });
    final environment = fullscreenShortcutEnvironment(
      library,
      inherited: {
        'DYLD_INSERT_LIBRARIES': '/other/helper.dylib:/second/helper.dylib',
      },
    );
    expect(
      environment['DYLD_INSERT_LIBRARIES'],
      '/other/helper.dylib:/second/helper.dylib:$library',
    );
  });
}
