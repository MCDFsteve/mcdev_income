import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/wine_patch_io.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-wine-patch-test-');
  });
  tearDown(() async => temp.delete(recursive: true));

  test('missing runtime is not ready', () async {
    expect(await patchedWineReady(temp.path), isFalse);
  });

  test(
    'unsupported original files are rejected without modification',
    () async {
      final mac = File(p.join(temp.path, 'lib/wine/x86_64-unix/winemac.so'));
      final gl = File(
        p.join(temp.path, 'lib/wine/x86_64-windows/opengl32.dll'),
      );
      await mac.parent.create(recursive: true);
      await gl.parent.create(recursive: true);
      await mac.writeAsString('unsupported mac driver');
      await gl.writeAsString('unsupported OpenGL');
      await expectLater(
        patchWine11(temp.path),
        throwsA(isA<DevelopmentStorageException>()),
      );
      expect(await mac.readAsString(), 'unsupported mac driver');
      expect(await gl.readAsString(), 'unsupported OpenGL');
      expect(await patchedWineReady(temp.path), isFalse);
    },
  );

  // Explicitly opt in with the unpacked, original hash-pinned Wine 11.0_1.
  // This test only copies two binaries and never starts Wine or a game.
  final original = Platform.environment['MCDEV_TEST_WINE_ORIGINAL'];
  test(
    'real signing metadata can vary while code and signatures remain verified',
    () async {
      final mac = File(p.join(temp.path, 'lib/wine/x86_64-unix/winemac.so'));
      final gl = File(
        p.join(temp.path, 'lib/wine/x86_64-windows/opengl32.dll'),
      );
      await mac.parent.create(recursive: true);
      await gl.parent.create(recursive: true);
      await File(
        p.join(original!, 'lib/wine/x86_64-unix/winemac.so'),
      ).copy(mac.path);
      await File(
        p.join(original, 'lib/wine/x86_64-windows/opengl32.dll'),
      ).copy(gl.path);
      final loader = File(p.join(temp.path, 'bin/wine'));
      await loader.parent.create(recursive: true);
      await loader.writeAsString('unused test loader');
      expect(
        sha256.convert(await mac.readAsBytes()).toString(),
        wineMacOriginal,
      );

      await patchWine11(temp.path);
      expect(await patchedWineReady(temp.path), isTrue);
      final firstHash = sha256.convert(await mac.readAsBytes()).toString();
      final signed = await Process.run('/usr/bin/codesign', [
        '--force',
        '--sign',
        '-',
        '--identifier',
        'mcdev.regression.different-signing-identifier',
        mac.path,
      ]);
      expect(signed.exitCode, 0, reason: signed.stderr.toString());
      expect(
        sha256.convert(await mac.readAsBytes()).toString(),
        isNot(firstHash),
      );
      final reSignedHash = sha256.convert(await mac.readAsBytes()).toString();
      expect(await patchedWineReady(temp.path), isTrue);
      // Checking readiness must not strip or otherwise modify the runtime.
      expect(sha256.convert(await mac.readAsBytes()).toString(), reSignedHash);

      final bytes = await mac.readAsBytes();
      bytes[0x3197d] ^= 1;
      await mac.writeAsBytes(bytes);
      expect(await patchedWineReady(temp.path), isFalse);
      final resignedTamper = await Process.run('/usr/bin/codesign', [
        '--force',
        '--sign',
        '-',
        mac.path,
      ]);
      expect(resignedTamper.exitCode, 0);
      // A valid signature alone must not make altered executable code trusted.
      expect(await patchedWineReady(temp.path), isFalse);
      bytes[0x3197d] ^= 1;
      await mac.writeAsBytes(bytes);
      final restored = await Process.run('/usr/bin/codesign', [
        '--force',
        '--sign',
        '-',
        mac.path,
      ]);
      expect(restored.exitCode, 0);
      expect(await patchedWineReady(temp.path), isTrue);

      final removed = await Process.run('/usr/bin/codesign', [
        '--remove-signature',
        mac.path,
      ]);
      expect(removed.exitCode, 0);
      expect(await patchedWineReady(temp.path), isFalse);
    },
    skip: !Platform.isMacOS || original == null,
  );
}
