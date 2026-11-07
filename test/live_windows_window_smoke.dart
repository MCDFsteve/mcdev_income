// Explicit opt-in on Windows. Launches an isolated copy several times and
// records whether the game window stays embedded in its chrome host.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'development_test.dart' show MemoryPreferences;

/// One JSON line per sample: every visible top-level window of the game, and
/// whether a game window is currently a child of the host's frame.
const _sampler = r'''
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Windows {
  delegate bool Visit(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(Visit v, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, Visit v, IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern long GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, int[] r);
  static string Describe(IntPtr h) {
    var c = new StringBuilder(64); GetClassName(h, c, 64); int[] r = new int[4]; GetWindowRect(h, r);
    return "{\"hwnd\":" + h.ToInt64() + ",\"class\":\"" + c + "\",\"style\":" + GetWindowLongPtr(h, -16) +
      ",\"parent\":" + GetParent(h).ToInt64() + ",\"rect\":[" + r[0] + "," + r[1] + "," + r[2] + "," + r[3] + "]}";
  }
  public static string Sample(uint game, uint host) {
    var top = new List<string>(); var frames = new List<IntPtr>(); var embedded = new List<string>();
    var hidden = new List<string>();
    EnumWindows((h, p) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      bool shown = IsWindowVisible(h) && GetWindow(h, 4) == IntPtr.Zero;
      if (pid == game) (shown ? top : hidden).Add(Describe(h));
      if (pid == host && shown) frames.Add(h);
      return true;
    }, IntPtr.Zero);
    foreach (var f in frames) EnumChildWindows(f, (h, p) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == game) embedded.Add(Describe(h));
      return true;
    }, IntPtr.Zero);
    return "{\"frames\":" + frames.Count + ",\"top\":[" + string.Join(",", top) + "],\"embedded\":[" + string.Join(",", embedded) + "],\"hidden\":[" + string.Join(",", hidden) + "]}";
  }
}
"@
$start = $null
$wait = Get-Date
while (-not $start -or ((Get-Date) - $start).TotalSeconds -lt [int]$env:MCDEV_SAMPLE_SECONDS) {
  if (((Get-Date) - $wait).TotalSeconds -gt 600) { break }
  $game = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue | Where { $_.Path -like $env:MCDEV_SAMPLE_GAME } | Select -First 1
  if ($game -and -not $start) { $start = Get-Date }
  $host_ = Get-Process minecraft_developer_manager -ErrorAction SilentlyContinue | Where { $_.Path -eq $env:MCDEV_GAME_HOST } | Select -First 1
  if ($game -and $host_) {
    "{0:0.0} {1}" -f ((Get-Date) - $start).TotalSeconds, [Windows]::Sample([uint32]$game.Id, [uint32]$host_.Id)
  }
  Start-Sleep -Milliseconds 200
}
''';

/// Does what a game still adjusting its window may do after it was embedded:
/// move it over the title bar, then detach it as a captioned top-level window.
/// Prints where the host left the window one second after each change.
const _disturb = r'''
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class Disturb {
  delegate bool Visit(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(Visit v, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, Visit v, IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
  [DllImport("user32.dll")] static extern long GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] static extern long SetWindowLongPtr(IntPtr h, int i, long v);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int ht, uint f);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, int[] r);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, int[] r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, int[] p);
  static IntPtr frame, game;
  static void Find(uint gamePid, uint hostPid) {
    frame = IntPtr.Zero; game = IntPtr.Zero;
    EnumWindows((h, p) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == hostPid && IsWindowVisible(h)) frame = h;
      return true;
    }, IntPtr.Zero);
    if (frame != IntPtr.Zero) EnumChildWindows(frame, (h, p) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == gamePid && game == IntPtr.Zero) game = h;
      return true;
    }, IntPtr.Zero);
  }
  static string State() {
    int[] w = new int[4], c = new int[4], o = new int[2];
    GetWindowRect(game, w); GetClientRect(frame, c); ClientToScreen(frame, o);
    return "{\"embedded\":" + (GetParent(game) == frame ? "true" : "false") +
      ",\"style\":" + GetWindowLongPtr(game, -16) + ",\"top\":" + (w[1] - o[1]) +
      ",\"left\":" + (w[0] - o[0]) + ",\"width\":" + (w[2] - w[0]) + ",\"frameWidth\":" + c[2] + "}";
  }
  public static string Run(uint gamePid, uint hostPid) {
    Find(gamePid, hostPid);
    if (game == IntPtr.Zero) return "{\"error\":\"not embedded\"}";
    string before = State();
    SetWindowPos(game, IntPtr.Zero, 0, 0, 300, 200, 0x14);
    System.Threading.Thread.Sleep(1000);
    string moved = State();
    long style = GetWindowLongPtr(game, -16);
    SetWindowLongPtr(game, -16, (style & ~0x40000000L) | 0x00CF0000L);
    SetParent(game, IntPtr.Zero);
    SetWindowPos(game, IntPtr.Zero, 120, 120, 800, 500, 0x34);
    System.Threading.Thread.Sleep(1000);
    return "{\"before\":" + before + ",\"moved\":" + moved + ",\"detached\":" + State() + "}";
  }
}
"@
$game = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue | Where { $_.Path -like $env:MCDEV_SAMPLE_GAME } | Select -First 1
$host_ = Get-Process minecraft_developer_manager -ErrorAction SilentlyContinue | Where { $_.Path -eq $env:MCDEV_GAME_HOST } | Select -First 1
[Disturb]::Run([uint32]$game.Id, [uint32]$host_.Id)
''';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'game window stays embedded in its host across repeated launches',
    () async {
      final target = Platform.environment['MCDEV_LIVE_WINDOW_ROOT'];
      final source = Platform.environment['MCDEV_LIVE_AI_GAME_SOURCE'];
      final assets = Platform.environment['MCDEV_LIVE_RELEASE_ASSETS'];
      final hostExecutable = Platform.environment['MCDEV_GAME_HOST'];
      final version =
          Platform.environment['MCDEV_LIVE_WINDOW_VERSION'] ?? '3.10.0.420447';
      final launches =
          int.tryParse(
            Platform.environment['MCDEV_LIVE_WINDOW_LAUNCHES'] ?? '',
          ) ??
          6;
      if (!Platform.isWindows ||
          target == null ||
          source == null ||
          assets == null ||
          hostExecutable == null ||
          p.isWithin(source, target) ||
          p.isWithin(target, source)) {
        throw StateError(
          'Windows, isolated root, source, assets and host required',
        );
      }
      final account = await FilePreferences.open(mcdevHome());
      CoreRuntime.preferences = () async => account;
      CoreRuntime.system = 'Windows';
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
        lockPath: p.join(p.dirname(target), 'window-storage.lock'),
      );
      await storage.initialize();
      final game = Directory(p.join(target, 'games', version));
      if (!await game.exists()) {
        await game.parent.create(recursive: true);
        final copy = await Process.run('robocopy', [
          p.join(source, 'games', version),
          game.path,
          '/E',
          '/NFL',
          '/NDL',
          '/NJH',
          '/NJS',
          '/NP',
        ]);
        // Robocopy reports success with any exit code below 8.
        expect(copy.exitCode, lessThan(8));
      }
      final host = NativeDevelopmentLauncher(
        storage,
        preferences,
        sessionId: 'window',
        cookieProvider: () => LoginService.buildCookieHeader(allowCache: false),
      );
      final failures = <String>[];
      try {
        await host.refresh();
        await host.chooseVersion(version);
        host.selectedPacks.clear();
        for (var run = 1; run <= launches; run++) {
          final menuOnly = run.isOdd;
          final lifetime = host.launchTest(
            worldName: '窗口嵌入验证',
            creative: true,
            menuOnly: menuOnly,
          );
          final sampler = await Process.start(
            'powershell.exe',
            ['-NoProfile', '-NonInteractive', '-Command', _sampler],
            environment: {
              'MCDEV_SAMPLE_SECONDS': '45',
              'MCDEV_SAMPLE_GAME': p.join(target, '*'),
              'MCDEV_GAME_HOST': hostExecutable,
            },
          );
          final samples = await sampler.stdout
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())
              .toList();
          final disturbed = await Process.run(
            'powershell.exe',
            ['-NoProfile', '-NonInteractive', '-Command', _disturb],
            environment: {
              'MCDEV_SAMPLE_GAME': p.join(target, '*'),
              'MCDEV_GAME_HOST': hostExecutable,
            },
          );
          await host.stopGame();
          await lifetime;
          final record = Platform.environment['MCDEV_LIVE_WINDOW_SAMPLES'];
          if (record != null) {
            await File(
              p.join(record, 'run-$run.jsonl'),
            ).writeAsString('${samples.join('\n')}\n');
          }
          final handles = <int>{};
          String? firstBad;
          String? previous;
          var embeddedSeen = false;
          final timeline = <String>[];
          for (final line in samples) {
            final space = line.indexOf(' ');
            if (space < 0) continue;
            final sample = jsonDecode(line.substring(space + 1)) as Map;
            final top = sample['top'] as List;
            final embedded = sample['embedded'] as List;
            final hidden = sample['hidden'] as List;
            for (final window in [...top, ...embedded]) {
              handles.add((window as Map)['hwnd'] as int);
            }
            String names(List windows) => windows
                .map((w) => '${(w as Map)['class']}#${w['hwnd']}')
                .join('+');
            final state =
                'frames=${sample['frames']} top=${names(top)} '
                'embedded=${names(embedded)} hidden=${hidden.length}';
            if (state != previous) {
              timeline.add('${line.substring(0, space)}s $state');
              previous = state;
            }
            embeddedSeen |= embedded.isNotEmpty;
            // Before the first embed the game legitimately owns a top-level
            // window. Afterwards any visible top-level game window is a split.
            if (embeddedSeen && top.isNotEmpty) firstBad ??= line;
            if (embeddedSeen && embedded.isEmpty) firstBad ??= line;
          }
          final summary =
              'run $run menu=$menuOnly samples=${samples.length} '
              'embedded=$embeddedSeen handles=${handles.length} '
              'bad=${firstBad ?? '-'}';
          stdout.writeln('WINDOW $summary');
          for (final change in timeline) {
            stdout.writeln('  $change');
          }
          final recovery = disturbed.stdout.toString().trim();
          stdout.writeln('  disturbed: $recovery');
          // The host owns the layout: one second after either change the game
          // must again be its child, below the title bar and full width.
          var recovered = false;
          try {
            final result = jsonDecode(recovery) as Map;
            final before = result['before'] as Map;
            recovered = [result['moved'], result['detached']].every(
              (state) =>
                  (state as Map)['embedded'] == true &&
                  state['top'] == before['top'] &&
                  state['left'] == before['left'] &&
                  state['width'] == before['width'],
            );
          } on FormatException {
            recovered = false;
          }
          if (!embeddedSeen || firstBad != null || !recovered) {
            failures.add('$summary recovered=$recovered');
          }
        }
      } finally {
        host.dispose();
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    },
    skip: Platform.environment['MCDEV_LIVE_WINDOW'] != '1',
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
