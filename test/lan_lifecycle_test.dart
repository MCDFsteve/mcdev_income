import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_lock.dart';
import 'package:path/path.dart' as p;

import 'development_test.dart' show MemoryPreferences;

class _DelayedStorage extends NativeDevelopmentStorage {
  _DelayedStorage({
    required super.preferences,
    required super.defaultRoot,
    required super.lockPath,
  });

  Completer<void>? inspectGate;

  @override
  Future<DevelopmentStorageStatus> inspect() async {
    await inspectGate?.future;
    return super.inspect();
  }
}

void main() {
  late Directory temporary;
  late MemoryPreferences preferences;
  late _DelayedStorage storage;
  late NativeDevelopmentLauncher launcher;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mcdev-lan-lifetime-');
    temporary = Directory(await temporary.resolveSymbolicLinks());
    preferences = MemoryPreferences();
    storage = _DelayedStorage(
      preferences: preferences,
      defaultRoot: p.join(temporary.path, 'data'),
      lockPath: p.join(temporary.path, 'storage.lock'),
    );
    await storage.initialize();
    launcher = NativeDevelopmentLauncher(storage, preferences);
  });

  tearDown(() async {
    launcher.dispose();
    await temporary.delete(recursive: true);
  });

  test(
    'stop during preparation waits for cancellation and permits retry',
    () async {
      final gate = Completer<void>();
      storage.inspectGate = gate;
      final launch = launcher.launchTest(
        worldName: '准备中的测试玩家',
        creative: true,
        menuOnly: false,
      );
      expect(launcher.busy, isTrue);
      var stopped = false;
      final stop = launcher.stopGame().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      gate.complete();
      await Future.wait([launch, stop]).timeout(const Duration(seconds: 5));
      expect(launcher.busy, isFalse);
      expect(launcher.running, isFalse);
      expect(launcher.error, isNull);

      // A subsequent launch reaches normal game validation, rather than keeping
      // a stale cancellation request. No game/runtime exists in this fixture.
      await launcher.launchTest(
        worldName: '重新测试',
        creative: true,
        menuOnly: false,
      );
      expect(launcher.error, '请先下载或导入游戏。');
    },
  );

  test(
    'repeated stop also cancels a guest queued behind another preparation',
    () async {
      final acquired = Completer<void>();
      final release = Completer<void>();
      final held = withFileLock(storage.lockPath, () async {
        acquired.complete();
        await release.future;
      });
      await acquired.future;
      final launch = launcher.launchTest(
        worldName: '等待共享文件的玩家',
        creative: true,
        menuOnly: false,
      );
      final firstStop = launcher.stopGame();
      final secondStop = launcher.stopGame();
      release.complete();
      await Future.wait([
        held,
        launch,
        firstStop,
        secondStop,
      ]).timeout(const Duration(seconds: 5));
      expect(launcher.busy, isFalse);
      expect(launcher.running, isFalse);
      expect(launcher.error, isNull);
      // A canceled launch releases both preparation and session leases.
      await storage.migrateTo(p.join(temporary.path, 'moved'));
      expect(storage.paths.root, p.join(temporary.path, 'moved'));
    },
  );
}
