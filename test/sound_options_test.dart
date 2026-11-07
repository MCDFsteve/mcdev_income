import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/sound_options_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'development_test.dart' show MemoryPreferences;
import 'test_settings_test.dart' show RejectTestSettingPreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(
    () async => temp = await Directory.systemTemp.createTemp('mcdev-sound-'),
  );
  tearDown(() async => temp.delete(recursive: true));
  NativeDevelopmentLauncher launcher(
    MemoryPreferences preferences, {
    String session = 'default',
  }) => NativeDevelopmentLauncher(
    NativeDevelopmentStorage(
      preferences: preferences,
      defaultRoot: temp.path,
      lockPath: p.join(temp.path, 'lock'),
    ),
    preferences,
    sessionId: session,
  );

  test(
    'mute defaults off, persists per tab, and works on any version',
    () async {
      final preferences = MemoryPreferences();
      final first = launcher(preferences)..selectedVersion = '3.8.0.313229';
      expect(first.disableSound, isFalse);
      await first.chooseDisableSound(true);
      expect(first.disableSound, isTrue);
      first.dispose();
      final reopened = launcher(preferences);
      final other = launcher(preferences, session: 'other');
      expect(reopened.disableSound, isTrue);
      expect(other.disableSound, isFalse);
      reopened.dispose();
      other.dispose();
    },
  );

  for (final state in ['busy', 'running', 'failed write']) {
    test('mute setting is unchanged during $state', () async {
      final instance =
          launcher(
              state == 'failed write'
                  ? RejectTestSettingPreferences()
                  : MemoryPreferences(),
            )
            ..busy = state == 'busy'
            ..running = state == 'running';
      await expectLater(instance.chooseDisableSound(true), throwsException);
      expect(instance.disableSound, isFalse);
      instance
        ..busy = false
        ..running = false
        ..dispose();
    });
  }

  for (final original in [
    'audio_main:0.7\r\ngfx_viewdistance:8\r\n',
    'gfx_viewdistance:8\n',
  ]) {
    test(
      'startup volume restoration preserves game-written options ($original)',
      () async {
        final options = File(p.join(temp.path, 'options.txt'));
        final guard = SoundOptionsGuard(options);
        await guard.capture(original);
        await options.writeAsString(
          'audio_main:0\r\ngfx_viewdistance:12\r\naudio_music:0.8\r\n',
        );
        // A fresh object models recovery after the launcher was interrupted.
        await SoundOptionsGuard(options).restore();
        final restored = await options.readAsString();
        expect(
          restored,
          contains(
            original.contains('0.7') ? 'audio_main:0.7' : 'audio_main:1',
          ),
        );
        expect(restored, contains('gfx_viewdistance:12'));
        expect(restored, contains('audio_music:0.8'));
        expect(await guard.backup.exists(), isFalse);
        await guard.restore();
        expect(await options.readAsString(), restored);
      },
    );
  }
}
