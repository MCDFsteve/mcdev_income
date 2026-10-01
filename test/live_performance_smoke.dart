// Explicit opt-in diagnostic. Only runs against a separate snapshot of the
// runtime, game and prefix; it never changes the user's selected mods or saves.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/performance_patch.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';

class IsolatedGraphicsPreferences implements PreferenceStore {
  IsolatedGraphicsPreferences(String root)
    : values = {
        DevelopmentStorage.preferenceKey: root,
        'development_game_version_v1': performancePatchVersion,
        'development_performance_patch_v1': 1,
        'development_frame_limit_60_v1':
            Platform.environment['MCDEV_LIVE_LIMIT60'] == '0' ? 0 : 1,
      };
  final Map<String, Object> values;
  @override
  String? getString(String key) => values[key] as String?;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<void> apply(Map<String, Object?> changes) async {
    for (final entry in changes.entries) {
      if (entry.value == null) {
        values.remove(entry.key);
      } else {
        values[entry.key] = entry.value!;
      }
    }
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'Release assets activate through the real isolated launcher',
    () async {
      final root = Platform.environment['MCDEV_LIVE_PERFORMANCE_ROOT'];
      final bundle = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      if (root == null || bundle == null) {
        throw StateError('Explicit isolated root and Release assets required');
      }
      final realRoot = await Directory(root).resolveSymbolicLinks();
      final accountPreferences = await FilePreferences.open(mcdevHome());
      final originalRoot =
          accountPreferences.getString(DevelopmentStorage.preferenceKey) ??
          p.join(
            Platform.environment['HOME']!,
            'Library',
            'Application Support',
            'mcdev_income',
            'development',
          );
      final original = await Directory(originalRoot).resolveSymbolicLinks();
      if (p.equals(realRoot, original) || p.isWithin(original, realRoot)) {
        throw StateError(
          'Refusing to run against the real development directory',
        );
      }
      final isolatedPrefix = await Directory(
        p.join(realRoot, 'prefixes', 'game'),
      ).resolveSymbolicLinks();
      if (!p.isWithin(realRoot, isolatedPrefix)) {
        throw StateError('The test prefix must be a separate copy');
      }
      CoreRuntime.preferences = () async => accountPreferences;
      CoreRuntime.system = 'Mac';
      binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
        message,
      ) async {
        if (message == null) return null;
        final key = utf8.decode(
          message.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        final file = File(p.join(bundle, key));
        return await file.exists()
            ? ByteData.sublistView(await file.readAsBytes())
            : null;
      });
      final preferences = IsolatedGraphicsPreferences(realRoot);
      final storage = NativeDevelopmentStorage(
        preferences: preferences,
        defaultRoot: realRoot,
        lockPath: p.join(p.dirname(realRoot), 'locks', 'launcher.lock'),
      );
      final launcher = NativeDevelopmentLauncher(
        storage,
        preferences,
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      String? lastStatus;
      launcher.addListener(() {
        final status = launcher.notice ?? launcher.progress?.message;
        if (status != null && status != lastStatus) {
          lastStatus = status;
          stdout.writeln('Isolated launcher status: $status');
        }
      });
      Future<void>? launched;
      try {
        await launcher.refresh();
        expect(launcher.performanceOptimization, isTrue);
        expect(launcher.performanceOptimizationSupported, isTrue);
        launched = launcher.launchTest(
          worldName: '性能补丁隔离验证',
          creative: true,
          menuOnly: false,
        );
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (!(launcher.notice?.contains('已生效') ?? false)) {
          if (launcher.error != null || DateTime.now().isAfter(deadline)) {
            throw StateError(
              'Isolated launch did not activate (details withheld)',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        stdout.writeln(
          'Isolated launcher: automatic graphics patch active; cap=${launcher.limit60Fps}',
        );
        final suffix = p.basename(launcher.logPath!).substring('test-'.length);
        final target = File(p.join(storage.paths.logs, 'performance-$suffix'));
        final warmupWindows = int.parse(
          Platform.environment['MCDEV_LIVE_WARMUP_WINDOWS'] ?? '1',
        );
        if (warmupWindows < 1 || warmupWindows > 90) {
          throw StateError('Invalid warm-up duration');
        }
        List<Map<String, dynamic>> summaries = [];
        while (launcher.running &&
            summaries.length < warmupWindows + 30 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(seconds: 2));
          summaries = (await target.readAsLines())
              .where((line) => line.contains('"frame_ms_mean"'))
              .map((line) => jsonDecode(line) as Map<String, dynamic>)
              // Loading screens and shutdown swaps can run thousands of times
              // per second without drawing the world. Benchmark actual uploads.
              .where((row) => (row['buffer_uploads'] as num) > 0)
              .toList();
        }
        expect(
          summaries.length,
          greaterThanOrEqualTo(warmupWindows + 30),
          reason: 'Keep the test game open until measurement has completed',
        );
        final status = (await target.readAsLines())
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .where((row) => row['performance_patch'] == 'active')
            .single;
        // The verified September 30 DLL already supports the environment switch
        // but predates this optional status field. Verify its frame cadence below.
        if (status.containsKey('limit_60_fps')) {
          expect(status['limit_60_fps'], launcher.limit60Fps);
        }
        final samples = summaries.skip(warmupWindows).toList();
        if (launcher.limit60Fps) {
          // An upper limit does not guarantee the hardware reaches 60 FPS.
          // Check the real presentation cadence, allowing logging precision.
          expect(
            samples.every((row) => (row['frame_ms_mean'] as num) >= 16.65),
            isTrue,
          );
        }
        final ms =
            samples
                .map((row) => row['frame_ms_mean'] as num)
                .reduce((a, b) => a + b) /
            samples.length;
        final result = {
          'automatic_injection': true,
          'limit_60_fps': launcher.limit60Fps,
          'frames': samples.length * 120,
          'fps': 1000 / ms,
          'frame_ms_mean': ms,
          'release_dll_sha256': performancePatchAssets['graphics-patch.dll'],
          'baseline_suspended':
              Platform.environment['MCDEV_TEST_BASELINE_SUSPENDED'] == '1',
          'viewport_width': samples.last['viewport_width'],
          'viewport_height': samples.last['viewport_height'],
          'interactive_validation': 'pending',
        };
        await File(
          p.join(
            p.dirname(realRoot),
            launcher.limit60Fps
                ? 'result-capped.json'
                : 'result-unlimited.json',
          ),
        ).writeAsString('${jsonEncode(result)}\n', flush: true);
        stdout.writeln('Isolated performance summary: ${jsonEncode(result)}');
        final holdSeconds = int.parse(
          Platform.environment['MCDEV_LIVE_HOLD_SECONDS'] ?? '0',
        );
        if (holdSeconds < 0 || holdSeconds > 300) {
          throw StateError('Invalid interactive hold duration');
        }
        if (holdSeconds > 0) {
          stdout.writeln('Isolated game ready for foreground interaction');
          final until = DateTime.now().add(Duration(seconds: holdSeconds));
          while (launcher.running && DateTime.now().isBefore(until)) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
        final minimum = Platform.environment['MCDEV_LIVE_MIN_FPS'];
        if (minimum != null) {
          expect(
            result['fps'] as double,
            greaterThanOrEqualTo(double.parse(minimum)),
          );
        }
      } finally {
        if (launcher.running) await launcher.stopGame();
        if (launched != null) {
          await launched.timeout(const Duration(seconds: 45));
        }
        launcher.dispose();
        binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
