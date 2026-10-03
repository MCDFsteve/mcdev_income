import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'development_storage.dart';

class TestWorldLaunch {
  const TestWorldLaunch(this.levelId, this.seed);
  final String levelId;
  final String seed;
}

/// Keep the old world until the game has actually written its replacement.
/// The pending record also survives a launcher crash while the game is open.
/// The caller holds the development directory's cross-process launch lock.
class TestWorldStore {
  TestWorldStore(this.directory);
  final String directory;
  static const legacyLevelId = 'mcdev_test';
  static final _validId = RegExp(r'^mcdev_test(?:_[a-f0-9]{32})?$');
  File get _state => File(p.join(directory, '.mcdev-test-world.json'));

  Future<TestWorldLaunch> prepare({
    required bool fresh,
    String seed = '',
  }) async {
    var active = legacyLevelId;
    String? pending;
    if (await _state.exists()) {
      try {
        final data = jsonDecode(await _state.readAsString());
        if (data is! Map ||
            data['version'] != 1 ||
            data['active'] is! String ||
            !_validId.hasMatch(data['active']) ||
            (data['pending'] != null &&
                (data['pending'] is! String ||
                    !_validId.hasMatch(data['pending'])))) {
          throw const FormatException('Invalid test world record');
        }
        active = data['active'] as String;
        pending = data['pending'] as String?;
      } on FormatException {
        throw const DevelopmentStorageException('测试存档记录损坏，未切换存档。');
      }
    }
    if (pending != null) {
      final level = File(p.join(directory, pending, 'level.dat'));
      if (await level.exists() && await level.length() > 8) active = pending;
    }

    String? next;
    if (fresh) {
      final random = Random.secure();
      do {
        final suffix = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        next = '${legacyLevelId}_$suffix';
      } while (await FileSystemEntity.type(
            p.join(directory, next),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound);
    }
    if (fresh || pending != null) {
      await Directory(directory).create(recursive: true);
      final staging = await Directory(directory).createTemp('.world-state-');
      try {
        final file = File(p.join(staging.path, 'state.json'));
        await file.writeAsString(
          jsonEncode({'version': 1, 'active': active, 'pending': ?next}),
          flush: true,
        );
        await file.rename(_state.path);
      } finally {
        await staging.delete(recursive: true);
      }
    }
    return TestWorldLaunch(next ?? active, fresh ? seed.trim() : '');
  }
}
