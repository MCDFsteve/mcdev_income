import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/storage/desktop_secret_store_io.dart';

void main() {
  test('desktopSecretScope normalizes paths and isolates directories', () {
    final a = desktopSecretScope('/tmp/mcdev-scope-a/./sub/..');
    final b = desktopSecretScope('/tmp/mcdev-scope-a');
    final c = desktopSecretScope('/tmp/mcdev-scope-b');
    expect(a, hasLength(16));
    expect(a, b);
    expect(a, isNot(c));
  });

  test(
    'native OS secret store round-trips small, large, updated and deleted values',
    () async {
      final tempA = await Directory.systemTemp.createTemp('mcdev-sec-a-');
      final tempB = await Directory.systemTemp.createTemp('mcdev-sec-b-');
      final key = 'test_session_${DateTime.now().microsecondsSinceEpoch}';
      final storeA = await openNativeDesktopSecretStore(tempA.path);
      final storeB = await openNativeDesktopSecretStore(tempB.path);
      try {
        expect(await storeA.read(key), isNull);

        const smallValue = '{"email":"dev@163.com","cookies":{"S_INFO":"abc"}}';
        await storeA.write(key, smallValue);
        expect(await storeA.read(key), smallValue);
        // Different directories must be isolated.
        expect(await storeB.read(key), isNull);

        // Large payload (> 2560 bytes) exercises chunking on Windows Credential
        // Manager and full UTF-8 fidelity on macOS Keychain.
        final largeValue =
            '{"email":"dev@163.com","cookies":{"NTES_SESS":"${'x' * 5200}"}}';
        await storeA.write(key, largeValue);
        expect(await storeA.read(key), largeValue);

        // Shrinking back to a small payload must still read cleanly.
        const updatedSmall = '{"email":"dev@163.com","cookies":{"S_INFO":"z"}}';
        await storeA.write(key, updatedSmall);
        expect(await storeA.read(key), updatedSmall);

        await storeA.delete(key);
        expect(await storeA.read(key), isNull);
        // Deleting a non-existent key is idempotent.
        await storeA.delete(key);
      } finally {
        await storeA.delete(key);
        await storeB.delete(key);
        await tempA.delete(recursive: true);
        await tempB.delete(recursive: true);
      }
    },
    skip: !(Platform.isMacOS || Platform.isWindows),
  );
}
