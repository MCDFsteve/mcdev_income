// Opt-in real world probe. It reads an existing locally generated launch config
// without printing its credentials, and uses a separate profile and fresh world.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:mcdev_income/development/platform/game_window_backend.dart';
import 'package:mcdev_income/development/platform/windows_game_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/lan_bridge_io.dart';
import 'package:mcdev_income/development/lan_endpoint_io.dart';
import 'package:mcdev_income/development/lan_rpc_io.dart';
import 'package:mcdev_income/development/mod_log_io.dart';
import 'package:mcdev_income/development/lan_patch_io.dart';
import 'package:mcdev_income/development/platform/windows_game_runtime.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/development/platform/host_files_io.dart';
import 'development_test.dart' show MemoryPreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native test world reaches a live server without a crash',
    () async {
      final configPath = Platform.environment['MCDEV_WORLD_CONFIG'];
      final source = Platform.environment['MCDEV_WINDOWS_GAME'];
      if (!Platform.isWindows || configPath == null || source == null) {
        throw StateError('Set MCDEV_WORLD_CONFIG and MCDEV_WINDOWS_GAME.');
      }
      final renderer = int.parse(
        Platform.environment['MCDEV_WORLD_RENDERER'] ?? '0',
      );
      final useLan = Platform.environment['MCDEV_TEST_LAN'] == '1';
      final root = p.absolute('build', 'world-probe');
      final storage = NativeDevelopmentStorage(
        preferences: MemoryPreferences(),
        defaultRoot: root,
        lockPath: '$root.lock',
      );
      await storage.initialize();
      final session = 'probe${DateTime.now().millisecondsSinceEpoch}';
      final runtime = WindowsGameRuntime(
        storage,
        session,
        window: Platform.environment['MCDEV_GAME_HOST'] == null
            ? const HeadlessGameWindow()
            : WindowsGameWindow(
                hostExecutable: Platform.environment['MCDEV_GAME_HOST'],
              ),
      );
      await runtime.prepare((_) {});
      addTearDown(runtime.terminateHelpers);
      final diagnostics = await runtime.createDiagnostics();
      await diagnostics.prepare();
      final diagnosticText = StringBuffer();
      final observed = diagnostics.watch().listen(
        (event) => diagnosticText.write(event.logLine),
      );
      addTearDown(observed.cancel);
      final game = p.join(root, 'game');
      if (!await File(p.join(game, 'Minecraft.Windows.exe')).exists()) {
        await copyDevelopmentTree(source, game);
      }
      final config =
          jsonDecode(await File(configPath).readAsString())
              as Map<String, dynamic>;
      final configFile = File(p.join(runtime.testDirectory, 'test.cppconfig'));
      final roam = await runtime.roaming();
      final bridge = await LanRosterBridge.create(
        behaviorPacksDirectory: p.join(
          roam,
          'MinecraftPE_Netease',
          'games',
          'com.netease',
          'behavior_packs',
        ),
        reportPath: p.join(runtime.testDirectory, 'roster.json'),
        windowsReportPath: runtime.testFilePath('roster.json'),
      );
      config['path'] = configFile.path;
      config['render_engine'] = renderer;
      config['world_info']['level_id'] = 'mcdev_test';
      config['world_info']['name'] = 'MCDev Windows probe';
      config['world_info']['seed'] = '12345';
      config['world_info']['resource_packs'] = <String>[];
      config['world_info']['behavior_packs'] = [bridge.directoryName];
      config['room_info']['port'] = await chooseAvailableLanPort();
      final rpc = await LanGameRpc.start();
      addTearDown(rpc.close);
      config['misc']['launcher_port'] = rpc.port;
      final skin = Platform.environment['MCDEV_WORLD_SKIN'] == 'alex'
          ? TestPlayerSkin.alex
          : TestPlayerSkin.steve;
      config['skin_info'] = await runtime.prepareSkin(skin, game);
      File? skinPixels;
      if (Platform.environment['MCDEV_CHECK_SKIN'] == '1') {
        final original = await File(
          p.join(game, 'data', 'skin_packs', 'vanilla', skin.textureFile),
        ).readAsBytes();
        if (config['skin_info']['in_package'] != true) {
          expect(
            await File(config['skin_info']['skin']).readAsBytes(),
            original,
          );
        }
        final rgba = img.decodePng(original)!.convert(numChannels: 4);
        skinPixels = await File(
          p.join(runtime.testDirectory, 'skin.rgba'),
        ).writeAsBytes(rgba.getBytes(order: img.ChannelOrder.rgba));
        final dummy = img.decodePng(
          await File(
            p.join(game, 'data/skin_packs/vanilla/dummy.png'),
          ).readAsBytes(),
        )!;
        await File(p.join(runtime.testDirectory, 'dummy.rgba')).writeAsBytes(
          dummy.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba),
        );
      }
      final assertions = Directory(p.join(runtime.testDirectory, 'assertions'));
      await assertions.create(recursive: true);
      await File(p.join(game, 'netease_data.json')).writeAsString(
        jsonEncode({
          'Uid': '',
          'Urs': '',
          'ServerName': 'MCS',
          'Product': 'mcstudio_mod_pc',
          'AssertCacheDir': assertions.path,
        }),
      );
      await configFile.writeAsString(jsonEncode(config));
      final options = File(
        p.join(roam, 'MinecraftPE_Netease', 'minecraftpe', 'options.txt'),
      );
      await options.parent.create(recursive: true);
      await options.writeAsString(
        'resource_concatenation_enabled:0\ndev_assertions_debug_break:0\ngfx_max_framerate:60\n',
      );
      final logger = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      logger.listen((socket) {
        peers.add(socket);
        final decoder = ModLogDecoder((text) {
          // Only bridge failures/frames, never account or config output.
          for (final line in text.split('\n')) {
            if (RegExp(
              r'MCDEV_LAN_BRIDGE|mcdevLanBridgeScripts|Traceback|File "|^(?:IOError|ImportError|AttributeError|SyntaxError)',
            ).hasMatch(line)) {
              stdout.writeln('Engine: $line');
            }
          }
        });
        socket.listen(decoder.add, onDone: decoder.close);
      });
      addTearDown(() async {
        for (final peer in peers) {
          peer.destroy();
        }
        await logger.close();
      });
      final child = await runtime.start(
        executable: p.join(game, 'Minecraft.Windows.exe'),
        arguments: [
          'dc_tag1=studio_no_launcher',
          'config=${configFile.path}',
          'loggingIP=127.0.0.1',
          'loggingPort=${logger.port}',
        ],
        workingDirectory: game,
        version: config['version'],
        displayName: 'MCDev probe',
        renderer: renderer == 0 ? 'OpenGL' : '渲染龙',
        fullscreenShortcut: false,
        overrides: {
          if (skinPixels != null) ...{
            'MCDEV_SKIN_PROBE_PIXELS': skinPixels.path,
            'MCDEV_SKIN_PROBE_DUMMY': p.join(
              runtime.testDirectory,
              'dummy.rgba',
            ),
            'MCDEV_SKIN_PROBE_LOG': p.join(
              runtime.testDirectory,
              'skin-gpu.log',
            ),
          },
          if (useLan) ...{
            'MCDEV_LAN_PATCH_LOG': runtime.testFilePath('lan.log'),
            'MCDEV_LAN_ROLE': 'host',
          },
        },
      );
      final drains = [child.stdout.drain<void>(), child.stderr.drain<void>()];
      int? exitCode;
      unawaited(child.exitCode.then((code) => exitCode = code));
      stdout.writeln(
        'Probe PID=${child.pid}, renderer=$renderer, profile=${runtime.prefix}',
      );
      var ready = false;
      var ticks = 0;
      var sequence = -1;
      String? crash;
      try {
        if (skinPixels != null && renderer == 0) {
          final injected = await Process.run(
            p.absolute(
              'build/windows/x64/runner/Release/mcdev_game_helper.exe',
            ),
            [
              p.absolute(
                'build/windows-diagnostics/Release/mcdev_skin_gl_probe.dll',
              ),
              p.join(game, 'Minecraft.Windows.exe'),
              '${child.pid}',
            ],
          ).timeout(const Duration(seconds: 110));
          expect(injected.exitCode, 0);
        }
        if (useLan) {
          await validateLanGame(
            config['version'],
            File(p.join(game, 'Minecraft.Windows.exe')),
          );
          final files = await prepareLanPatch(storage.paths.runtimes);
          final injected = await Process.run(
            p.absolute(
              'build/windows/x64/runner/Release/mcdev_game_helper.exe',
            ),
            [
              p.join(files.path, 'lan-patch.dll'),
              runtime.gamePath(p.join(game, 'Minecraft.Windows.exe')),
              '${child.pid}',
            ],
          ).timeout(const Duration(seconds: 110));
          expect(injected.exitCode, 0, reason: 'Native LAN helper failed.');
        }
        for (var i = 0; i < 110 && exitCode == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (await bridge.reportFile.exists()) {
            final report = await bridge.readReport();
            if (report != null &&
                report.players.isNotEmpty &&
                report.sequence > sequence) {
              sequence = report.sequence;
              ready = true;
              ticks++;
              if (ticks >= 15) break;
            }
          }
          final crashRoot = Directory(
            p.join(runtime.profile, 'AppData', 'Local', 'UniSDK', 'CrashDump'),
          );
          if (await crashRoot.exists()) {
            await for (final entry in crashRoot.list(recursive: true)) {
              if (entry.path.endsWith('.dmp')) {
                crash = entry.path;
                break;
              }
            }
          }
          if (crash != null) break;
        }
        final result = {
          'pid': child.pid,
          'renderer': renderer,
          'ready': ready,
          'liveReports': ticks,
          'exitCode': exitCode,
          'crash': crash,
          'profile': runtime.prefix,
        };
        await File(
          p.join(root, 'result-$session.json'),
        ).writeAsString(jsonEncode(result));
        stdout.writeln(jsonEncode(result));
        if (Platform.environment['MCDEV_GAME_HOST'] != null) {
          final native = await Process.run(
            p.absolute(
              'build/windows-diagnostics/Release/mcdev_game_diagnostics.exe',
            ),
            ['${child.pid}'],
          );
          stdout.writeln(native.stdout);
          expect(native.exitCode, 0);
          expect(native.stdout.toString(), contains('embedded=1 borderless=1'));
          expect(native.stdout.toString(), contains('frame_icon=1'));
          expect(
            native.stdout.toString(),
            matches(
              r'embedded=1 borderless=1 [^\r\n]*\r?\nwindow=[^\r\n]* hung=0(?: |$)',
            ),
            reason: 'The embedded game window must be responsive.',
          );
          expect(diagnosticText.toString(), contains('游戏窗口已就绪'));
        }
        expect(diagnosticText.toString(), contains('引擎正在加载测试世界'));
        await File(
          p.join(runtime.testDirectory, 'runtime.log'),
        ).writeAsString(diagnosticText.toString());
        expect(crash, isNull);
        expect(ready && ticks >= 15, isTrue);
        if (skinPixels != null) {
          final gpuLog = File(p.join(runtime.testDirectory, 'skin-gpu.log'));
          if (await gpuLog.exists()) {
            final lines = (await gpuLog.readAsString()).split('\n');
            expect(
              lines.any((line) => line.contains('rgb_match=1')),
              isTrue,
              reason: 'Selected skin was not uploaded to the OpenGL renderer.',
            );
            stdout.writeln(
              'Skin GPU uploads=${lines.where((l) => l.startsWith('skin_gpu_upload')).length}, matches=${lines.where((l) => l.contains('rgb_match=1')).length}',
            );
          }
          final skinCheck = await Process.run(
            p.absolute(
              'build/windows-diagnostics/Release/mcdev_skin_diagnostics.exe',
            ),
            ['${child.pid}', skinPixels.path],
          ).timeout(const Duration(seconds: 45));
          stdout.writeln(skinCheck.stdout);
          expect(
            skinCheck.exitCode,
            0,
            reason: 'Official skin pixels were not decoded.',
          );
        }
        if (useLan) {
          expect(
            await File(p.join(runtime.testDirectory, 'lan.log')).readAsString(),
            contains('"lan_patch":"ready"'),
          );
        }
        final hold =
            int.tryParse(
              Platform.environment['MCDEV_HOLD_WORLD_SECONDS'] ?? '0',
            ) ??
            0;
        if (hold > 0) {
          stdout.writeln('World ready; holding for manual inspection.');
          await Future.any([
            child.exitCode,
            Future<void>.delayed(Duration(seconds: hold.clamp(0, 300))),
          ]);
        }
      } finally {
        await runtime.stop(child);
        stdout.writeln('Shutdown exitCode=${await child.exitCode}');
        await runtime.terminateHelpers();
        await Future.wait(drains).timeout(const Duration(seconds: 5));
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
