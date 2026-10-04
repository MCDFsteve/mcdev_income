import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/sound_patch_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'development_test.dart' show MemoryPreferences;
import 'test_settings_test.dart' show RejectTestSettingPreferences;

class _Assets extends CachingAssetBundle {
  _Assets({this.corrupt = false});
  final bool corrupt;
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    if (corrupt) bytes[0] ^= 1;
    return ByteData.sublistView(bytes);
  }
}

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
  )..selectedVersion = soundPatchVersion;

  test(
    'mute defaults off, persists per tab, and can be cleared on an unsupported version',
    () async {
      final preferences = MemoryPreferences();
      final first = launcher(preferences);
      expect(first.disableSound, isFalse);
      await first.chooseDisableSound(true);
      first.dispose();
      final reopened = launcher(preferences);
      final other = launcher(preferences, session: 'other');
      expect(reopened.disableSound, isTrue);
      expect(other.disableSound, isFalse);
      reopened.selectedVersion = '3.9.0.1';
      expect(reopened.disableSoundSupported, isFalse);
      await reopened.chooseDisableSound(false);
      await expectLater(reopened.chooseDisableSound(true), throwsException);
      expect(reopened.disableSound, isFalse);
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

  test(
    'audio adapter and helper are hash-pinned x64 PE assets; changed cache is repaired',
    () async {
      final directories = await Future.wait(
        List.generate(
          3,
          (_) => prepareSoundPatch(temp.path, bundle: _Assets()),
        ),
      );
      final directory = directories.first;
      expect(directories.map((item) => item.path).toSet(), hasLength(1));
      await File(
        p.join(directory.path, 'sound-patch.dll'),
      ).writeAsString('changed');
      await prepareSoundPatch(temp.path, bundle: _Assets());
      for (final entry in soundPatchAssets.entries) {
        final bytes = await File(
          p.join(directory.path, entry.key),
        ).readAsBytes();
        expect(sha256.convert(bytes).toString(), entry.value);
        final data = ByteData.sublistView(bytes);
        final header = data.getUint32(0x3c, Endian.little);
        expect(data.getUint16(0, Endian.little), 0x5a4d);
        expect(data.getUint16(header + 4, Endian.little), 0x8664);
      }
    },
  );

  test(
    'corrupt packaged DLL is refused before replacing cached files',
    () async {
      final directory = await Directory(
        p.join(temp.path, 'sound-patch-v1'),
      ).create();
      final dll = await File(
        p.join(directory.path, 'sound-patch.dll'),
      ).writeAsString('keep');
      await expectLater(
        prepareSoundPatch(temp.path, bundle: _Assets(corrupt: true)),
        throwsException,
      );
      expect(await dll.readAsString(), 'keep');
    },
  );

  test('version label and altered game cannot authorize injection', () async {
    final file = await File(
      p.join(temp.path, 'Minecraft.Windows.exe'),
    ).writeAsString('altered');
    expect(supportsSoundPatch(soundPatchVersion), isTrue);
    expect(supportsSoundPatch('3.10.0.420448'), isFalse);
    expect(supportsSoundPatch(null), isFalse);
    await expectLater(
      validateSoundGame(soundPatchVersion, file),
      throwsException,
    );
    await expectLater(validateSoundGame('3.9.0.1', file), throwsException);
    expect(await file.readAsString(), 'altered');
  });

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

  for (final state in ['armed', 'ready', 'failed']) {
    test(
      'native $state record confirms silence only for verified NOSOUND output',
      () async {
        if (Platform.isWindows) return;
        final helper = await File(
          p.join(temp.path, 'renderer-inject.exe'),
        ).writeAsString('exit 0\n');
        final log = await File(p.join(temp.path, 'sound.json')).writeAsString(
          jsonEncode({
            'state': state,
            'output': state == 'ready' ? 2 : -1,
            'reason': 'probe',
          }),
        );
        var current = true;
        var ready = false;
        final operation = activateSoundPatch(
          files: temp,
          executable: 'game.exe',
          wine: '/bin/sh',
          targetPid: 1,
          environment: const {},
          gamePath: (path) => path,
          log: log,
          exited: Future<void>.delayed(const Duration(seconds: 2)),
          current: () => current,
          onReady: () {
            ready = true;
            current = false;
          },
          readyTimeout: const Duration(milliseconds: 30),
        );
        expect(await helper.exists(), isTrue);
        if (state == 'ready') {
          await operation;
          expect(ready, isTrue);
        } else {
          await expectLater(operation, throwsException);
          expect(ready, isFalse);
        }
      },
    );
  }

  test('native failure after readiness is still reported', () async {
    if (Platform.isWindows) return;
    await File(
      p.join(temp.path, 'renderer-inject.exe'),
    ).writeAsString('exit 0\n');
    final log = await File(
      p.join(temp.path, 'sound.json'),
    ).writeAsString(jsonEncode({'state': 'ready', 'output': 2}));
    final ready = Completer<void>();
    final operation = activateSoundPatch(
      files: temp,
      executable: 'game.exe',
      wine: '/bin/sh',
      targetPid: 1,
      environment: const {},
      gamePath: (path) => path,
      log: log,
      exited: Future<void>.delayed(const Duration(seconds: 2)),
      current: () => true,
      onReady: ready.complete,
    );
    final failed = expectLater(operation, throwsException);
    await ready.future;
    await log.writeAsString(
      jsonEncode({'state': 'failed', 'reason': 'output_switch'}),
    );
    await failed;
  });
}
