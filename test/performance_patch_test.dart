import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/game_graphics.dart';
import 'package:mcdev_income/development/performance_patch.dart';
import 'package:mcdev_income/development/performance_patch_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'development_test.dart' show MemoryPreferences;

class LocalPatchBundle extends CachingAssetBundle {
  LocalPatchBundle({this.corrupt = false});
  final bool corrupt;
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    if (corrupt) bytes[0] ^= 1;
    return ByteData.sublistView(bytes);
  }
}

class RejectPatchPreference extends MemoryPreferences {
  @override
  Future<bool> setInt(String key, int value) async => false;
  @override
  Future<bool> setString(String key, String value) async => false;
}

void main() {
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('mcdev-perf-'),
  );
  tearDown(() async => temp.delete(recursive: true));

  test('only the benchmarked game version is eligible', () {
    expect(supportsPerformancePatch('3.8.0.313229'), isTrue);
    expect(supportsPerformancePatch('3.10.0.420447'), isFalse);
    expect(supportsPerformancePatch('3.8.0.291644'), isFalse);
    expect(supportsPerformancePatch(null), isFalse);
  });

  test('small packaged helpers are exact x64 PE files', () async {
    for (final entry in performancePatchAssets.entries) {
      final bytes = await File('assets/development/${entry.key}').readAsBytes();
      expect(sha256.convert(bytes).toString(), entry.value);
      expect(bytes.length, lessThan(65536));
      final data = ByteData.sublistView(bytes);
      expect(data.getUint16(0, Endian.little), 0x5a4d);
      final header = data.getUint32(0x3c, Endian.little);
      expect(data.getUint32(header, Endian.little), 0x4550);
      expect(data.getUint16(header + 4, Endian.little), 0x8664);
    }
  });

  test('corrupted game is refused without modifying it', () async {
    final game = File(p.join(temp.path, 'Minecraft.Windows.exe'));
    await game.writeAsString('different game binary');
    await expectLater(
      validatePerformanceGame(performancePatchVersion, game),
      throwsException,
    );
    expect(await game.readAsString(), 'different game binary');
    await expectLater(
      validatePerformanceGame('3.10.0.420447', game),
      throwsException,
    );
  });

  test('helper cache is repaired from verified app assets', () async {
    final directory = await preparePerformancePatch(
      temp.path,
      bundle: LocalPatchBundle(),
    );
    final dll = File(p.join(directory.path, 'graphics-patch.dll'));
    await dll.writeAsString('corrupted cache');
    await preparePerformancePatch(temp.path, bundle: LocalPatchBundle());
    expect(
      sha256.convert(await dll.readAsBytes()).toString(),
      performancePatchAssets['graphics-patch.dll'],
    );
  });

  test('corrupted bundled helper is refused before injection', () async {
    await expectLater(
      preparePerformancePatch(
        temp.path,
        bundle: LocalPatchBundle(corrupt: true),
      ),
      throwsException,
    );
    expect(
      await File(
        p.join(temp.path, 'graphics-patch-v1', 'graphics-patch.dll'),
      ).exists(),
      isFalse,
    );
  });

  NativeDevelopmentLauncher launcher(MemoryPreferences preferences) =>
      NativeDevelopmentLauncher(
        NativeDevelopmentStorage(
          preferences: preferences,
          defaultRoot: temp.path,
          lockPath: p.join(temp.path, 'lock'),
        ),
        preferences,
      );

  test('optimization defaults on and explicit rollback persists', () async {
    final preferences = MemoryPreferences();
    final first = launcher(preferences);
    expect(first.performanceOptimization, isTrue);
    await first.choosePerformanceOptimization(false);
    first.dispose();
    final second = launcher(preferences);
    expect(second.performanceOptimization, isFalse);
    await second.choosePerformanceOptimization(true);
    second.selectedVersion = '3.10.0.420447';
    expect(second.performanceOptimizationSupported, isFalse);
    second.dispose();
  });

  test('frame limit persists independently of optimization', () async {
    final preferences = MemoryPreferences();
    final first = launcher(preferences);
    expect(first.limit60Fps, isTrue);
    await first.chooseFrameLimit(false);
    expect(first.performanceOptimization, isTrue);
    first.dispose();
    final second = launcher(preferences);
    expect(second.limit60Fps, isFalse);
    await second.choosePerformanceOptimization(false);
    await second.chooseFrameLimit(true);
    expect(second.performanceOptimization, isFalse);
    second.dispose();
  });

  test(
    'renderer is saved per version and unsupported versions stay on OpenGL',
    () async {
      final preferences = MemoryPreferences();
      await preferences.setString(
        'development_game_version_v1',
        '3.10.0.420447',
      );
      final first = launcher(preferences);
      await first.chooseRenderer(GameRenderer.renderDragon);
      first.dispose();
      final second = launcher(preferences);
      expect(second.effectiveRenderer, GameRenderer.renderDragon);
      second.dispose();
      await preferences.setString(
        'development_game_version_v1',
        '3.9.0.401155',
      );
      final other = launcher(preferences);
      expect(other.renderer, GameRenderer.openGL);
      await other.chooseRenderer(GameRenderer.openGL);
      other.dispose();
      await preferences.setString(
        'development_game_version_v1',
        '3.8.0.313229',
      );
      final older = launcher(preferences);
      await expectLater(
        older.chooseRenderer(GameRenderer.renderDragon),
        throwsException,
      );
      older.renderer = GameRenderer.renderDragon;
      expect(older.effectiveRenderer, GameRenderer.openGL);
      expect(older.performanceOptimizationSupported, isTrue);
      older.dispose();
    },
  );

  test(
    'renderer refuses active launches and unsuccessful preference writes',
    () async {
      final active = launcher(MemoryPreferences())
        ..selectedVersion = '3.10.0.420447'
        ..running = true;
      await expectLater(
        active.chooseRenderer(GameRenderer.renderDragon),
        throwsException,
      );
      expect(active.renderer, GameRenderer.openGL);
      active.running = false;
      active.dispose();
      final failure = launcher(RejectPatchPreference())
        ..selectedVersion = '3.10.0.420447';
      await expectLater(
        failure.chooseRenderer(GameRenderer.renderDragon),
        throwsException,
      );
      expect(failure.renderer, GameRenderer.openGL);
      failure.dispose();
    },
  );

  test(
    'frame limit refuses active launches and unsuccessful preference writes',
    () async {
      final active = launcher(MemoryPreferences())..running = true;
      await expectLater(active.chooseFrameLimit(false), throwsException);
      expect(active.limit60Fps, isTrue);
      active.running = false;
      active.dispose();
      final failure = launcher(RejectPatchPreference());
      await expectLater(failure.chooseFrameLimit(false), throwsException);
      expect(failure.limit60Fps, isTrue);
      failure.dispose();
    },
  );

  test(
    'active game and failed preference writes do not change the option',
    () async {
      final active = launcher(MemoryPreferences())..running = true;
      await expectLater(
        active.choosePerformanceOptimization(false),
        throwsException,
      );
      expect(active.performanceOptimization, isTrue);
      active.running = false;
      active.dispose();
      final failure = launcher(RejectPatchPreference());
      await expectLater(
        failure.choosePerformanceOptimization(false),
        throwsException,
      );
      expect(failure.performanceOptimization, isTrue);
      failure.dispose();
    },
  );

  test('game exit cancels a helper still waiting for initialization', () async {
    final helper = File(p.join(temp.path, 'waiting.sh'));
    await helper.writeAsString('while true; do :; done\n');
    final exited = Completer<void>();
    final loading = injectPerformancePatch(
      wine: '/bin/sh',
      environment: Platform.environment,
      helper: helper.path,
      dll: 'unused.dll',
      executable: 'unused.exe',
      cancelWhen: exited.future,
    );
    exited.complete();
    expect(await loading, isFalse);
  });

  test('failed injection helper leaves the game directory intact', () async {
    final helper = File(p.join(temp.path, 'failed.sh'));
    await helper.writeAsString('exit 9\n');
    final marker = File(p.join(temp.path, 'save.marker'));
    await marker.writeAsString('existing save');
    expect(
      await injectPerformancePatch(
        wine: '/bin/sh',
        environment: Platform.environment,
        helper: helper.path,
        dll: 'unused.dll',
        executable: 'unused.exe',
      ),
      isFalse,
    );
    expect(await marker.readAsString(), 'existing save');
  });

  test('successful helper does not wait for inherited pipe handles', () async {
    final helper = File(p.join(temp.path, 'inherited-pipes.sh'));
    final worker = File(p.join(temp.path, 'worker.pid'));
    await helper.writeAsString('sleep 30 &\necho "\$!" > "\$2"\nexit 0\n');
    try {
      expect(
        await injectPerformancePatch(
          wine: '/bin/sh',
          environment: Platform.environment,
          helper: helper.path,
          dll: 'unused.dll',
          executable: worker.path,
        ),
        isTrue,
      );
    } finally {
      if (await worker.exists()) {
        Process.killPid(int.parse((await worker.readAsString()).trim()));
      }
    }
  });

  test(
    'timed-out helper returns without terminating unrelated processes',
    () async {
      final helper = File(p.join(temp.path, 'timeout.sh'));
      await helper.writeAsString('while true; do :; done\n');
      expect(
        await injectPerformancePatch(
          wine: '/bin/sh',
          environment: Platform.environment,
          helper: helper.path,
          dll: 'unused.dll',
          executable: 'unused.exe',
          timeout: const Duration(milliseconds: 100),
        ),
        isFalse,
      );
    },
  );
}
