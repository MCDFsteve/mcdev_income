import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/input_guard_io.dart';
import 'package:mcdev_income/development/wine_network_io.dart';
import 'performance_patch_test.dart' show LocalPatchBundle;

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('mcdev-net-'));
  tearDown(() async => temp.delete(recursive: true));

  test('packaged network helper matches the pinned x64 Mach-O image', () async {
    final bytes = await File(
      'assets/development/ipv6-discovery.dylib',
    ).readAsBytes();
    expect(sha256.convert(bytes).toString(), wineNetworkLibraryHash);
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(0, Endian.little), 0xfeedfacf);
    expect(data.getUint32(4, Endian.little), 0x01000007);
  });

  test('verified cache is reusable, repairable and movable', () async {
    final root = p.join(temp.path, 'Wine runtimes');
    var library = await prepareWineNetworkLibrary(
      root,
      bundle: LocalPatchBundle(),
    );
    final modified = await library.lastModified();
    await prepareWineNetworkLibrary(
      root,
      bundle: LocalPatchBundle(corrupt: true),
    );
    expect(await library.lastModified(), modified);
    await library.writeAsString('damaged');
    library = await prepareWineNetworkLibrary(root, bundle: LocalPatchBundle());
    expect(
      sha256.convert(await library.readAsBytes()).toString(),
      wineNetworkLibraryHash,
    );
    final moved = await Directory(
      root,
    ).rename(p.join(temp.path, 'Moved runtimes'));
    library = await prepareWineNetworkLibrary(
      moved.path,
      bundle: LocalPatchBundle(corrupt: true),
    );
    expect(await library.exists(), isTrue);
  });

  test(
    'corrupt assets and ambiguous dyld paths fail before cache writes',
    () async {
      await expectLater(
        prepareWineNetworkLibrary(
          temp.path,
          bundle: LocalPatchBundle(corrupt: true),
        ),
        throwsException,
      );
      expect(
        await Directory(p.join(temp.path, 'network-discovery-v1')).exists(),
        isFalse,
      );
      await expectLater(
        prepareWineNetworkLibrary('${temp.path}:bad'),
        throwsException,
      );
    },
  );

  test('network and input helpers both survive environment composition', () {
    const network = '/Data with spaces/network/ipv6-discovery.dylib';
    const input = '/Data with spaces/input/fullscreen-shortcut.dylib';
    final environment = wineNetworkEnvironment(
      network,
      inherited: {'DYLD_INSERT_LIBRARIES': '/existing/helper.dylib'},
    );
    environment.addAll(
      fullscreenShortcutEnvironment(input, inherited: environment),
    );
    expect(
      environment['DYLD_INSERT_LIBRARIES'],
      '/existing/helper.dylib:$network:$input',
    );
    expect(environment['MCDEV_FULLSCREEN_SHORTCUT'], '0');
    expect(
      wineNetworkEnvironment(network, inherited: {})['DYLD_INSERT_LIBRARIES'],
      network,
    );
  });
}
