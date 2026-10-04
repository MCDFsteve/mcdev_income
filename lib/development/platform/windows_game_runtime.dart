import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../development_storage.dart';
import '../download_io.dart';
import '../launcher_service.dart' show TestPlayerSkin;
import 'development_capabilities.dart';
import 'game_runtime_io.dart';
import 'game_window_backend.dart';
import 'windows_game_window.dart';
import 'file_game_diagnostics.dart';
import 'game_diagnostics.dart';
import 'windows_session_drive.dart';

class WindowsGameRuntime extends GameRuntime {
  WindowsGameRuntime(
    super.storage,
    super.sessionId, {
    GameWindowBackend? window,
  }) : _window = window ?? WindowsGameWindow();
  final GameWindowBackend _window;
  WindowsSessionDrive? _sessionDrive;
  WindowsSessionDrive get _drive {
    if (_sessionDrive?.directory != prefix) {
      _sessionDrive = WindowsSessionDrive(prefix);
    }
    return _sessionDrive!;
  }

  @override
  Future<GameDiagnostics> createDiagnostics() async => CombinedGameDiagnostics(
    FileGameDiagnostics(
      dataDirectory: p.join(await roaming(), 'MinecraftPE_Netease'),
      crashDirectory: p.join(
        profile,
        'AppData',
        'Local',
        'UniSDK',
        'CrashDump',
      ),
    ),
    _window.diagnostics,
  );
  @override
  DevelopmentCapabilities get capabilities => DevelopmentCapabilities.windows;
  @override
  String get baseRuntime => storage.paths.runtimes;
  @override
  String? get wine => null;
  String get profile => p.join(prefix, 'users', 'Developer');
  @override
  String get testDirectory => p.join(prefix, 'MCDevTests');
  @override
  String gamePath(String path) => _drive.translate(path);
  @override
  String testFilePath(String name) => gamePath(p.join(testDirectory, name));
  @override
  Future<Map<String, Object>> prepareSkin(
    TestPlayerSkin skin,
    String gameDirectory,
  ) async => {
    // The native client's packaged-skin API takes a name, not a PNG path.
    // External imports can decode/upload successfully but select Standard.Dummy.
    'skin': skin.name,
    'in_package': true,
    // Omit skin_iid: the -1/-2 import IDs trigger validation of `skin` as a
    // filename, whereas packaged skins obtain their identity from the pack.
  };

  @override
  Future<String> roaming() async => p.join(profile, 'AppData', 'Roaming');
  @override
  Future<bool> ready() async => true;
  @override
  Future<void> install(
    http.Client client,
    DownloadControl? control,
    void Function(StorageMigrationProgress) onProgress,
  ) async {}
  @override
  Map<String, String> environment({Map<String, String> overrides = const {}}) {
    // Remove inherited keys case-insensitively before setting the per-session
    // profile. Windows environment variable names are case-insensitive.
    const replaced = {'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP'};
    return {
      for (final entry in Platform.environment.entries)
        if (!replaced.contains(entry.key.toUpperCase()) &&
            !entry.key.toUpperCase().startsWith('WINE'))
          entry.key: entry.value,
      'USERPROFILE': gamePath(profile),
      'APPDATA': gamePath(p.join(profile, 'AppData', 'Roaming')),
      'LOCALAPPDATA': gamePath(p.join(profile, 'AppData', 'Local')),
      'TEMP': gamePath(p.join(profile, 'Temp')),
      'TMP': gamePath(p.join(profile, 'Temp')),
      ...overrides,
    };
  }

  @override
  Future<void> prepare(
    void Function(StorageMigrationProgress) onProgress,
  ) async {
    final oldProfile = Directory(p.join(prefix, 'profile'));
    if (await oldProfile.exists()) {
      if (await Directory(profile).exists()) {
        throw const FileSystemException('测试容器中同时存在新旧用户目录，请先检查存档位置');
      }
      await Directory(p.dirname(profile)).create(recursive: true);
      await oldProfile.rename(profile);
    }
    for (final path in [
      await roaming(),
      p.join(profile, 'AppData', 'Local'),
      p.join(profile, 'Temp'),
      testDirectory,
    ]) {
      await Directory(path).create(recursive: true);
    }
    await _drive.mount();
  }

  @override
  Future<Process> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required String version,
    required String displayName,
    required String renderer,
    required bool fullscreenShortcut,
    Map<String, String> overrides = const {},
  }) async {
    final request = GameWindowRequest(
      executable: executable,
      version: version,
      displayName: displayName,
      renderer: renderer,
      fullscreenShortcut: fullscreenShortcut,
    );
    final decoration = await _window.prepare(request);
    final child = await Process.start(
      decoration.loader ?? executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment(
        overrides: {...decoration.environment, ...overrides},
      ),
    );
    try {
      await _window.attach(child, request);
      return child;
    } catch (_) {
      child.kill();
      await _window.close();
      await _drive.unmount();
      rethrow;
    }
  }

  @override
  Future<void> terminateHelpers() async {
    await _window.close();
    await _drive.unmount();
  }

  @override
  Future<void> stop(Process child) async {
    try {
      await child.exitCode.timeout(Duration.zero);
      return;
    } on TimeoutException {
      /* The owned process is still alive. */
    }
    try {
      if (await _window.requestClose()) {
        await child.exitCode.timeout(const Duration(seconds: 25));
        return;
      }
      // Address the Process we own, never every Minecraft window by name.
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-Process -Id ${child.pid} -ErrorAction SilentlyContinue).CloseMainWindow() | Out-Null',
      ]).timeout(const Duration(seconds: 5));
      await child.exitCode.timeout(const Duration(seconds: 20));
      return;
    } catch (_) {
      child.kill();
    }
    await child.exitCode.timeout(const Duration(seconds: 5));
  }
}
