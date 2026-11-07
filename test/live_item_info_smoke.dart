// Explicit opt-in. Uses isolated 3.10 copies and never the user's projects/saves.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'development_test.dart' show MemoryPreferences;

// PrintWindow reads only the game's window, so whatever else is on the desktop
// stays out of the file and the desktop's focus is left alone. The process must
// be DPI aware, or a scaled display reports a smaller window and crops the HUD.
const _captureGameWindow = r'''
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Native -Name Window -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool GetWindowRect(System.IntPtr window, int[] rect);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool PrintWindow(System.IntPtr window, System.IntPtr dc, uint flags);
"@
[Native.Window]::SetProcessDPIAware() | Out-Null
$window = (Get-Process minecraft_developer_manager |
  Where { $_.Path -eq $env:MCDEV_GAME_HOST -and $_.MainWindowHandle -ne 0 } |
  Select -First 1).MainWindowHandle
$rect = New-Object int[] 4
[Native.Window]::GetWindowRect($window, $rect) | Out-Null
$image = New-Object Drawing.Bitmap ($rect[2] - $rect[0]), ($rect[3] - $rect[1])
$graphics = [Drawing.Graphics]::FromImage($image)
$dc = $graphics.GetHdc()
[Native.Window]::PrintWindow($window, $dc, 2) | Out-Null
$graphics.ReleaseHdc($dc)
$image.Save($env:MCDEV_CAPTURE_PATH)
''';

Future<void> capture(String path) async {
  if (Platform.isWindows) {
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', _captureGameWindow],
      environment: {'MCDEV_CAPTURE_PATH': path},
    );
    stdout.writeln('ITEM INFO capture ${result.exitCode}: ${result.stderr}');
  } else {
    await Process.run('/usr/sbin/screencapture', ['-x', path]);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'HUD names crosshair targets and flags missing Chinese text',
    () async {
      final target = Platform.environment['MCDEV_LIVE_ITEM_INFO_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_AI_GAME_SOURCE'];
      final assets = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      final screenshot =
          Platform.environment['MCDEV_LIVE_ITEM_INFO_SCREENSHOT'];
      if (target == null ||
          source == null ||
          assets == null ||
          p.equals(target, source) ||
          p.isWithin(source, target) ||
          p.isWithin(target, source)) {
        throw StateError(
          'Separate isolated root, source and release assets required',
        );
      }
      final account = await FilePreferences.open(mcdevHome());
      final activeRoot =
          account.getString(DevelopmentStorage.preferenceKey) ?? source;
      if (p.equals(target, activeRoot) ||
          p.isWithin(activeRoot, target) ||
          p.isWithin(target, activeRoot)) {
        throw StateError('Refusing the live development directory');
      }
      CoreRuntime.preferences = () async => account;
      CoreRuntime.system = Platform.isWindows ? 'Windows' : 'Mac';
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
        final bundled = File(p.join(assets, key));
        final file = !key.startsWith('tools/') && await bundled.exists()
            ? bundled
            : File(p.join(Directory.current.path, key));
        return await file.exists()
            ? ByteData.sublistView(await file.readAsBytes())
            : null;
      });
      final preferences = MemoryPreferences();
      final storage = NativeDevelopmentStorage(
        preferences: preferences,
        defaultRoot: target,
        lockPath: p.join(p.dirname(target), 'item-info-storage.lock'),
      );
      await storage.initialize();
      final version =
          Platform.environment['MCDEV_LIVE_ITEM_INFO_VERSION'] ??
          '3.10.0.420447';
      for (final relative in [
        if (!Platform.isWindows) 'runtimes/wine-11.0_1-mcs-v1',
        'games/$version',
      ]) {
        final dest = Directory(p.join(target, relative));
        if (!await dest.exists()) {
          await dest.parent.create(recursive: true);
          final from = p.join(source, relative);
          final copy = Platform.isWindows
              ? await Process.run('robocopy', [
                  from,
                  dest.path,
                  '/E',
                  '/NFL',
                  '/NDL',
                  '/NJH',
                  '/NJS',
                  '/NP',
                ])
              : await Process.run('/bin/cp', ['-cR', from, dest.path]);
          // Robocopy reports success with any exit code below 8.
          expect(copy.exitCode, lessThan(Platform.isWindows ? 8 : 1));
        }
      }
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'item-info',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      Future<void>? lifetime;
      try {
        await host.refresh();
        await host.chooseVersion(version);
        await host.chooseItemInfoDisplay(true);
        await host.chooseNewWorld(true);
        await host.importMods(
          p.join(Directory.current.path, 'tools/item_info/fixtures'),
        );
        expect(host.error, isNull);
        lifetime = host.launchTest(
          worldName: '物品信息隔离验证',
          creative: true,
          menuOnly: false,
          seed: '20261107',
        );
        var captured = false;
        var log = '';
        for (
          var i = 0;
          i < 420 && !log.contains('ITEM_INFO_FIXTURE_DONE');
          i++
        ) {
          if (i % 30 == 0) {
            stdout.writeln(
              'ITEM INFO waiting $i: ${host.error}; ${host.logPath}',
            );
          }
          if (!host.running && host.error != null) {
            throw StateError(host.error!);
          }
          final file = host.logPath == null ? null : File(host.logPath!);
          if (file != null && await file.exists()) {
            log = await file.readAsString();
          }
          if (screenshot != null &&
              !captured &&
              log.contains('mcdev_item_fixture:unnamed.name')) {
            captured = true;
            await capture(screenshot);
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(
          log,
          contains('ITEM_INFO_FIXTURE_DONE'),
          reason: '${host.logPath}',
        );
        final shown = [
          for (final match in RegExp(r'ITEM_INFO_SHOWN (.*)').allMatches(log))
            jsonDecode(match.group(1)!.trim()) as List,
        ];
        stdout.writeln('ITEM INFO shown: ${jsonEncode(shown)}');
        bool displayed(Pattern text) => shown.any(
          (item) => item[0] == true && (item[1] as String).contains(text),
        );
        expect(displayed('§f花岗岩'), isTrue);
        expect(displayed('minecraft:granite:0'), isTrue);
        expect(displayed(RegExp(r'§f.*\n§7minecraft:oak_stairs:2')), isTrue);
        expect(displayed('§f测试方块'), isTrue);
        expect(
          displayed('§c未配置中文 tile.mcdev_item_fixture:unnamed.name'),
          isTrue,
        );
        expect(displayed('§eEnglish Only'), isTrue);
        expect(displayed('§f猪'), isTrue);
        expect(
          displayed('§c未配置中文 entity.mcdev_item_fixture:nameless.name'),
          isTrue,
        );
        expect(shown.last[0], isFalse, reason: 'No target hides the panel');
        expect(log, isNot(contains('MCDEV_ITEM_INFO failed')));
      } finally {
        await host.stopGame();
        await lifetime;
        host.dispose();
      }
      stdout.writeln('ITEM INFO LIVE PASS: ${host.logPath}');
    },
    skip: Platform.environment['MCDEV_LIVE_ITEM_INFO'] != '1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
