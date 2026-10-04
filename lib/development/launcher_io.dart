import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/preferences.dart';
import '../storage/file_lock.dart';
import '../logging/app_logger.dart' as app_logger;
import 'development_storage.dart';
import 'download_io.dart';
import 'game_archive_io.dart';
export 'game_archive_io.dart';
import 'launcher_service.dart';
import 'mcs_api.dart';
import 'performance_patch_io.dart';
import 'game_graphics.dart';
import 'render_dragon.dart';
import 'render_dragon_io.dart';
import 'test_world_io.dart';
import 'session_preferences.dart';
import 'test_session_io.dart';
import 'lan_rpc_io.dart';
import 'lan_bridge_io.dart';
import 'lan_endpoint_io.dart';
import 'lan_join_io.dart';
import 'lan_patch_io.dart';
import 'mod_log_io.dart';
import 'mod_log_filter.dart';
import 'mod_log_capture_io.dart';
import 'platform/development_capabilities.dart';
import 'platform/game_runtime_io.dart';
import 'platform/runtime_factory_io.dart';
import 'platform/host_files_io.dart';
import 'platform/game_diagnostics.dart' show classifyNativeDiagnostic;
import 'mod_manifest_io.dart';
import 'python_reload_io.dart';

Future<DevelopmentLauncher> openDevelopmentLauncher(
  DevelopmentStorage storage,
  PreferenceStore preferences, {
  Future<String> Function()? cookieProvider,
  String sessionId = 'default',
}) async {
  final launcher = NativeDevelopmentLauncher(
    storage,
    preferences,
    cookieProvider: cookieProvider,
    sessionId: sessionId,
  );
  await launcher.refresh();
  return launcher;
}

/// No game or Wine is an application asset. Their installations are versioned
/// and committed only after verification, leaving previous installations usable.
class NativeDevelopmentLauncher extends DevelopmentLauncher {
  NativeDevelopmentLauncher(
    this.storage,
    PreferenceStore preferences, {
    this.sessionId = 'default',
    http.Client? client,
    GameRuntime? runtimeBackend,
    Future<String> Function()? cookieProvider,
  }) : preferences = TestSessionPreferences(preferences, sessionId),
       api = McsApi(client: client),
       _cookieProvider = cookieProvider ?? (() async => '') {
    _runtime = runtimeBackend ?? createGameRuntime(storage, sessionId);
    selectedVersion = this.preferences.getString(_versionKey);
    performanceOptimization = this.preferences.getInt(_performanceKey) != 0;
    limit60Fps = this.preferences.getInt(_frameLimitKey) != 0;
    showDeveloperConsole = this.preferences.getInt(_developerConsoleKey) == 1;
    disableCompanion = this.preferences.getInt(_disableCompanionKey) != 0;
    fullscreenShortcut = this.preferences.getInt(_fullscreenShortcutKey) == 1;
    useNewWorld = this.preferences.getInt(_newWorldKey) == 1;
    newWorldSeed = this.preferences.getString(_worldSeedKey) ?? '';
    projectSortOrder =
        ProjectSortOrder.values
            .where(
              (value) =>
                  value.name == this.preferences.getString(_projectSortKey),
            )
            .firstOrNull ??
        ProjectSortOrder.importedNewest;
    playerSkin =
        TestPlayerSkin.values
            .where(
              (value) =>
                  value.name == this.preferences.getString(_playerSkinKey),
            )
            .firstOrNull ??
        TestPlayerSkin.steve;
    _restoreRenderer();
  }
  late final GameRuntime _runtime;
  @override
  DevelopmentCapabilities get capabilities => _runtime.capabilities;
  final Future<String> Function() _cookieProvider;
  String? _accountFingerprint;
  final DevelopmentStorage storage;
  final String sessionId;
  Future<void>? _launchCompletion;
  final PreferenceStore preferences;
  final McsApi api;
  static const _versionKey = 'development_game_version_v1';
  static const _performanceKey = 'development_performance_patch_v1';
  static const _frameLimitKey = 'development_frame_limit_60_v1';
  static const _developerConsoleKey = 'development_show_developer_console_v1';
  static const _disableCompanionKey = 'development_disable_companion_v1';
  static const _fullscreenShortcutKey = 'development_fullscreen_shortcut_v1';
  static const _playerSkinKey = 'development_player_skin_v1';
  static const _newWorldKey = 'development_new_world_v1';
  static const _worldSeedKey = 'development_world_seed_v1';
  static const _selectionKey = 'development_selected_packs_v1';
  static const _projectSortKey = 'development_project_sort_v1';
  String get _rendererKey => 'development_renderer_v1_$selectedVersion';
  String get _vibrantKey => 'development_vibrant_visuals_v1_$selectedVersion';

  void _restoreRenderer() {
    renderer =
        GameRenderer.values
            .where((value) => value.name == preferences.getString(_rendererKey))
            .firstOrNull ??
        GameRenderer.openGL;
    vibrantVisuals = preferences.getInt(_vibrantKey) == 1;
  }

  @override
  Future<void> chooseProjectSortOrder(ProjectSortOrder value) async {
    if (!await preferences.setString(_projectSortKey, value.name)) {
      throw const DevelopmentStorageException('无法保存项目排序方式。');
    }
    projectSortOrder = value;
    _notify();
  }

  bool _disposed = false;
  DownloadControl? _control;
  Process? _game;
  bool _stopRequested = false;
  bool _stopping = false;
  LanGameRpc? _rpc;
  LanRosterBridge? _lanBridge;
  Timer? _lanTimer;
  int _launchGeneration = 0;
  int? _pollingLanGeneration;
  int? _lanPort;
  DateTime? _lanPortChecked;
  int? _requestedLanPort;
  bool _closingLan = false;
  bool _hasLanPlayers = false;
  bool _hostEverJoined = false;
  bool _lanTransportReady = false;
  int _hostId = 0;
  String _hostWorldName = '';
  String? _hostPackRoot;
  String _roomToken = '';
  DateTime? _rosterUpdated;
  int _rosterSequence = -1;
  String? _rosterEpoch;
  List<LanRosterPlayer> _worldPlayers = [];
  final Map<String, _LanGuest> _lanGuests = {};
  _LanJoinTarget? _joinTarget;
  String _playerName = 'Developer';
  TestPlayerSkin _hostSkin = TestPlayerSkin.steve;
  PythonReloadSession? _pythonReloadSession;
  PythonReloadBridge? _pythonReloadBridge;
  Timer? _pythonReloadTimer;
  Completer<void>? _pythonReloadFinished;
  bool _pythonReloadNeedsRestart = false;
  bool _pythonReloadApplied = false;
  String? _pythonReloadFailure;
  bool get _reloadHasGuests =>
      _worldPlayers.length > 1 ||
      _lanGuests.values.any((guest) => !guest.finished);

  @override
  bool get pythonReloadAvailable =>
      running &&
      !busy &&
      !pythonReloadBusy &&
      !_stopRequested &&
      !_stopping &&
      !_pythonReloadNeedsRestart &&
      _joinTarget == null &&
      !_reloadHasGuests &&
      _pythonReloadSession?.hasScripts == true &&
      _pythonReloadBridge?.ready == true;

  @override
  String get pythonReloadUnavailableReason {
    if (selectedVersion != pythonReloadVersion) {
      return 'Python 热重载目前支持 3.10.0.420447。';
    }
    if (!running) return '启动测试世界后可重载已启用项目的 Python。';
    if (_pythonReloadNeedsRestart) return '上次重载未完整完成，请重新启动测试游戏。';
    if (_pythonReloadFailure != null) return _pythonReloadFailure!;
    if (_reloadHasGuests) return '请先退出局域网玩家，再重载 Python。';
    if (_pythonReloadSession?.hasScripts != true) {
      return '本次测试没有可重载的 Python 源码。';
    }
    if (pythonReloadBusy) return '正在重载 Python…';
    return '请等待世界加载完成；游戏暂停时请先返回游戏。';
  }

  @override
  Future<void> reloadPython() async {
    if (!pythonReloadAvailable) {
      throw DevelopmentStorageException(pythonReloadUnavailableReason);
    }
    final generation = _launchGeneration;
    final bridge = _pythonReloadBridge!;
    final epoch = bridge.epoch!;
    final session = _pythonReloadSession!;
    void checkCurrent() {
      if (!running ||
          _stopRequested ||
          _stopping ||
          generation != _launchGeneration ||
          !identical(bridge, _pythonReloadBridge) ||
          bridge.epoch != epoch) {
        throw const DevelopmentStorageException('测试世界已退出或变化，已停止热重载。');
      }
    }

    pythonReloadBusy = true;
    final finished = Completer<void>();
    _pythonReloadFinished = finished;
    error = null;
    notice = '正在检查 Python 修改…';
    _notify();
    PythonReloadChanges? changes;
    var applying = false;
    try {
      changes = await session.changes();
      checkCurrent();
      if (changes.isEmpty) {
        notice = 'Python 源码没有变化。';
        return;
      }
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final files = changes.requestFiles(_winPath);
      final validation = await bridge.request(
        id: id,
        operation: 'validate',
        worldEpoch: epoch,
        files: files,
        checkCurrent: checkCurrent,
      );
      if (validation['ok'] != true) {
        await _pythonReloadLog(
          '[ERROR] Python 语法检查失败：\n${validation['error']}',
        );
        throw const DevelopmentStorageException('Python 语法检查失败，游戏逻辑未更新；请查看日志。');
      }
      await changes.stage(checkCurrent);
      notice = '正在应用 ${changes.count} 个 Python 文件…';
      _notify();
      applying = true;
      final result = await bridge.request(
        id: id,
        operation: 'apply',
        worldEpoch: epoch,
        files: files,
        checkCurrent: checkCurrent,
      );
      checkCurrent();
      if (result['ok'] != true) {
        await _pythonReloadLog('[ERROR] Python 热重载失败：\n${result['error']}');
        throw const DevelopmentStorageException('Python 执行失败，请查看日志并重新启动测试。');
      }
      changes.commit();
      _pythonReloadApplied = true;
      notice =
          'Python 热重载完成：${result['reloaded']} 个模块已更新'
          '${result['deferred'] == 0 ? '。' : '，${result['deferred']} 个新模块将在导入时加载。'}';
      await _pythonReloadLog('[INFO] $notice');
    } catch (e) {
      if (applying &&
          generation == _launchGeneration &&
          identical(bridge, _pythonReloadBridge)) {
        _pythonReloadNeedsRestart = true;
      } else if (!applying) {
        await changes?.rollback();
      }
      if (generation == _launchGeneration) {
        error = e is TimeoutException && applying
            ? 'Python 重载未收到完成确认，请查看日志并重新启动测试。'
            : e.toString();
        notice = null;
      }
    } finally {
      if (generation == _launchGeneration) pythonReloadBusy = false;
      finished.complete();
      if (identical(_pythonReloadFinished, finished)) {
        _pythonReloadFinished = null;
      }
      _notify();
    }
  }

  void Function(String)? _writePythonReloadLog;
  Future<void> _pythonReloadLog(String message) async =>
      _writePythonReloadLog?.call('$message\n');

  @override
  String get gameDisplayName => _joinTarget == null
      ? super.gameDisplayName
      : '${super.gameDisplayName} · $_playerName';

  @override
  bool get lanAvailable =>
      running &&
      _joinTarget == null &&
      !pythonReloadBusy &&
      !_pythonReloadApplied &&
      !_closingLan &&
      _lanTransportReady &&
      _lanBridge != null &&
      _hostPackRoot != null &&
      _lanPort != null &&
      _rosterUpdated != null &&
      DateTime.now().difference(_rosterUpdated!).inSeconds < 10 &&
      _worldPlayers.isNotEmpty;
  @override
  String get lanUnavailableReason => _pythonReloadApplied
      ? 'Python 热重载后，请重新启动测试再添加局域网玩家。'
      : !supportsLanPatch(selectedVersion ?? '')
      ? '当前游戏版本尚未适配局域网测试，请选择 3.10.0.420447。'
      : '请等待此测试页的世界加载完成。';

  @override
  bool get hasLanPlayers => _hasLanPlayers || _worldPlayers.length > 1;
  @override
  List<DevelopmentPlayer> get players {
    final claimed = <String>{};
    bool inWorld(String name) {
      final match = _worldPlayers
          .where(
            (player) => player.name == name && !claimed.contains(player.id),
          )
          .firstOrNull;
      if (match == null) return false;
      claimed.add(match.id);
      return true;
    }

    final result = <DevelopmentPlayer>[];
    if (running || _hasLanPlayers) {
      result.add(
        DevelopmentPlayer(
          id: 'host',
          name: _playerName,
          skin: _hostSkin,
          host: true,
          status: running && inWorld(_playerName)
              ? DevelopmentPlayerStatus.connected
              : !running || _hostEverJoined
              ? DevelopmentPlayerStatus.disconnected
              : DevelopmentPlayerStatus.starting,
        ),
      );
    }
    for (final guest in _lanGuests.values) {
      final connected = !guest.finished && inWorld(guest.name);
      result.add(
        DevelopmentPlayer(
          id: guest.id,
          name: guest.name,
          skin: guest.skin,
          host: false,
          canStop: !guest.finished,
          status: guest.failure != null
              ? DevelopmentPlayerStatus.failed
              : guest.finished
              ? DevelopmentPlayerStatus.disconnected
              : connected
              ? DevelopmentPlayerStatus.connected
              : guest.everJoined
              ? DevelopmentPlayerStatus.disconnected
              : DevelopmentPlayerStatus.starting,
          error: guest.failure,
        ),
      );
    }
    for (final player in _worldPlayers) {
      if (claimed.contains(player.id)) continue;
      result.add(
        DevelopmentPlayer(
          id: 'external:${player.id}',
          name: player.name,
          host: false,
          status: DevelopmentPlayerStatus.connected,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  @override
  Future<void> launchLanPlayer({
    required String name,
    required TestPlayerSkin skin,
  }) async {
    final invalid = validateDevelopmentPlayerName(name);
    if (invalid != null) throw DevelopmentStorageException(invalid);
    name = name.trim();
    if (!lanAvailable) {
      throw DevelopmentStorageException(lanUnavailableReason);
    }
    if (name == _playerName ||
        _worldPlayers.any((player) => player.name == name) ||
        _lanGuests.values.any((p) => !p.finished && p.name == name)) {
      throw const DevelopmentStorageException('这个玩家名字已经在当前世界使用，请换一个名字。');
    }
    var slot = 1;
    final prefix = sha256
        .convert(utf8.encode(sessionId))
        .toString()
        .substring(0, 16);
    while (_lanGuests['lan-$prefix-$slot']?.finished == false) {
      slot++;
    }
    final id = 'lan-$prefix-$slot';
    final old = _lanGuests[id];
    old?.launcher.dispose();
    final child = NativeDevelopmentLauncher(
      storage,
      (preferences as TestSessionPreferences).store,
      sessionId: id,
      cookieProvider: _cookieProvider,
    );
    child
      ..games = List.of(games)
      ..packs = List.of(packs)
      ..catalog = catalog
      ..selectedVersion = selectedVersion
      ..runtimeReady = runtimeReady
      ..renderer = renderer
      ..performanceOptimization = performanceOptimization
      ..limit60Fps = limit60Fps
      ..vibrantVisuals = vibrantVisuals
      ..showDeveloperConsole = showDeveloperConsole
      ..disableCompanion = disableCompanion
      ..fullscreenShortcut = fullscreenShortcut
      ..playerSkin = skin
      ..useNewWorld = false
      .._playerName = name
      .._accountFingerprint = _accountFingerprint;
    child.selectedPacks.addAll(selectedPacks);
    child.api
      ..session = api.session
      ..web = api.web;
    final token = _roomToken;
    final epoch = _rosterEpoch;
    final port = _lanPort!;
    final hostProcess = _game!;
    final hostBridge = _lanBridge!;
    child._joinTarget = _LanJoinTarget(
      port,
      hostProcess.pid,
      _hostId,
      _hostWorldName,
      token,
      _hostPackRoot!,
      hostBridge,
      () =>
          !_disposed &&
          running &&
          !_closingLan &&
          identical(_game, hostProcess) &&
          identical(_lanBridge, hostBridge) &&
          _roomToken == token &&
          _rosterEpoch == epoch,
      () =>
          _rosterUpdated != null &&
          DateTime.now().difference(_rosterUpdated!).inSeconds < 10 &&
          _worldPlayers.isNotEmpty,
      _pollLan,
    );
    final guest = _LanGuest(id, name, skin, child);
    _lanGuests[id] = guest;
    _hasLanPlayers = true;
    child.addListener(_notify);
    _notify();
    final launched = child.launchTest(
      worldName: _hostWorldName,
      creative: true,
      menuOnly: false,
    );
    unawaited(
      launched.then<void>(
        (_) {
          guest.finished = true;
          guest.failure = child.error;
          child.removeListener(_notify);
          _notify();
        },
        onError: (Object e, StackTrace _) {
          guest.finished = true;
          guest.failure = e.toString();
          child.removeListener(_notify);
          _notify();
        },
      ),
    );
  }

  @override
  Future<void> stopLanPlayer(String id) async {
    final guest = _lanGuests[id];
    if (guest == null || guest.finished) return;
    guest.launcher.cancel();
    await guest.launcher.stopGame();
  }

  Future<void> _stopLanGuests() async {
    _closingLan = true;
    _notify();
    await Future.wait(
      _lanGuests.values
          .where((g) => !g.finished)
          .map((g) => stopLanPlayer(g.id)),
    );
  }

  Future<void> _pollLan() async {
    final generation = _launchGeneration;
    final game = _game;
    final bridge = _lanBridge;
    bool current() =>
        !_disposed &&
        generation == _launchGeneration &&
        game != null &&
        identical(game, _game) &&
        identical(bridge, _lanBridge) &&
        running &&
        !_closingLan;
    if (_pollingLanGeneration == generation ||
        !current() ||
        _joinTarget != null) {
      return;
    }
    _pollingLanGeneration = generation;
    try {
      final report = await bridge?.readReport();
      if (!current()) return;
      if (report != null && report.epoch != _rosterEpoch) {
        _rosterEpoch = report.epoch;
        _rosterSequence = -1;
        _lanPort = null;
        _lanPortChecked = null;
      }
      if (report != null && report.ready && report.sequence > _rosterSequence) {
        _rosterSequence = report.sequence;
        _rosterUpdated = DateTime.now();
        _worldPlayers = report.players;
        if (_worldPlayers.any((player) => player.name == _playerName)) {
          if (!_hostEverJoined) notice = '测试世界已加载。';
          _hostEverJoined = true;
        }
        for (final guest in _lanGuests.values) {
          if (_worldPlayers.any((player) => player.name == guest.name)) {
            guest.everJoined = true;
          }
        }
      }
      if (_worldPlayers.isNotEmpty &&
          (_lanPortChecked == null ||
              DateTime.now().difference(_lanPortChecked!).inSeconds >= 5)) {
        // Recent Bedrock builds choose their own ephemeral hosting port and
        // omit the legacy RPC launch reply. Inspect only this exact process.
        final endpoint = await discoverLanEndpointForProcess(game!.pid);
        if (!current()) return;
        _lanPort = endpoint?.port;
        _lanPortChecked = DateTime.now();
      }
      if (_rosterUpdated != null &&
          DateTime.now().difference(_rosterUpdated!).inSeconds >= 10) {
        _worldPlayers = [];
      }
      _notify();
    } catch (_) {
      // A disappearing prefix or a transient UDP failure must not escape an
      // unawaited timer callback. Require a fresh world report before joining.
      if (current()) {
        _worldPlayers = [];
        _rosterUpdated = null;
        _notify();
      }
    } finally {
      if (_pollingLanGeneration == generation) _pollingLanGeneration = null;
    }
  }

  String get runtime => _runtime.baseRuntime;
  String? get wine => _runtime.wine;
  String get gamePrefix => _runtime.prefix;
  String get _lock => storage.lockPath;
  String get _projectsFile => p.join(storage.paths.root, 'projects.json');
  @override
  Future<void> chooseNewWorld(bool enabled) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后修改存档设置。');
    }
    if (!await preferences.setInt(_newWorldKey, enabled ? 1 : 0)) {
      throw const DevelopmentStorageException('无法保存存档设置。');
    }
    useNewWorld = enabled;
    _notify();
  }

  @override
  Future<void> choosePerformanceOptimization(bool enabled) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后修改性能优化设置。');
    }
    if (!await preferences.setInt(_performanceKey, enabled ? 1 : 0)) {
      throw const DevelopmentStorageException('无法保存性能优化设置。');
    }
    performanceOptimization = enabled;
    _notify();
  }

  @override
  Future<void> chooseFrameLimit(bool enabled) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后修改帧率上限。');
    }
    if (!await preferences.setInt(_frameLimitKey, enabled ? 1 : 0)) {
      throw const DevelopmentStorageException('无法保存帧率上限。');
    }
    limit60Fps = enabled;
    _notify();
  }

  @override
  Future<void> chooseDeveloperConsole(bool enabled) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后修改开发控制台设置。');
    }
    if (!await preferences.setInt(_developerConsoleKey, enabled ? 1 : 0)) {
      throw const DevelopmentStorageException('无法保存开发控制台设置。');
    }
    showDeveloperConsole = enabled;
    _notify();
  }

  @override
  Future<void> choosePlayerSkin(TestPlayerSkin value) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后修改玩家皮肤。');
    }
    if (!await preferences.setString(_playerSkinKey, value.name)) {
      throw const DevelopmentStorageException('无法保存玩家皮肤选择。');
    }
    playerSkin = value;
    _notify();
  }

  @override
  Future<void> chooseDisableCompanion(bool disabled) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后修改我的伙伴设置。');
    }
    if (!await preferences.setInt(_disableCompanionKey, disabled ? 1 : 0)) {
      throw const DevelopmentStorageException('无法保存我的伙伴设置。');
    }
    disableCompanion = disabled;
    _notify();
  }

  @override
  Future<void> chooseFullscreenShortcut(bool enabled) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后修改全屏快捷键设置。');
    }
    if (!await preferences.setInt(_fullscreenShortcutKey, enabled ? 1 : 0)) {
      throw const DevelopmentStorageException('无法保存全屏快捷键设置。');
    }
    fullscreenShortcut = enabled;
    _notify();
  }

  @override
  Future<void> chooseRenderer(GameRenderer value) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后切换渲染器。');
    }
    if (!rendererSwitchSupported) {
      throw const DevelopmentStorageException('此游戏版本不支持切换渲染器，请选择 3.9 或更新版本。');
    }
    if (!await preferences.setString(_rendererKey, value.name)) {
      throw const DevelopmentStorageException('无法保存渲染器选择。');
    }
    renderer = value;
    _notify();
  }

  @override
  Future<void> chooseVibrantVisuals(bool enabled) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请在游戏退出后切换灵动视效。');
    }
    if (!vibrantVisualsSupported) {
      throw const DevelopmentStorageException('灵动视效适配需要 3.10.0.420447 的渲染龙。');
    }
    if (!await preferences.setInt(_vibrantKey, enabled ? 1 : 0)) {
      throw const DevelopmentStorageException('无法保存灵动视效设置。');
    }
    vibrantVisuals = enabled;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _update(StorageMigrationProgress value) {
    progress = value;
    _notify();
  }

  Future<void> _requireStorage() async {
    if (!(await storage.inspect()).initialized) {
      throw const DevelopmentStorageException('请先配置可用的开发数据目录。');
    }
  }

  Future<void> _operation(
    Future<void> Function() action, {
    bool sharedLock = true,
  }) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请等待当前任务完成或退出测试游戏。');
    }
    busy = true;
    error = null;
    notice = null;
    _control = DownloadControl();
    _notify();
    try {
      Future<void> work() async {
        await _requireStorage();
        await action();
      }

      if (sharedLock) {
        await withFileLock(_lock, work);
      } else {
        await work();
      }
    } on DownloadCancelled {
      notice = '下载已暂停，重试时会继续。';
    } on FileSystemException catch (e, stack) {
      final phase = progress?.message ?? '开发操作';
      app_logger.error('$phase：文件操作失败', e, stack);
      error =
          '$phase失败：${e.osError?.message ?? e.message}'
          '${e.osError == null ? '' : '（系统错误 ${e.osError!.errorCode}）'}'
          '${e.path == null ? '' : '\n${e.path}'}';
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      progress = null;
      _control = null;
      if (_disposed) api.close();
      _notify();
    }
  }

  Future<void> _saveJson(File file, Object value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp-${Random.secure().nextInt(1 << 30)}');
    try {
      await temp.writeAsString(jsonEncode(value), flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> refresh() async {
    if (running) return;
    await _requireStorage();
    await _refreshAccount();
    runtimeReady = await _runtime.ready();
    final installed = <LocalGame>[];
    await for (final dir in Directory(
      storage.paths.games,
    ).list(followLinks: false)) {
      if (dir is! Directory || p.basename(dir.path).startsWith('.')) continue;
      if (await File(p.join(dir.path, 'Minecraft.Windows.exe')).exists() &&
          await File(p.join(dir.path, '.mcdev-game.json')).exists()) {
        final metadata = jsonDecode(
          await File(p.join(dir.path, '.mcdev-game.json')).readAsString(),
        );
        installed.add(
          LocalGame(
            p.basename(dir.path),
            dir.path,
            architecture:
                GameArchitecture.values
                    .where((value) => value.name == metadata['architecture'])
                    .firstOrNull ??
                GameArchitecture.unknown,
            channels: [
              for (final value in GameChannel.values)
                if (metadata['channels'] is List &&
                    (metadata['channels'] as List).contains(value.name))
                  value,
            ],
            clientType:
                GameClientType.values
                    .where((value) => value.name == metadata['client_type'])
                    .firstOrNull ??
                GameClientType.openGL,
          ),
        );
      }
    }
    installed.sort((a, b) => compareGameVersions(b.version, a.version));
    games = installed;
    if (!games.any((g) => g.version == selectedVersion)) {
      selectedVersion = games.isEmpty ? null : games.first.version;
      if (selectedVersion != null &&
          !await preferences.setString(_versionKey, selectedVersion!)) {
        throw const DevelopmentStorageException('无法保存游戏版本选择。');
      }
    }
    _restoreRenderer();
    await _readProjects();
    _notify();
  }

  Future<void> _readProjects() async {
    final manifest = File(_projectsFile);
    final type = await FileSystemEntity.type(manifest.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const DevelopmentStorageException('项目注册文件无法读取。');
    }
    final loaded = <ModPack>[];
    final selected = <String>{};
    if (await manifest.exists()) {
      for (final row in jsonDecode(await manifest.readAsString()) as List) {
        if (row['selected'] == true) {
          selected.add(row['uuid']);
        }
        final directory = _expandProject(row['path']);
        loaded.add(
          ModPack(
            name: await _readModPackTitle(directory, row['name']),
            uuid: row['uuid'],
            version: (row['version'] as List).cast<int>(),
            type: row['type'],
            directory: directory,
            projectRoot: row['projectRoot'] is String
                ? _expandProject(row['projectRoot'])
                : null,
            importedAt: DateTime.tryParse(row['importedAt']?.toString() ?? ''),
            lastLaunchedAt: DateTime.tryParse(
              row['lastLaunchedAt']?.toString() ?? '',
            ),
          ),
        );
      }
    }
    // Another tab may be opened before the legacy tab. Preserve its old
    // selection before any shared registry writer drops the legacy flags.
    final originalPreferences = (preferences as TestSessionPreferences).store;
    if (originalPreferences.getString(_selectionKey) == null &&
        !await originalPreferences.setString(
          _selectionKey,
          jsonEncode(selected.toList()),
        )) {
      throw const DevelopmentStorageException('无法迁移原测试页的项目选择。');
    }
    if (sessionId != 'default') selected.clear();
    final savedSelection = preferences.getString(_selectionKey);
    if (savedSelection != null) {
      selected
        ..clear()
        ..addAll((jsonDecode(savedSelection) as List).whereType<String>());
    } else if (!await preferences.setString(
      _selectionKey,
      jsonEncode(selected.toList()),
    )) {
      throw const DevelopmentStorageException('无法保存项目选择。');
    }
    packs = loaded;
    selectedPacks
      ..clear()
      ..addAll(
        selected.where((uuid) => packs.any((pack) => pack.uuid == uuid)),
      );
  }

  Future<void> _saveSelection() async {
    if (!await preferences.setString(
      _selectionKey,
      jsonEncode(selectedPacks.toList()),
    )) {
      throw const DevelopmentStorageException('无法保存项目选择。');
    }
  }

  String _expandProject(String value) =>
      p.isAbsolute(value) ? value : p.join(storage.paths.root, value);
  Future<void> _saveProjects() => _saveJson(File(_projectsFile), [
    for (final pack in packs)
      {
        'name': pack.name,
        'uuid': pack.uuid,
        'version': pack.version,
        'type': pack.type,
        if (pack.importedAt != null)
          'importedAt': pack.importedAt!.toUtc().toIso8601String(),
        if (pack.lastLaunchedAt != null)
          'lastLaunchedAt': pack.lastLaunchedAt!.toUtc().toIso8601String(),
        'path': p.isWithin(storage.paths.root, pack.directory)
            ? p.relative(pack.directory, from: storage.paths.root)
            : pack.directory,
        if (pack.projectRoot != null)
          'projectRoot': p.isWithin(storage.paths.root, pack.projectRoot!)
              ? p.relative(pack.projectRoot!, from: storage.paths.root)
              : pack.projectRoot,
      },
  ]);

  // Called while startup still owns the shared preparation lock. Reload first
  // so another tab's imports or launch history are never overwritten.
  Future<void> _recordProjectLaunch(
    Iterable<String> uuids,
    DateTime time,
  ) async {
    final ids = uuids.toSet();
    if (ids.isEmpty) return;
    await _readProjects();
    final previous = packs;
    packs = [
      for (final pack in packs)
        if (ids.contains(pack.uuid)) pack.withLastLaunch(time) else pack,
    ];
    try {
      await _saveProjects();
    } catch (_) {
      packs = previous;
      rethrow;
    }
  }

  @override
  Future<void> chooseVersion(String version) => _operation(() async {
    if (!games.any((game) => game.version == version)) {
      throw const DevelopmentStorageException('所选游戏版本不可用。');
    }
    if (!await preferences.setString(_versionKey, version)) {
      throw const DevelopmentStorageException('无法保存游戏版本选择。');
    }
    selectedVersion = version;
    _restoreRenderer();
  });

  @override
  Future<void> togglePacks(Iterable<String> uuids, bool selected) =>
      _operation(() async {
        await _readProjects();
        final previous = {...selectedPacks};
        final known = uuids
            .where((uuid) => packs.any((pack) => pack.uuid == uuid))
            .toList();
        selected ? selectedPacks.addAll(known) : selectedPacks.removeAll(known);
        try {
          await _saveSelection();
        } catch (_) {
          selectedPacks
            ..clear()
            ..addAll(previous);
          rethrow;
        }
      });

  Future<String> _refreshAccount() async {
    final cookie = await _cookieProvider();
    final fingerprint = sha256.convert(utf8.encode(cookie)).toString();
    if (fingerprint != _accountFingerprint) {
      api.session = null;
      catalog = null;
      _accountFingerprint = fingerprint;
    }
    loggedIn = cookie.isNotEmpty;
    return cookie;
  }

  Future<void> _connectAccount() async {
    final cookie = await _refreshAccount();
    final expiry = api.session?.expiresAt ?? 0;
    if (api.session == null ||
        expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60) {
      _update(const StorageMigrationProgress('验证现有开发者登录'));
      await api.authenticateDeveloper(cookie);
    }
  }

  @override
  Future<void> installWine() => _operation(() async {
    await _runtime.install(api.client, _control, _update);
    runtimeReady = await _runtime.ready();
    notice = capabilities.requiresWine
        ? 'Wine 与启动补丁已就绪。'
        : 'Windows 原生运行环境已就绪。';
  });
  Map<String, String> _env(
    String prefix, {
    Map<String, String> overrides = const {},
  }) => _runtime.environment(overrides: overrides);
  String _winPath(String path) => _runtime.gamePath(path);

  Future<void> _loadCatalog() async {
    await _connectAccount();
    _update(const StorageMigrationProgress('查询可下载的游戏版本'));
    catalog = await api.catalog();
  }

  @override
  Future<void> queryLatest() => queryVersions();

  @override
  Future<void> queryVersions() => _operation(() async {
    await _loadCatalog();
    notice = '已获取 ${availableGames.length} 个可下载版本。';
  });

  @override
  Future<void> installLatest() => _operation(() async {
    await _loadCatalog();
    final package = catalog!.stable;
    if (package == null) {
      throw const DevelopmentStorageException('官方稳定版下载描述缺失。');
    }
    await _installPackage(package);
  });

  @override
  Future<void> installVersion(String version) => _operation(() async {
    // Refresh the official entry and download exactly the user's choice. Never
    // silently substitute stable when a preview or historical entry disappears.
    await _loadCatalog();
    final package = availableGames
        .where((package) => package.version == version)
        .firstOrNull;
    if (package == null) {
      throw const DevelopmentStorageException('该版本已不在官方清单中，请刷新版本列表。');
    }
    await _installPackage(package);
  });

  Future<void> _installPackage(GamePackage package) async {
    final destination = Directory(p.join(storage.paths.games, package.version));
    if (await File(p.join(destination.path, '.mcdev-game.json')).exists()) {
      await refresh();
      notice = '该游戏版本已安装，可在启动区切换使用。';
      return;
    }
    final patchFile = File(
      p.join(storage.paths.downloads, '${package.version}-patch.json'),
    );
    await downloadManaged(
      api.client,
      signMcsDownload(package.patchUrl),
      patchFile,
      expectedMd5: package.patchMd5,
      control: _control,
      onProgress: _update,
    );
    final patch = await patchFile.readAsString();
    final hashes = parseGamePatch(patch);
    if (await destination.exists()) {
      throw const DevelopmentStorageException('目标游戏目录已有未完成的数据，请保留备份后移走该目录再重试。');
    }
    final zip = File(
      p.join(storage.paths.downloads, 'minecraft-${package.version}.zip'),
    );
    await downloadManaged(
      api.client,
      signMcsDownload(package.zipUrl),
      zip,
      reuseCompleted: true,
      control: _control,
      onProgress: _update,
    );
    final stage = await Directory(
      storage.paths.games,
    ).createTemp('.game-install-');
    try {
      try {
        _update(const StorageMigrationProgress('解压游戏包'));
        final input = InputFileStream(zip.path);
        try {
          await extractGameZipSafe(
            ZipDecoder().decodeStream(input),
            stage.path,
            control: _control,
            onProgress: _update,
          );
        } finally {
          await input.close();
        }
        await verifyGameFiles(
          stage.path,
          hashes,
          control: _control,
          onProgress: _update,
        );
      } on ArchiveException {
        await zip.delete();
        throw const DevelopmentStorageException('游戏压缩包损坏，重试将重新下载。');
      } on FormatException {
        await zip.delete();
        throw const DevelopmentStorageException('游戏压缩包格式无效，重试将重新下载。');
      } on DevelopmentStorageException catch (e) {
        await zip.delete();
        throw DevelopmentStorageException('$e；重试将重新下载游戏包。');
      }
      final gameRoot = stage.path;
      await File(
        p.join(gameRoot, 'patch.json'),
      ).writeAsString(patch, flush: true);
      await _saveJson(File(p.join(gameRoot, '.mcdev-game.json')), {
        'version': package.version,
        'patch_md5': package.patchMd5,
        'architecture': package.architecture.name,
        'channels': package.channels.map((channel) => channel.name).toList(),
        'client_type': package.clientType.name,
        'installed_at': DateTime.now().toUtc().toIso8601String(),
      });
      await Directory(gameRoot).rename(destination.path);
      await refresh();
      notice = '游戏 ${package.version} 已安装。';
    } finally {
      final cleanup = Directory(nativeFileSystemPath(stage.path));
      if (await cleanup.exists()) await cleanup.delete(recursive: true);
    }
  }

  @override
  Future<void> importGame(String directory) => _operation(() async {
    final source = await Directory(directory).resolveSymbolicLinks();
    final patchFile = File(p.join(source, 'patch.json'));
    if (!await File(p.join(source, 'Minecraft.Windows.exe')).exists() ||
        !await patchFile.exists()) {
      throw const DevelopmentStorageException(
        '请选择包含 Minecraft.Windows.exe 和 patch.json 的完整游戏目录。',
      );
    }
    final version = p.basename(source);
    if (!RegExp(r'^\d+(\.\d+){1,5}$').hasMatch(version)) {
      throw const DevelopmentStorageException('游戏文件夹名称必须是完整版本号。');
    }
    final target = Directory(p.join(storage.paths.games, version));
    if (await target.exists()) {
      throw const DevelopmentStorageException('此版本已有本机安装，未覆盖。');
    }
    final stage = await Directory(
      storage.paths.games,
    ).createTemp('.game-import-');
    try {
      _update(const StorageMigrationProgress('复制已有游戏'));
      await rejectTreeLinks(source);
      await copyDevelopmentTree(source, stage.path);
      await verifyGameFiles(
        stage.path,
        parseGamePatch(await patchFile.readAsString()),
        control: _control,
        onProgress: _update,
      );
      await _saveJson(File(p.join(stage.path, '.mcdev-game.json')), {
        'version': version,
        'imported': true,
      });
      await stage.rename(target.path);
      await refresh();
      notice = '已有游戏已导入。';
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  });

  @override
  Future<void> importMods(
    String path, {
    Future<bool> Function()? confirmUuidRefresh,
  }) => _operation(() async {
    await _readProjects();
    var source = p.absolute(path);
    final type = await FileSystemEntity.type(source);
    Directory? stage;
    ModManifestChanges? changes;
    String? committed;
    var registered = false;
    try {
      if (type == FileSystemEntityType.file) {
        final projects = await Directory(
          p.join(storage.paths.root, 'projects'),
        ).create(recursive: true);
        stage = await projects.createTemp('.import-');
        final input = InputFileStream(source);
        try {
          await extractZipSafe(
            ZipDecoder().decodeStream(input),
            stage.path,
            control: _control,
          );
        } finally {
          input.close();
        }
        source = stage.path;
      } else if (type != FileSystemEntityType.directory) {
        throw const DevelopmentStorageException('模组路径不可访问。');
      }
      List<ModPack> imported;
      try {
        imported = await discoverModPacks(source);
      } on DuplicateModUuidException {
        if (confirmUuidRefresh == null) rethrow;
        if (!await confirmUuidRefresh()) {
          notice = '已取消导入，UUID 未修改。';
          return;
        }
        imported = await discoverModPacks(source, allowDuplicateUuids: true);
        changes = await ModManifestChanges.prepare(
          imported,
          refreshUuids: true,
        );
        await changes.write();
        imported = changes.packs;
      }
      if (imported.isEmpty) {
        throw const DevelopmentStorageException(
          '选中目录或其直接子目录中没有找到有效 manifest.json；'
          '请选择单包目录，或直接包含行为包、资源包目录的模组文件夹。',
        );
      }
      if (stage != null) {
        committed = p.join(
          stage.parent.path,
          'import-${Random.secure().nextInt(1 << 30)}',
        );
        await stage.rename(committed);
      }
      final next = [...packs];
      final previousPacks = packs;
      final previousSelection = {...selectedPacks};
      final importedAt = DateTime.now().toUtc();
      for (final pack in imported) {
        final actual = committed == null
            ? pack.directory
            : p.join(committed, p.relative(pack.directory, from: source));
        final previous = next
            .where(
              (old) => old.uuid == pack.uuid || p.equals(old.directory, actual),
            )
            .firstOrNull;
        next.removeWhere(
          (old) => old.uuid == pack.uuid || p.equals(old.directory, actual),
        );
        if (previous != null && previous.uuid != pack.uuid) {
          selectedPacks.remove(previous.uuid);
        }
        next.add(
          ModPack(
            name: pack.name,
            uuid: pack.uuid,
            version: pack.version,
            type: pack.type,
            directory: actual,
            importedAt: previous == null ? importedAt : previous.importedAt,
            lastLaunchedAt: previous?.lastLaunchedAt,
            projectRoot: pack.projectRoot == null
                ? previous?.projectRoot
                : committed == null
                ? pack.projectRoot
                : p.join(
                    committed,
                    p.relative(pack.projectRoot!, from: source),
                  ),
          ),
        );
        selectedPacks.add(pack.uuid);
      }
      packs = next;
      var savedRegistry = false;
      try {
        await _saveProjects();
        savedRegistry = true;
        await _saveSelection();
      } catch (_) {
        packs = previousPacks;
        selectedPacks
          ..clear()
          ..addAll(previousSelection);
        if (savedRegistry) await _saveProjects();
        rethrow;
      }
      registered = true;
      notice = '已导入 ${groupModProjects(imported).length} 个项目。测试前同步源文件。';
    } finally {
      if (!registered) {
        if (committed != null) {
          final directory = Directory(committed);
          if (await directory.exists()) await directory.delete(recursive: true);
        } else {
          await changes?.rollback();
        }
      }
      if (stage != null && await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  });

  @override
  Future<void> randomizeProjectUuids(String projectId) =>
      _editProjectManifests(projectId, refreshUuids: true);

  @override
  Future<void> upgradeProjectVersion(String projectId) =>
      _editProjectManifests(projectId, upgradeVersion: true);

  Future<void> _editProjectManifests(
    String projectId, {
    bool refreshUuids = false,
    bool upgradeVersion = false,
  }) => _operation(() async {
    await _readProjects();
    final project = projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null) {
      throw const DevelopmentStorageException('项目已被移除，请重新打开详情。');
    }
    // Validate all source manifests before preparing any changes.
    for (final pack in project.packs) {
      await discoverModPacks(pack.directory, allowDuplicateUuids: refreshUuids);
    }
    final changes = await ModManifestChanges.prepare(
      project.packs,
      refreshUuids: refreshUuids,
      upgradeVersion: upgradeVersion,
    );
    final replacements = {
      for (final pack in changes.packs) pack.directory: pack,
    };
    final previousPacks = packs;
    final previousSelection = {...selectedPacks};
    final store = (preferences as TestSessionPreferences).store;
    final selectionChanges = <String, Object?>{};
    final mapping = changes.uuidReplacements;
    if (mapping.entries.any((entry) => entry.key != entry.value)) {
      for (final key in store.getKeys()) {
        if (key != _selectionKey &&
            !(key.startsWith('development_session_') &&
                key.endsWith('_$_selectionKey'))) {
          continue;
        }
        final raw = store.getString(key);
        if (raw == null) continue;
        final ids = (jsonDecode(raw) as List).cast<String>();
        if (ids.any(mapping.containsKey)) {
          selectionChanges[key] = jsonEncode([
            for (final id in ids) mapping[id] ?? id,
          ]);
        }
      }
      final selected = selectedPacks.map((id) => mapping[id] ?? id).toSet();
      selectedPacks
        ..clear()
        ..addAll(selected);
    }
    var savedRegistry = false;
    try {
      await changes.write();
      packs = [for (final pack in packs) replacements[pack.directory] ?? pack];
      await _saveProjects();
      savedRegistry = true;
      if (selectionChanges.isNotEmpty) await store.apply(selectionChanges);
      notice = refreshUuids
          ? '项目 UUID 已随机刷新，包依赖已同步。'
          : '项目版本号已升级，末位加 1，模块和包依赖已同步。';
    } catch (_) {
      packs = previousPacks;
      selectedPacks
        ..clear()
        ..addAll(previousSelection);
      await changes.rollback();
      if (savedRegistry) await _saveProjects();
      rethrow;
    }
  });

  @override
  Future<void> removePack(String uuid) => removePacks([uuid]);

  @override
  Future<void> removePacks(Iterable<String> uuids) => _operation(() async {
    await _readProjects();
    final ids = uuids.toSet();
    final previous = [...packs];
    final selected = {...selectedPacks};
    packs = packs.where((pack) => !ids.contains(pack.uuid)).toList();
    selectedPacks.removeAll(ids);
    try {
      await _saveProjects();
      await _saveSelection();
      notice = '项目已从列表移除，源文件保留。';
    } catch (_) {
      packs = previous;
      selectedPacks
        ..clear()
        ..addAll(selected);
      rethrow;
    }
  });

  Future<String> _roaming() => _runtime.roaming();

  @override
  Future<void> launchTest({
    required String worldName,
    required bool creative,
    required bool menuOnly,
    String? seed,
  }) {
    if (busy || running) {
      return Future.error(const DevelopmentStorageException('此测试页已经在运行。'));
    }
    _stopRequested = false;
    _stopping = false;
    _launchGeneration++;
    final operation = _operation(
      () => withTestSessionLocks(
        storageLock: _lock,
        prefixes: storage.paths.prefixes,
        sessionId: sessionId,
        run: (releasePreparation) => _launchTest(
          worldName: worldName,
          creative: creative,
          menuOnly: menuOnly,
          seed: seed,
          releasePreparation: releasePreparation,
        ),
      ),
      sharedLock: false,
    );
    _launchCompletion = operation;
    return operation;
  }

  Future<void> _launchTest({
    required String worldName,
    required bool creative,
    required bool menuOnly,
    required void Function() releasePreparation,
    String? seed,
  }) async {
    final generation = _launchGeneration;
    _pythonReloadSession = null;
    _pythonReloadBridge = null;
    _pythonReloadFailure = null;
    _pythonReloadNeedsRestart = false;
    _pythonReloadApplied = false;
    pythonReloadBusy = false;
    _control?.check();
    _joinTarget?.requireHost();
    if (_joinTarget == null) {
      for (final guest in _lanGuests.values) {
        guest.launcher.dispose();
      }
      _lanGuests.clear();
      _hasLanPlayers = false;
      _hostEverJoined = false;
      _closingLan = false;
      _lanPort = null;
      _lanPortChecked = null;
      _requestedLanPort = null;
      _worldPlayers = [];
      _rosterUpdated = null;
      _rosterSequence = -1;
      _rosterEpoch = null;
      _hostPackRoot = null;
    }
    final game = games
        .where((game) => game.version == selectedVersion)
        .firstOrNull;
    if (game == null) throw const DevelopmentStorageException('请先下载或导入游戏。');
    if (!menuOnly && useNewWorld && seed != null) {
      final value = seed.trim();
      if (!await preferences.setString(_worldSeedKey, value)) {
        throw const DevelopmentStorageException('无法保存世界种子。');
      }
      newWorldSeed = value;
    }
    Directory? performanceFiles;
    Directory? lanFiles;
    Directory? rendererFiles;
    Directory? pythonFiles;
    String? dragonRuntime;
    final adaptedDragon =
        capabilities.metalRenderer &&
        !menuOnly &&
        effectiveRenderer == GameRenderer.renderDragon &&
        renderDragonCompatibilitySupported;
    _update(const StorageMigrationProgress('准备此测试页的游戏文件'));
    final gameDirectory = await prepareSessionGame(
      source: game.directory,
      prefix: gamePrefix,
      version: game.version,
    );
    final executable = p.join(gameDirectory, 'Minecraft.Windows.exe');
    _lanTransportReady = false;
    if (!menuOnly && supportsLanPatch(game.version)) {
      _update(const StorageMigrationProgress('校验局域网兼容组件'));
      await validateLanGame(game.version, File(executable));
      lanFiles = await prepareLanPatch(storage.paths.runtimes);
    }
    if (performanceOptimization && performanceOptimizationSupported) {
      _update(const StorageMigrationProgress('校验性能补丁'));
      await validatePerformanceGame(game.version, File(executable));
      performanceFiles = await preparePerformancePatch(storage.paths.runtimes);
    }
    if (adaptedDragon) {
      _update(const StorageMigrationProgress('校验渲染龙适配版本'));
      await validateRenderDragonGame(game.version, File(executable));
      dragonRuntime = await prepareRenderDragonRuntime(
        baseRuntime: runtime,
        runtimes: storage.paths.runtimes,
        downloads: storage.paths.downloads,
        client: api.client,
        control: _control,
        onProgress: _update,
      );
      rendererFiles = await prepareRendererPatch(storage.paths.runtimes);
    }
    await _connectAccount();
    await _runtime.prepare(_update);
    if (dragonRuntime != null) {
      await prepareWineMetalPrefix(dragonRuntime, gamePrefix);
    }
    final options = File(
      p.join(
        await _roaming(),
        'MinecraftPE_Netease',
        'minecraftpe',
        'options.txt',
      ),
    );
    await options.parent.create(recursive: true);
    final originalOptions = await options.exists()
        ? await options.readAsString(encoding: gameOptionsEncoding)
        : '';
    final stagingOptions = File('${options.path}.mcdev-tmp');
    IOSink? output;
    ModLogServer? modLogs;
    final nativeFilters = <ModNativeErrorFilter>[];
    final subscriptions = <StreamSubscription<Object?>>[];
    String? runtimeFailure;
    try {
      await stagingOptions.writeAsString(
        mergeGameOptions(originalOptions, {
          ...frameLimitOptions(
            limit60Fps,
            nativePacing: performanceFiles != null,
          ),
          if (adaptedDragon) ...renderDragonOptions(vibrantVisuals),
          'dev_showDevConsoleButton': showDeveloperConsole ? '1' : '0',
          // Match MCS CppGameOptionM.SetForceOptions. These developer options
          // do not replace normal resource initialization or suppress all
          // native resource assertions.
          'resource_concatenation_enabled': '0',
          'dev_assertions_debug_break': '0',
          // Direct LAN login reads this option rather than player_info's
          // launcher nickname. Keep each managed prefix's player independent.
          'mp_username': _playerName,
        }),
        flush: true,
      );
      await stagingOptions.rename(options.path);
      final chosen = packs
          .where((pack) => selectedPacks.contains(pack.uuid))
          .toList();
      final dataRoot = p.join(
        await _roaming(),
        'MinecraftPE_Netease',
        'games',
        'com.netease',
      );
      if (_joinTarget == null) _hostPackRoot = dataRoot;
      final behavior = <String>[], resources = <String>[];
      final modSnapshots = <Directory>[];
      final pythonPacks = <PythonReloadPack>[];
      for (final pack in chosen) {
        _control?.check();
        final name = 'mcdev_${pack.uuid}';
        // A guest joins the already running world. Source projects may have
        // changed since launch; use exactly the host's mounted pack snapshot.
        final source = _joinTarget == null
            ? pack.directory
            : p.join(
                _joinTarget!.packRoot,
                pack.type == 'resources' ? 'resource_packs' : 'behavior_packs',
                name,
              );
        final current = (await discoverModPacks(
          source,
        )).where((item) => item.uuid == pack.uuid).firstOrNull;
        if (current == null) {
          throw DevelopmentStorageException(
            '模组 ${pack.name} 的源文件已变化或无法访问，请重新导入。',
          );
        }
        final target = Directory(
          p.join(
            dataRoot,
            pack.type == 'resources' ? 'resource_packs' : 'behavior_packs',
            name,
          ),
        );
        await target.parent.create(recursive: true);
        final staging = await target.parent.createTemp('.pack-');
        final backup = Directory('${target.path}.previous');
        try {
          await rejectTreeLinks(source);
          await copyDevelopmentTree(source, staging.path);
          await rejectTreeLinks(staging.path);
          if (await backup.exists()) await backup.delete(recursive: true);
          if (await target.exists()) await target.rename(backup.path);
          try {
            await staging.rename(target.path);
          } catch (_) {
            if (await backup.exists()) await backup.rename(target.path);
            rethrow;
          }
          if (await backup.exists()) await backup.delete(recursive: true);
        } finally {
          if (await staging.exists()) await staging.delete(recursive: true);
        }
        (pack.type == 'resources' ? resources : behavior).add(name);
        modSnapshots.add(target);
        if (pack.type != 'resources') {
          pythonPacks.add(PythonReloadPack(source, target.path));
        }
      }
      if (!menuOnly && game.version == pythonReloadVersion) {
        try {
          _pythonReloadSession = await PythonReloadSession.capture(pythonPacks);
          if (_pythonReloadSession!.hasScripts) {
            pythonFiles = await preparePythonReloadDll(
              storage.paths.runtimes,
              File(executable),
            );
            _pythonReloadBridge = await PythonReloadBridge.create(
              behaviorPacks: p.join(dataRoot, 'behavior_packs'),
              testDirectory: _runtime.testDirectory,
              gamePath: _winPath,
              roots: _pythonReloadSession!.roots,
            );
            behavior.add(PythonReloadBridge.packName);
          }
        } catch (e) {
          _pythonReloadFailure = 'Python 热重载暂不可用：$e';
          pythonFiles = null;
          _pythonReloadBridge = null;
        }
      }
      final modCapture = await prepareModLogCapture(modSnapshots);
      if (_joinTarget case final target?) {
        target.requireHost();
        await target.bridge.copyToGuest(
          behaviorPacksDirectory: p.join(dataRoot, 'behavior_packs'),
        );
        behavior.add(target.bridge.directoryName);
        target.requireHost();
      }
      // Legacy endpoint replies alone do not prove ownership. _pollLan still
      // verifies the exact game PID. Protocol diagnostics are not mod output.
      _rpc = await LanGameRpc.start();
      final stamp = '$sessionId-${DateTime.now().microsecondsSinceEpoch}';
      final config = File(p.join(_runtime.testDirectory, 'test.cppconfig'));
      final args = <String>[
        'dc_tag1=${menuOnly ? 'mod_pc_no_launcher' : 'studio_no_launcher'}',
      ];
      if (!menuOnly) {
        _hostSkin = playerSkin;
        final skinInfo = await _runtime.prepareSkin(_hostSkin, gameDirectory);
        final world = _joinTarget == null
            ? await TestWorldStore(
                p.join(
                  await _roaming(),
                  'MinecraftPE_Netease',
                  'minecraftWorlds',
                ),
              ).prepare(fresh: useNewWorld, seed: newWorldSeed)
            : null;
        final playerId =
            (((int.tryParse(api.session?.id ?? '') ?? 0) | 0x80000000) &
            0xffffffff);
        _roomToken =
            _joinTarget?.token ??
            // CoreNative.GetH5Token returns the login token's MD5 hex;
            // CppGameM encodes those 16 digest bytes for the game config.
            base64Encode(md5.convert(utf8.encode(api.session!.token)).bytes);
        _hostId = _joinTarget?.hostId ?? playerId;
        _hostWorldName = worldName.trim().isEmpty ? '模组测试' : worldName.trim();
        if (_joinTarget == null) {
          _requestedLanPort = await chooseAvailableLanPort();
          _lanBridge = await LanRosterBridge.create(
            behaviorPacksDirectory: p.join(dataRoot, 'behavior_packs'),
            reportPath: p.join(_runtime.testDirectory, 'lan-roster.json'),
            windowsReportPath: _runtime.testFilePath('lan-roster.json'),
          );
          behavior.add(_lanBridge!.directoryName);
        }
        await _saveJson(config, {
          'version': game.version,
          if (rendererSwitchSupported)
            ...rendererConfig(
              effectiveRenderer,
              catalog?.packages
                      .where((package) => package.version == game.version)
                      .firstOrNull
                      ?.clientType ??
                  game.clientType,
            ),
          'MainComponentId': '',
          // 3.10 Launch::launch forwards this object to SunshineManager;
          // PetSysClient reads it before creating UI or scheduling its summon.
          'launch_params': {'close_pet_addon': disableCompanion},
          'LocalComponentPathsDict': {},
          'path': _winPath(config.path),
          'world_info': world == null
              ? null
              : {
                  'level_id': world.levelId,
                  'name': worldName.trim().isEmpty ? '模组测试' : worldName.trim(),
                  'seed': world.seed,
                  'game_type': creative ? 1 : 0,
                  'difficulty': 2,
                  'permission_level': 1,
                  'cheat': true,
                  'cheat_info': {
                    'pvp': true,
                    'show_coordinates': true,
                    'daylight_cycle': true,
                    'fire_spreads': true,
                    'tnt_explodes': true,
                    'mob_spawn': true,
                    'natural_regeneration': true,
                    'mob_loot': true,
                    'mob_griefing': true,
                    'tile_drops': true,
                    'entities_drop_loot': true,
                    'weather_cycle': true,
                    'command_blocks_enabled': true,
                    'random_tick_speed': 1,
                  },
                  'resource_packs': resources,
                  'behavior_packs': behavior,
                  'world_type': 1,
                  'start_with_map': false,
                  'bonus_items': false,
                },
          'room_info': {
            // Use local RakNet rather than the developer client's default
            // NetherNet/P2P service, which requires online signaling.
            'in_webrtc_gray': false,
            'ip': _joinTarget == null ? '' : '127.0.0.1',
            'port': _joinTarget?.port ?? _requestedLanPort,
            // Each guest owns an independent process and prefix. MCS's
            // muiltClient shortcut skips player, skin and resource bootstrap;
            // type 100 plus the endpoint still selects a remote world join.
            'muiltClient': false,
            'token': _roomToken,
            'room_id': _hostId,
            'host_id': _hostId,
            'room_name': _hostWorldName,
            'max_player': 255,
            'visibility_mode': 0,
            'allow_pe': true,
            'is_pe': false,
            'item_ids': [],
          },
          'player_info': {
            'user_id': playerId,
            'user_name': _playerName,
            'urs': '',
          },
          'skin_info': skinInfo,
          'anti_addiction_info': {
            'enable': false,
            'left_time': 0,
            'exp_multiplier': 1.0,
            'block_multplier': 1.0,
            'first_message': '',
          },
          'misc': {
            // LAN_HOST/GUEST (1/2) are NetEase relay rooms. Keep the host a
            // local test world and join its direct endpoint with type 100.
            'multiplayer_game_type': _joinTarget == null ? 0 : 100,
            'launcher_port': _rpc!.port,
            'auth_server_url': 'https://g79authexpr1.nie.netease.com',
            'sensitive_word_file': '',
            'is_store_enabled': 1,
          },
          'web_server_url':
              api.web?.toString() ?? 'https://x19mclexpr.nie.netease.com',
          'core_server_url': 'https://x19exprcore.nie.netease.com:8443',
          'vip_using_mod': chosen.map((pack) => pack.uuid).toList(),
          'isCloud': false,
          'last_play_time': 0,
        });
        args.add('config=${_winPath(config.path)}');
      }
      logPath = p.join(storage.paths.logs, 'test-$stamp.log');
      args.add(
        'errorlog=${_winPath(p.join(storage.paths.logs, 'game-$stamp.log'))}',
      );
      await Directory(p.dirname(logPath!)).create(recursive: true);
      final assertDir = Directory(p.join(_runtime.testDirectory, 'assertions'));
      await assertDir.create(recursive: true);
      await _saveJson(File(p.join(gameDirectory, 'netease_data.json')), {
        'Uid': api.session?.id ?? '',
        'Urs': '',
        'ServerName': 'MCS',
        'Product': 'mcstudio_mod_pc',
        'AssertCacheDir': _winPath(assertDir.path),
      });
      output = File(logPath!).openWrite();
      _writePythonReloadLog = (text) => output?.write(text);
      output.writeln(
        '[INFO] 准备测试游戏：${game.version} · ${effectiveRenderer.label}',
      );
      if (_pythonReloadFailure != null) {
        output.writeln('[WARN] $_pythonReloadFailure');
      }
      final diagnostics = await _runtime.createDiagnostics();
      await diagnostics.prepare();
      modLogs = await ModLogServer.start(
        marker: modCapture.marker,
        sources: modCapture.sources,
        onText: (text) {
          if (generation == _launchGeneration) output?.write(text);
        },
        onNativeLine: (line) {
          if (generation != _launchGeneration) return;
          final diagnostic = classifyNativeDiagnostic(line);
          if (diagnostic != null) output?.write(diagnostic.logLine);
        },
      );
      args.addAll(['loggingIP=127.0.0.1', 'loggingPort=${modLogs.port}']);
      final performanceLog = p.join(
        storage.paths.logs,
        'performance-$stamp.log',
      );
      final rendererLog = p.join(storage.paths.logs, 'renderer-$stamp.log');
      final lanLog = p.join(storage.paths.logs, 'lan-$stamp.log');
      if (dragonRuntime != null) {
        _runtime.activeRuntime = dragonRuntime;
      }
      _control?.check();
      _joinTarget?.requireHost();
      if (_joinTarget != null) {
        await File(
          p.join(
            await _roaming(),
            'MinecraftPE_Netease',
            'random_device_id.txt',
          ),
        ).writeAsString('');
      }
      _control?.check();
      await _joinTarget?.verifyHost(() {
        _control?.check();
        if (_stopRequested) throw DownloadCancelled();
      });
      _control?.check();
      _game = await _runtime.start(
        executable: executable,
        arguments: args,
        version: game.version,
        displayName: gameDisplayName,
        renderer: (menuOnly ? GameRenderer.openGL : effectiveRenderer).label,
        fullscreenShortcut: fullscreenShortcut,
        workingDirectory: gameDirectory,
        overrides: {
          if (_pythonReloadBridge != null) ..._pythonReloadBridge!.environment,
          if (lanFiles != null) ...{
            'MCDEV_LAN_PATCH_LOG': _winPath(lanLog),
            'MCDEV_LAN_ROLE': _joinTarget == null ? 'host' : 'guest',
          },
          if (rendererFiles != null) ...{
            ...renderDragonEnvironment,
            'MCDEV_RENDERER_LOG': _winPath(rendererLog),
            'MCDEV_VIBRANT': vibrantVisuals ? '1' : '0',
          },
          if (performanceFiles != null) ...{
            'MCDEV_PERFORMANCE_LOG': _winPath(performanceLog),
            'MCDEV_PERFORMANCE_LIMIT': limit60Fps ? '1' : '0',
          },
        },
      );
      running = true;
      output.writeln('[INFO] 游戏进程已创建，PID=${_game!.pid}；等待世界加载。');
      subscriptions.add(
        diagnostics.watch().listen(
          (event) {
            if (generation != _launchGeneration) return;
            output?.write(event.logLine);
            if (event.fatal && runtimeFailure == null) {
              runtimeFailure = event.message;
              error = event.message;
              notice = null;
              _notify();
              unawaited(_runtime.stop(_game!).catchError((Object _) {}));
            }
          },
          onError: (Object _) {
            output?.writeln('[WARN] 游戏诊断采集已中断。');
          },
        ),
      );
      final launchedAt = DateTime.now().toUtc();
      busy = false;
      final actualRenderer = menuOnly ? GameRenderer.openGL : effectiveRenderer;
      notice =
          '游戏进程已启动，正在加载（${actualRenderer.label} · ${limit60Fps ? '60 帧上限' : '不限帧'}）。';
      _notify();
      final drains = <Future<void>>[];
      for (final stream in [_game!.stdout, _game!.stderr]) {
        final filter = ModNativeErrorFilter(
          modCapture.sources,
          (text) => output?.write(text),
        );
        nativeFilters.add(filter);
        final done = Completer<void>();
        subscriptions.add(
          stream
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(
                filter.add,
                onError: (Object e, StackTrace st) {
                  if (!done.isCompleted) done.completeError(e, st);
                },
                onDone: () {
                  filter.close();
                  if (!done.isCompleted) done.complete();
                },
              ),
        );
        drains.add(done.future);
      }
      final drained = Future.wait(drains);
      // Attach immediately so an early stream error cannot become unhandled.
      unawaited(
        drained.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      progress = null;
      if (lanFiles != null) {
        unawaited(_activateLan(lanFiles, executable, lanLog, _game!));
      }
      if (pythonFiles != null && _pythonReloadBridge != null) {
        final bridge = _pythonReloadBridge!;
        unawaited(
          _activatePythonReload(pythonFiles, executable, bridge, _game!),
        );
        var polling = false;
        _pythonReloadTimer = Timer.periodic(const Duration(seconds: 1), (
          _,
        ) async {
          if (polling ||
              generation != _launchGeneration ||
              !identical(bridge, _pythonReloadBridge)) {
            return;
          }
          polling = true;
          try {
            await bridge.poll();
            _notify();
          } finally {
            polling = false;
          }
        });
      }
      if (performanceFiles != null) {
        unawaited(
          _activatePerformance(
            performanceFiles,
            executable,
            performanceLog,
            _game!,
          ),
        );
      }
      if (rendererFiles != null) {
        unawaited(
          _activateRenderer(rendererFiles, executable, rendererLog, _game!),
        );
      }
      if (!menuOnly &&
          _joinTarget == null &&
          !_stopRequested &&
          _control?.cancelled != true) {
        try {
          await _recordProjectLaunch(
            chosen.map((pack) => pack.uuid),
            launchedAt,
          );
        } catch (e) {
          error = '游戏已启动，但无法保存项目启动时间：$e';
        }
        _notify();
      }
      releasePreparation();
      // Cancellation can arrive while Process.start is awaiting the OS. At
      // that time stopGame has no Process to close and waits for this lifetime.
      // Close the process directly here; calling stopGame would self-await.
      final cancelledAfterSpawn =
          _stopRequested ||
          _control?.cancelled == true ||
          (_joinTarget != null && !_joinTarget!.isCurrent());
      if (cancelledAfterSpawn) {
        _stopRequested = true;
        _closingLan = true;
        try {
          await _requestProcessExit(_game!);
        } catch (_) {
          // Retain the live process and its lifetime lease if the OS could not
          // stop it. The user can retry shutdown; never mark it as exited.
          error = '游戏启动已取消，但窗口尚未退出，请重试退出测试。';
          _notify();
        }
      } else if (_joinTarget == null && !menuOnly) {
        _lanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          unawaited(_pollLan());
        });
      }
      final code = await _game!.exitCode;
      output.writeln(
        '[${code == 0 ? 'INFO' : 'ERROR'}] 游戏进程退出：$code（0x${(code & 0xffffffff).toRadixString(16).padLeft(8, '0')}）。',
      );
      busy = true;
      await _stopLanGuests();
      try {
        await drained.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        await _runtime.terminateHelpers();
      }
      if (runtimeFailure != null) {
        error = runtimeFailure;
      } else if (code != 0 && !_stopRequested) {
        error = '测试游戏退出（$code），请打开日志查看。';
      } else {
        notice = '测试游戏已退出，存档保留在当前容器中。';
      }
    } finally {
      // Invalidate in-flight probes before any asynchronous cleanup. RPC must
      // stop writing before the log sink closes.
      busy = true;
      _closingLan = true;
      _lanTimer?.cancel();
      _lanTimer = null;
      _lanBridge = null;
      _pythonReloadTimer?.cancel();
      _pythonReloadTimer = null;
      final reloadBridge = _pythonReloadBridge;
      _pythonReloadBridge = null;
      await reloadBridge?.close();
      // A cancelled staging operation must restore its files before another
      // launch can reuse this session's mounted directories.
      await _pythonReloadFinished?.future;
      _pythonReloadSession = null;
      try {
        await _closeRpc();
      } catch (_) {
        // The server invalidates callbacks before closing its socket; continue
        // releasing streams and the prefix even if the OS reports close errors.
      }
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      try {
        await _runtime.terminateHelpers();
      } catch (_) {
        output?.writeln('[WARN] 运行环境清理失败，下次启动将尝试恢复。');
      }
      try {
        await modLogs?.close();
        for (final filter in nativeFilters) {
          filter.close();
        }
        _writePythonReloadLog = null;
        await output?.close();
      } finally {
        _lanPort = null;
        _worldPlayers = [];
        _lanBridge = null;
        running = false;
        _game = null;
        _runtime.activeRuntime = null;
        if (adaptedDragon && await options.exists()) {
          try {
            // The prefix is shared across versions. Restore only the two
            // temporary renderer settings; preserve game-written preferences.
            final text = await options.readAsString(
              encoding: gameOptionsEncoding,
            );
            await stagingOptions.writeAsString(
              restoreRenderDragonOptions(text, originalOptions),
              flush: true,
            );
            await stagingOptions.rename(options.path);
          } on FileSystemException {
            error ??= '渲染设置恢复失败，请检查开发目录的写入权限。';
          }
        }
        _notify();
      }
    }
  }

  Future<void> _activatePythonReload(
    Directory files,
    String executable,
    PythonReloadBridge bridge,
    Process target,
  ) async {
    bool current() =>
        running &&
        identical(_game, target) &&
        identical(_pythonReloadBridge, bridge);
    try {
      final loaded = await injectPerformancePatch(
        wine: _runtime.wine,
        targetPid: target.pid,
        environment: _env(gamePrefix),
        helper: _winPath(p.join(files.path, lanInjectorFile)),
        dll: _winPath(p.join(files.path, 'python-reload.dll')),
        executable: _winPath(executable),
        cancelWhen: target.exitCode.then<void>((_) {}),
      );
      if (!current()) return;
      if (!loaded) {
        throw const DevelopmentStorageException('Python 重载 DLL 未能加载。');
      }
      final deadline = DateTime.now().add(const Duration(seconds: 70));
      while (current() && DateTime.now().isBefore(deadline)) {
        final log = File(bridge.nativeLogPath);
        if (await log.exists()) {
          try {
            final result = jsonDecode(await log.readAsString()) as Map;
            if (result['state'] == 'ready') {
              await _pythonReloadLog('[INFO] Python 热重载 DLL 已就绪。');
              return;
            }
            if (result['state'] != null) {
              throw DevelopmentStorageException(
                'Python 重载 DLL 不支持当前运行布局：${result['reason']}',
              );
            }
          } on FormatException {
            // The worker may still be writing its readiness record.
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (current()) {
        throw const DevelopmentStorageException('Python 重载 DLL 初始化超时。');
      }
    } catch (e) {
      if (current()) {
        _pythonReloadFailure = e.toString();
        await _pythonReloadLog('[WARN] $_pythonReloadFailure');
        _notify();
      }
    }
  }

  Future<void> _activateLan(
    Directory files,
    String executable,
    String log,
    Process target,
  ) async {
    bool current() => running && identical(_game, target);
    try {
      final loaded = await injectPerformancePatch(
        wine: wine,
        targetPid: target.pid,
        environment: _env(gamePrefix),
        helper: _winPath(p.join(files.path, lanInjectorFile)),
        dll: _winPath(p.join(files.path, 'lan-patch.dll')),
        executable: _winPath(executable),
        cancelWhen: target.exitCode.then<void>((_) {}),
      );
      if (loaded) {
        for (var attempt = 0; attempt < 160 && current(); attempt++) {
          final file = File(log);
          if (await file.exists()) {
            final text = await file.readAsString();
            if (!current()) return;
            if (text.contains('"lan_patch":"ready"')) {
              _lanTransportReady = true;
              _notify();
              return;
            }
            if (text.contains('"lan_patch":"failed"') ||
                text.contains('"lan_patch":"unsupported"')) {
              break;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (_) {
      // Single-player gameplay may continue; no unverified LAN join is offered.
    }
    if (current()) {
      if (_joinTarget != null) {
        error = '局域网连接兼容组件未能激活，请查看日志后重新添加测试玩家。';
        _notify();
        try {
          await stopGame();
        } catch (_) {
          error = '局域网兼容组件未能激活，访客窗口尚未退出，请在玩家列表关闭该窗口。';
          _notify();
        }
        return;
      }
      notice = '局域网兼容组件未能激活，当前游戏仍可继续单人测试，请查看日志。';
      _notify();
    }
  }

  Future<void> _activateRenderer(
    Directory files,
    String executable,
    String log,
    Process target,
  ) async {
    bool current() => running && identical(_game, target);
    try {
      final loaded = await injectPerformancePatch(
        wine: wine,
        targetPid: target.pid,
        environment: _env(
          gamePrefix,
          overrides: {
            ...renderDragonEnvironment,
            'MCDEV_RENDERER_LOG': _winPath(log),
            'MCDEV_VIBRANT': vibrantVisuals ? '1' : '0',
          },
        ),
        helper: _winPath(p.join(files.path, 'renderer-inject.exe')),
        dll: _winPath(p.join(files.path, 'renderer-patch.dll')),
        executable: _winPath(executable),
        cancelWhen: target.exitCode.then<void>((_) {}),
      );
      if (loaded) {
        for (var attempt = 0; attempt < 140 && current(); attempt++) {
          final file = File(log);
          if (await file.exists()) {
            final text = await file.readAsString();
            if (!current()) return;
            if (text.contains('"renderer_patch":"active"')) {
              notice =
                  vibrantVisuals && text.contains('"vibrant_supported":true')
                  ? '渲染龙 Metal 适配与灵动视效模式已启用（实验性）。'
                  : vibrantVisuals
                  ? '渲染龙已启用，此设备未满足灵动视效能力要求，请查看渲染日志。'
                  : '渲染龙 Metal 适配已启用。';
              _notify();
              return;
            }
            if (text.contains('failed') || text.contains('unsupported')) break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      if (current()) {
        error = '渲染龙适配未能激活，请退出游戏后重试或切回 OpenGL。';
        _notify();
      }
    } catch (_) {
      if (current()) {
        error = '渲染龙适配加载失败，请查看日志，或退出后切回 OpenGL。';
        _notify();
      }
    }
  }

  Future<void> _activatePerformance(
    Directory files,
    String executable,
    String log,
    Process target,
  ) async {
    bool current() => running && identical(_game, target);
    String fallbackNotice(String detail) =>
        limit60Fps ? '$detail 本次 60 帧上限也未生效；请退出后关闭图形优化再启动。' : detail;
    try {
      final loaded = await injectPerformancePatch(
        wine: wine,
        targetPid: target.pid,
        environment: _env(gamePrefix),
        helper: _winPath(p.join(files.path, 'performance-inject.exe')),
        dll: _winPath(p.join(files.path, 'graphics-patch.dll')),
        executable: _winPath(executable),
        cancelWhen: target.exitCode.then<void>((_) {}),
      );
      if (!loaded) {
        if (current()) {
          notice = fallbackNotice('游戏已启动，性能补丁未能加载；本次使用正常渲染。');
          _notify();
        }
        return;
      }
      for (var attempt = 0; attempt < 190 && current(); attempt++) {
        final file = File(log);
        if (await file.exists()) {
          final text = await file.readAsString();
          if (!current()) return;
          if (text.contains('"performance_patch":"active"')) {
            notice = limit60Fps
                ? '测试游戏已启动，图形优化与 60 帧上限已生效。'
                : '测试游戏已启动，图形优化已生效，帧率不设上限。';
            _notify();
            return;
          }
          if (text.contains('failed') || text.contains('unsupported')) break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (current()) {
        notice = fallbackNotice('性能补丁未激活；游戏继续使用正常渲染，请查看性能日志。');
        _notify();
      }
    } catch (_) {
      if (current()) {
        notice = fallbackNotice('游戏继续运行，性能补丁加载失败；可在退出后重试。');
        _notify();
      }
    }
  }

  Future<void> _closeRpc() async {
    final rpc = _rpc;
    _rpc = null;
    await rpc?.close();
  }

  Future<void> _requestProcessExit(Process child) => _runtime.stop(child);

  @override
  Future<void> stopGame() async {
    final completion = _launchCompletion;
    final generation = _launchGeneration;
    if (_game == null && !busy) return;
    if (_stopping) {
      await completion?.timeout(const Duration(seconds: 90));
      return;
    }
    _stopping = true;
    _stopRequested = true;
    _control?.cancelled = true;
    _closingLan = true;
    _notify();
    try {
      try {
        await _stopLanGuests().timeout(const Duration(seconds: 90));
      } catch (_) {
        // Still close the host if a guest could not finish shutting down.
      }
      final child = _game;
      if (child != null) await _requestProcessExit(child);
      await completion?.timeout(const Duration(seconds: 90));
    } catch (_) {
      throw const DevelopmentStorageException('测试游戏尚未完成退出，请重试；正在运行的窗口与存档仍保留。');
    } finally {
      if (generation == _launchGeneration) _stopping = false;
    }
  }

  @override
  void cancel() {
    _control?.cancelled = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _control?.cancelled = true;
    for (final guest in _lanGuests.values) {
      guest.launcher.dispose();
    }
    if (!running && !busy) api.close();
    super.dispose();
  }
}

class _LanJoinTarget {
  const _LanJoinTarget(
    this.port,
    this.hostPid,
    this.hostId,
    this.worldName,
    this.token,
    this.packRoot,
    this.bridge,
    this.isCurrent,
    this.hasFreshWorld,
    this.refreshWorld,
  );
  final int port;
  final int hostPid;
  final int hostId;
  final String worldName;
  final String token;
  final String packRoot;
  final LanRosterBridge bridge;
  final bool Function() isCurrent;
  final bool Function() hasFreshWorld;
  final Future<void> Function() refreshWorld;
  void requireHost() {
    if (!isCurrent()) {
      throw const DevelopmentStorageException('房主世界已退出或已切换，请重新添加测试玩家。');
    }
  }

  Future<void> verifyHost(void Function() checkCancelled) => verifyLanJoinHost(
    hostPid: hostPid,
    port: port,
    requireHost: requireHost,
    hasFreshWorld: hasFreshWorld,
    refreshWorld: refreshWorld,
    checkCancelled: checkCancelled,
  );
}

class _LanGuest {
  _LanGuest(this.id, this.name, this.skin, this.launcher);
  final String id;
  final String name;
  final TestPlayerSkin skin;
  final NativeDevelopmentLauncher launcher;
  bool finished = false;
  bool everJoined = false;
  String? failure;
}

Future<String> _readModPackTitle(String directory, String fallback) async {
  try {
    final manifest = jsonDecode(
      await File(p.join(directory, 'manifest.json')).readAsString(),
    );
    final header = manifest is Map ? manifest['header'] : null;
    final name = header is Map ? header['name'] : null;
    if (name is String && modDisplayName(name).isNotEmpty) return name;
  } on FileSystemException {
    // Keep registered projects visible if their source is temporarily offline.
  } on FormatException {
    // A manifest being edited should not prevent the project list from loading.
  }
  return fallback;
}

Future<List<ModPack>> discoverModPacks(
  String root, {
  bool allowDuplicateUuids = false,
}) async {
  final result = <ModPack>[];
  final uuids = <String>{};
  var duplicateUuids = false;
  Future<bool> readPack(String directory) async {
    final file = File(p.join(directory, 'manifest.json'));
    if (await file.exists()) {
      final manifest = jsonDecode(await file.readAsString());
      final header = manifest is Map ? manifest['header'] : null;
      final modules = manifest is Map ? manifest['modules'] : null;
      if (header is! Map || modules is! List) {
        throw const DevelopmentStorageException('模组 manifest.json 结构无效。');
      }
      final uuid = header['uuid'];
      final version = header['version'];
      if (uuid is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
          ).hasMatch(uuid) ||
          version is! List ||
          version.length != 3 ||
          version.any((v) => v is! int || v < 0)) {
        throw const DevelopmentStorageException('模组 UUID 或版本无效。');
      }
      if (modules.isEmpty ||
          modules.any((m) => m is! Map || m['type'] is! String)) {
        throw const DevelopmentStorageException('模组模块声明无效。');
      }
      final types = modules.map((m) => m['type']).toSet();
      final type = types.contains('resources')
          ? 'resources'
          : types.any((t) => t == 'data' || t == 'script')
          ? 'data'
          : null;
      if (type == null) {
        throw const DevelopmentStorageException('模组不包含可测试的资源、行为或脚本模块。');
      }
      for (final id in [
        uuid,
        for (final module in modules)
          if (module['uuid'] is String) module['uuid'] as String,
      ]) {
        if (!uuids.add(id.toLowerCase())) duplicateUuids = true;
      }
      result.add(
        ModPack(
          name: header['name']?.toString() ?? p.basename(directory),
          uuid: uuid.toLowerCase(),
          version: version.cast<int>(),
          type: type,
          directory: directory,
        ),
      );
      return true;
    }
    return false;
  }

  final directory = await Directory(root).resolveSymbolicLinks();
  // The selected directory is either a single pack or a project whose packs
  // live immediately below it. Never walk into backups or nested projects.
  if (await readPack(directory)) {
    if (duplicateUuids && !allowDuplicateUuids) {
      throw const DuplicateModUuidException();
    }
    return result;
  }
  await for (final entry in Directory(directory).list(followLinks: false)) {
    if (entry is Directory &&
        !p.basename(entry.path).startsWith('.') &&
        !['build', 'node_modules'].contains(p.basename(entry.path))) {
      await readPack(entry.path);
    }
  }
  if (result.where((pack) => pack.type == 'data').length > 1 ||
      result.where((pack) => pack.type == 'resources').length > 1) {
    throw const DevelopmentStorageException(
      '选中目录包含多个行为包或资源包，请选择具体模组项目目录或单包目录。',
    );
  }
  if (duplicateUuids && !allowDuplicateUuids) {
    throw const DuplicateModUuidException();
  }
  // A single-pack import keeps legacy name-based matching, allowing its
  // companion to be imported later. A pair belongs to the selected project.
  if (result.length < 2) return result;
  return [
    for (final pack in result)
      ModPack(
        name: pack.name,
        uuid: pack.uuid,
        version: pack.version,
        type: pack.type,
        directory: pack.directory,
        projectRoot: directory,
      ),
  ];
}
