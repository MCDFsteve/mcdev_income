import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'development_test.dart' show MemoryPreferences;

class RejectTestSettingPreferences extends MemoryPreferences {
  @override
  Future<bool> setInt(String key, int value) async => false;
  @override
  Future<bool> setString(String key, String value) async => false;
}

void main() {
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('mcdev-settings-'),
  );
  tearDown(() async => temp.delete(recursive: true));

  NativeDevelopmentLauncher launcher(MemoryPreferences preferences) =>
      NativeDevelopmentLauncher(
        NativeDevelopmentStorage(
          preferences: preferences,
          defaultRoot: temp.path,
          lockPath: p.join(temp.path, 'lock'),
        ),
        preferences,
      );

  test('PNG skins select the MCS identity and matching arm model', () {
    for (final skin in TestPlayerSkin.values) {
      final texture = p.windows.join(
        r'Z:\games\3.10.0.420447',
        'data',
        'skin_packs',
        'vanilla',
        skin.textureFile,
      );
      final config = skin.skinInfo(texture);
      expect(config['skin'], endsWith(skin.textureFile));
      expect(config['in_package'], isFalse);
      expect(config['sync'], isTrue);
      expect(config['slim'], skin == TestPlayerSkin.alex);
      expect(config['slim'], isA<bool>());
      expect(config['skin_iid'], skin == TestPlayerSkin.alex ? '-2' : '-1');
    }
  });

  test(
    'console and fullscreen shortcut default off; settings survive reopening and version changes',
    () async {
      final preferences = MemoryPreferences();
      final first = launcher(preferences);
      expect(first.showDeveloperConsole, isFalse);
      expect(first.fullscreenShortcut, isFalse);
      expect(first.playerSkin, TestPlayerSkin.steve);
      await first.chooseDeveloperConsole(true);
      await first.chooseFullscreenShortcut(true);
      await first.choosePlayerSkin(TestPlayerSkin.alex);
      expect(first.limit60Fps, isTrue);
      expect(first.performanceOptimization, isTrue);
      first.dispose();

      await preferences.setString(
        'development_game_version_v1',
        '3.10.0.420447',
      );
      final second = launcher(preferences);
      expect(second.showDeveloperConsole, isTrue);
      expect(second.fullscreenShortcut, isTrue);
      expect(second.playerSkin, TestPlayerSkin.alex);
      await second.chooseDeveloperConsole(false);
      await second.chooseFullscreenShortcut(false);
      await second.choosePlayerSkin(TestPlayerSkin.steve);
      second.dispose();

      final third = launcher(preferences);
      expect(third.showDeveloperConsole, isFalse);
      expect(third.fullscreenShortcut, isFalse);
      expect(third.playerSkin, TestPlayerSkin.steve);
      third.dispose();
    },
  );

  test('unknown saved skin falls back to the built-in Steve skin', () async {
    final preferences = MemoryPreferences();
    await preferences.setString('development_player_skin_v1', 'removed-skin');
    final instance = launcher(preferences);
    expect(instance.playerSkin, TestPlayerSkin.steve);
    instance.dispose();
  });

  for (final state in ['busy', 'running', 'failed write']) {
    test('test settings do not change during $state', () async {
      final instance =
          launcher(
              state == 'failed write'
                  ? RejectTestSettingPreferences()
                  : MemoryPreferences(),
            )
            ..busy = state == 'busy'
            ..running = state == 'running';
      await expectLater(instance.chooseDeveloperConsole(true), throwsException);
      await expectLater(
        instance.chooseFullscreenShortcut(true),
        throwsException,
      );
      await expectLater(
        instance.choosePlayerSkin(TestPlayerSkin.alex),
        throwsException,
      );
      expect(instance.showDeveloperConsole, isFalse);
      expect(instance.fullscreenShortcut, isFalse);
      expect(instance.playerSkin, TestPlayerSkin.steve);
      instance
        ..busy = false
        ..running = false
        ..dispose();
    });
  }
}
