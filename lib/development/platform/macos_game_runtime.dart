import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../development_storage.dart';
import '../download_io.dart';
import '../launcher_service.dart' show TestPlayerSkin;
import '../player_skin_io.dart';
import '../wine_patch_io.dart';
import 'game_window_backend.dart';
import 'macos_game_window.dart';
import 'file_game_diagnostics.dart';
import 'game_diagnostics.dart';
import 'development_capabilities.dart';
import 'game_runtime_io.dart';

class MacWineRuntime extends GameRuntime {
  MacWineRuntime(super.storage, super.sessionId);
  @override
  Future<GameDiagnostics> createDiagnostics() async {
    final roamingPath = await roaming();
    return FileGameDiagnostics(
      dataDirectory: p.join(roamingPath, 'MinecraftPE_Netease'),
      crashDirectory: p.join(
        p.dirname(roamingPath),
        'Local',
        'UniSDK',
        'CrashDump',
      ),
    );
  }

  @override
  DevelopmentCapabilities get capabilities => DevelopmentCapabilities.macOS;
  @override
  String get baseRuntime =>
      p.join(storage.paths.runtimes, 'wine-11.0_1-mcs-v1');
  @override
  String get wine => p.join(activeRuntime ?? baseRuntime, 'bin/wine');
  @override
  String get testDirectory => p.join(prefix, 'drive_c', 'MCDevTests');
  @override
  String gamePath(String path) => _winPath(path);
  @override
  String testFilePath(String name) => p.windows.join(r'C:\MCDevTests', name);
  @override
  Future<Map<String, Object>> prepareSkin(
    TestPlayerSkin skin,
    String gameDirectory,
  ) => prepareTestPlayerSkin(
    skin: skin,
    gameDirectory: gameDirectory,
    skinDirectory: p.join(testDirectory, 'skins'),
    gameSkinDirectory: testFilePath('skins'),
  );
  @override
  Future<bool> ready() => patchedWineReady(baseRuntime);
  @override
  Map<String, String> environment({Map<String, String> overrides = const {}}) =>
      _env(prefix, overrides: overrides);
  @override
  Future<void> terminateHelpers() => _killPrefix(prefix);
  @override
  Future<void> install(
    http.Client client,
    DownloadControl? control,
    void Function(StorageMigrationProgress) onProgress,
  ) async {
    if (await patchedWineReady(baseRuntime)) {
      return;
    }
    final archive = File(
      p.join(storage.paths.downloads, 'wine-stable-11.0_1.tar.xz'),
    );
    // University MacPorts archives depend on /opt/local and cannot be used here.
    // Every transport serves the exact same hash-pinned upstream portable asset.
    var downloaded = false;
    for (final url in [
      wineArchiveUrl,
      'https://gh-proxy.com/$wineArchiveUrl',
      'https://ghfast.top/$wineArchiveUrl',
    ]) {
      try {
        await downloadManaged(
          client,
          Uri.parse(url),
          archive,
          expectedSha256: wineArchiveHash,
          control: control,
          onProgress: onProgress,
        );
        downloaded = true;
        break;
      } on DownloadCancelled {
        rethrow;
      } catch (_) {
        control?.check();
      }
    }
    if (!downloaded) {
      throw const DevelopmentStorageException('Wine 下载线路均不可用，请稍后重试。');
    }
    final stage = await Directory(
      storage.paths.runtimes,
    ).createTemp('.wine-install-');
    try {
      onProgress(const StorageMigrationProgress('解压 Wine'));
      final extracted = await Process.run('/usr/bin/tar', [
        '-xJf',
        archive.path,
        '-C',
        stage.path,
      ]);
      if (extracted.exitCode != 0) {
        throw const DevelopmentStorageException('Wine 解压失败。');
      }
      final payload = p.join(
        stage.path,
        'Wine Stable.app',
        'Contents',
        'Resources',
        'wine',
      );
      onProgress(const StorageMigrationProgress('安装启动补丁'));
      await patchWine11(payload);
      control?.check();
      if (await Directory(baseRuntime).exists()) {
        throw const DevelopmentStorageException(
          '已有 Wine 目录校验未通过，请在 Finder 中保留备份后移走该目录再重试。',
        );
      }
      await Directory(payload).rename(baseRuntime);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  Map<String, String> _env(
    String prefix, {
    Map<String, String> overrides = const {},
  }) => {
    ...Platform.environment,
    'WINEPREFIX': prefix,
    'TMPDIR': p.join(storage.paths.prefixes, '.wine_tmp'),
    'WINELOADER': wine,
    'WINEDEBUG': '-all',
    'MVK_CONFIG_LOG_LEVEL': '1',
    'WINEDLLOVERRIDES': 'kerberos=',
    'LC_ALL': 'C',
    ...overrides,
  };

  Future<void> _killPrefix(String prefix) async {
    await Process.run(p.join(p.dirname(wine), 'wineserver'), [
      '-k',
    ], environment: _env(prefix)).timeout(const Duration(seconds: 15));
  }

  Future<ProcessResult> _wineRun(
    String prefix,
    List<String> args, {
    Map<String, String> overrides = const {},
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    await Directory(
      p.join(storage.paths.prefixes, '.wine_tmp'),
    ).create(recursive: true);
    final child = await Process.start(
      wine,
      args,
      environment: _env(prefix, overrides: overrides),
      workingDirectory: workingDirectory,
    );
    // Never persist native SDK/dependency output: it may include account details.
    final drains = [child.stdout.drain<void>(), child.stderr.drain<void>()];
    try {
      final code = await child.exitCode.timeout(timeout);
      await Future.wait(drains).timeout(const Duration(seconds: 15));
      return ProcessResult(child.pid, code, '', '');
    } on TimeoutException {
      child.kill(ProcessSignal.sigterm);
      await _killPrefix(prefix);
      throw const DevelopmentStorageException('Windows 依赖操作超时，请重试；已下载的安装包会保留。');
    }
  }

  @override
  Future<void> prepare(
    void Function(StorageMigrationProgress) onProgress,
  ) async {
    if (!await patchedWineReady(baseRuntime)) {
      throw const DevelopmentStorageException('请先安装 Wine。');
    }
    final supported = await Process.run(wine, ['--version']);
    if (supported.exitCode != 0) {
      throw const DevelopmentStorageException(
        'Wine 无法运行。Apple 芯片 Mac 请先安装 Rosetta 2，再检查运行环境。',
      );
    }
    await Directory(prefix).create(recursive: true);
    if (!await File(p.join(prefix, 'system.reg')).exists()) {
      onProgress(const StorageMigrationProgress('准备 Windows 容器'));
      final result = await _wineRun(
        prefix,
        ['wineboot', '-u'],
        overrides: {'WINEDLLOVERRIDES': 'mscoree,mshtml='},
      );
      if (result.exitCode != 0) {
        throw const DevelopmentStorageException('Windows 容器初始化失败。');
      }
    }
  }

  String _winPath(String path) => 'Z:${p.absolute(path).replaceAll('/', '\\')}';

  @override
  Future<String> roaming() async {
    final users = Directory(p.join(prefix, 'drive_c', 'users'));
    await for (final dir in users.list(followLinks: false)) {
      if (dir is Directory &&
          ![
            'Public',
            'Default',
            'Default User',
            'All Users',
          ].contains(p.basename(dir.path))) {
        return p.join(dir.path, 'AppData', 'Roaming');
      }
    }
    throw const DevelopmentStorageException('Windows 用户目录尚未创建。');
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
    final window = MacGameWindow(
      runtime: activeRuntime ?? baseRuntime,
      runtimes: storage.paths.runtimes,
      metal: activeRuntime != null,
      sessionId: sessionId,
    );
    final decoration = await window.prepare(
      GameWindowRequest(
        executable: executable,
        version: version,
        displayName: displayName,
        renderer: renderer,
        fullscreenShortcut: fullscreenShortcut,
      ),
    );
    return Process.start(
      decoration.loader!,
      [gamePath(executable), ...arguments],
      workingDirectory: workingDirectory,
      environment: environment(
        overrides: {...decoration.environment, ...overrides},
      ),
    );
  }

  @override
  Future<void> stop(Process child) async {
    try {
      // WM_CLOSE first; only this application's isolated prefix is targeted.
      await _wineRun(prefix, [
        'taskkill',
        '/im',
        'Minecraft.Windows.exe',
      ], timeout: const Duration(seconds: 15));
      await child.exitCode.timeout(const Duration(seconds: 20));
      return;
    } catch (_) {
      // Includes a missing wine binary or a disconnected data volume, as well
      // as a timeout. Such failures must not enter an unbounded lifetime wait.
    }
    try {
      await _killPrefix(prefix);
    } catch (_) {
      // The already-created Process remains addressable if its runtime moved.
    }
    try {
      await child.exitCode.timeout(const Duration(seconds: 5));
      return;
    } on TimeoutException {
      child.kill(ProcessSignal.sigterm);
    }
    try {
      await child.exitCode.timeout(const Duration(seconds: 5));
      return;
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
    }
    await child.exitCode.timeout(const Duration(seconds: 5));
  }
}
