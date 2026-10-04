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
import 'development_storage.dart';
import 'download_io.dart';
import 'launcher_service.dart';
import 'mcs_api.dart';
import 'wine_patch_io.dart';
import 'performance_patch_io.dart';
import 'game_graphics.dart';
import 'render_dragon.dart';
import 'render_dragon_io.dart';
import 'wine_game_app_io.dart';
import 'input_guard_io.dart';
import 'game_window_chrome_io.dart';
import 'player_skin_io.dart';
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
    Future<String> Function()? cookieProvider,
  }) : preferences = TestSessionPreferences(preferences, sessionId),
       api = McsApi(client: client),
       _cookieProvider = cookieProvider ?? (() async => '') {
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

  @override
  String get gameDisplayName => _joinTarget == null
      ? super.gameDisplayName
      : '${super.gameDisplayName} · $_playerName';

  @override
  bool get lanAvailable =>
      running &&
      _joinTarget == null &&
      !_closingLan &&
      _lanTransportReady &&
      _lanBridge != null &&
      _hostPackRoot != null &&
      _lanPort != null &&
      _rosterUpdated != null &&
      DateTime.now().difference(_rosterUpdated!).inSeconds < 10 &&
      _worldPlayers.isNotEmpty;
  @override
  String get lanUnavailableReason => !supportsLanPatch(selectedVersion ?? '')
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

  String? _activeWine;
  String get runtime => p.join(storage.paths.runtimes, 'wine-11.0_1-mcs-v1');
  String get wine => _activeWine ?? p.join(runtime, 'bin/wine');
  String get gamePrefix => p.join(
    storage.paths.prefixes,
    sessionId == 'default' ? 'game' : 'game-$sessionId',
  );
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
    } on FileSystemException {
      error = '无法读写开发目录，请检查磁盘连接、权限和剩余空间。';
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
    runtimeReady = await patchedWineReady(runtime);
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
    if (await patchedWineReady(runtime)) {
      runtimeReady = true;
      notice = 'Wine 已就绪。';
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
          api.client,
          Uri.parse(url),
          archive,
          expectedSha256: wineArchiveHash,
          control: _control,
          onProgress: _update,
        );
        downloaded = true;
        break;
      } on DownloadCancelled {
        rethrow;
      } catch (_) {
        _control?.check();
      }
    }
    if (!downloaded) {
      throw const DevelopmentStorageException('Wine 下载线路均不可用，请稍后重试。');
    }
    final stage = await Directory(
      storage.paths.runtimes,
    ).createTemp('.wine-install-');
    try {
      _update(const StorageMigrationProgress('解压 Wine'));
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
      _update(const StorageMigrationProgress('安装启动补丁'));
      await patchWine11(payload);
      _control?.check();
      if (await Directory(runtime).exists()) {
        throw const DevelopmentStorageException(
          '已有 Wine 目录校验未通过，请在 Finder 中保留备份后移走该目录再重试。',
        );
      }
      await Directory(payload).rename(runtime);
      runtimeReady = true;
      notice = 'Wine 与启动补丁已安装。';
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  });

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

  Future<void> _ensurePrefix(String prefix) async {
    if (!await patchedWineReady(runtime)) {
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
      _update(const StorageMigrationProgress('准备 Windows 容器'));
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
      control: _control,
      onProgress: _update,
    );
    final stage = await Directory(
      storage.paths.games,
    ).createTemp('.game-install-');
    try {
      _update(const StorageMigrationProgress('解压游戏包'));
      final input = InputFileStream(zip.path);
      try {
        await extractZipSafe(
          ZipDecoder().decodeStream(input),
          stage.path,
          control: _control,
        );
      } finally {
        input.close();
      }
      var gameRoot = stage.path;
      if (!await File(p.join(gameRoot, 'Minecraft.Windows.exe')).exists()) {
        final candidates = <Directory>[];
        await for (final entry in stage.list(followLinks: false)) {
          if (entry is Directory &&
              await File(
                p.join(entry.path, 'Minecraft.Windows.exe'),
              ).exists()) {
            candidates.add(entry);
          }
        }
        if (candidates.length != 1) {
          throw const DevelopmentStorageException('游戏包中没有唯一的游戏目录。');
        }
        gameRoot = candidates.single.path;
      }
      await verifyGameFiles(
        gameRoot,
        hashes,
        control: _control,
        onProgress: _update,
      );
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
      if (await stage.exists()) await stage.delete(recursive: true);
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
      if ((await Process.run('/usr/bin/ditto', [
            '--noextattr',
            '--norsrc',
            source,
            stage.path,
          ])).exitCode !=
          0) {
        throw const DevelopmentStorageException('复制已有游戏失败。');
      }
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
  Future<void> importMods(String path) => _operation(() async {
    await _readProjects();
    var source = p.absolute(path);
    final type = await FileSystemEntity.type(source);
    Directory? stage;
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
    try {
      final imported = await discoverModPacks(source);
      if (imported.isEmpty) {
        throw const DevelopmentStorageException(
          '没有找到有效 manifest.json；支持资源包、行为包、mcpack 和 mcaddon。',
        );
      }
      String? committed;
      if (stage != null) {
        committed = p.join(
          stage.parent.path,
          'import-${Random.secure().nextInt(1 << 30)}',
        );
        await stage.rename(committed);
      }
      final next = [...packs];
      final importedAt = DateTime.now().toUtc();
      for (final pack in imported) {
        final previous = next.where((old) => old.uuid == pack.uuid).firstOrNull;
        next.removeWhere((old) => old.uuid == pack.uuid);
        final actual = committed == null
            ? pack.directory
            : p.join(committed, p.relative(pack.directory, from: source));
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
      await _saveProjects();
      await _saveSelection();
      notice = '已导入 ${groupModProjects(imported).length} 个项目。测试前同步源文件。';
    } finally {
      if (stage != null && await stage.exists()) {
        await stage.delete(recursive: true);
      }
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

  Future<String> _roaming() async {
    final users = Directory(p.join(gamePrefix, 'drive_c', 'users'));
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
    String? dragonRuntime;
    final adaptedDragon =
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
    await _ensurePrefix(gamePrefix);
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
          if ((await Process.run('/usr/bin/ditto', [
                '--noextattr',
                '--norsrc',
                source,
                staging.path,
              ])).exitCode !=
              0) {
            throw DevelopmentStorageException('装配模组失败：${pack.name}');
          }
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
      final config = File(
        p.join(gamePrefix, 'drive_c', 'MCDevTests', 'test.cppconfig'),
      );
      final args = <String>[
        'dc_tag1=${menuOnly ? 'mod_pc_no_launcher' : 'studio_no_launcher'}',
      ];
      if (!menuOnly) {
        _hostSkin = playerSkin;
        final skinInfo = await prepareTestPlayerSkin(
          skin: _hostSkin,
          gameDirectory: gameDirectory,
          gamePrefix: gamePrefix,
        );
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
            reportPath: p.join(
              gamePrefix,
              'drive_c',
              'MCDevTests',
              'lan-roster.json',
            ),
            windowsReportPath: r'C:\MCDevTests\lan-roster.json',
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
      final assertDir = Directory(
        p.join(gamePrefix, 'drive_c', 'MCDevTests', 'assertions'),
      );
      await assertDir.create(recursive: true);
      await _saveJson(File(p.join(gameDirectory, 'netease_data.json')), {
        'Uid': api.session?.id ?? '',
        'Urs': '',
        'ServerName': 'MCS',
        'Product': 'mcstudio_mod_pc',
        'AssertCacheDir': _winPath(assertDir.path),
      });
      output = File(logPath!).openWrite();
      modLogs = await ModLogServer.start(
        marker: modCapture.marker,
        sources: modCapture.sources,
        onText: (text) {
          if (generation == _launchGeneration) output?.write(text);
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
        _activeWine = p.join(dragonRuntime, 'bin/wine');
      }
      final gameApplication = Platform.isMacOS
          ? await prepareWineGameApplication(
              dragonRuntime ?? runtime,
              metal: dragonRuntime != null,
              sessionId: sessionId,
              displayName: gameDisplayName,
            )
          : null;
      final inputGuard = Platform.isMacOS && !fullscreenShortcut
          ? await prepareFullscreenShortcutGuard(storage.paths.runtimes)
          : null;
      final chrome = gameApplication != null
          ? await prepareGameWindowChrome(storage.paths.runtimes)
          : null;
      final inputEnvironment = inputGuard != null
          ? fullscreenShortcutEnvironment(inputGuard.path)
          : <String, String>{};
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
      _game = await Process.start(
        gameApplication?.loader ?? wine,
        [_winPath(executable), ...args],
        workingDirectory: gameDirectory,
        environment: _env(
          gamePrefix,
          overrides: {
            if (gameApplication != null) ...gameApplication.environment,
            ...inputEnvironment,
            if (lanFiles != null) ...{
              'MCDEV_LAN_PATCH_LOG': _winPath(lanLog),
              'MCDEV_LAN_ROLE': _joinTarget == null ? 'host' : 'guest',
            },
            if (chrome != null)
              ...chrome.environment(
                loader: gameApplication!.loader,
                version: game.version,
                displayName: gameDisplayName,
                renderer:
                    (menuOnly ? GameRenderer.openGL : effectiveRenderer).label,
                inherited: {...Platform.environment, ...inputEnvironment},
              ),
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
        ),
      );
      running = true;
      final launchedAt = DateTime.now().toUtc();
      busy = false;
      final actualRenderer = menuOnly ? GameRenderer.openGL : effectiveRenderer;
      notice =
          '测试游戏已启动（${actualRenderer.label} · ${limit60Fps ? '60 帧上限' : '不限帧'}）。';
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
      busy = true;
      await _stopLanGuests();
      try {
        await drained.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        await _killPrefix(gamePrefix);
      }
      if (code != 0 && !_stopRequested) {
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
        await modLogs?.close();
        for (final filter in nativeFilters) {
          filter.close();
        }
        await output?.close();
      } finally {
        _lanPort = null;
        _worldPlayers = [];
        _lanBridge = null;
        running = false;
        _game = null;
        _activeWine = null;
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

  Future<void> _requestProcessExit(Process child) async {
    try {
      // WM_CLOSE first; only this application's isolated prefix is targeted.
      await _wineRun(gamePrefix, [
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
      await _killPrefix(gamePrefix);
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

String safeArchivePath(String name) {
  final value = name.replaceAll('\\', '/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value) ||
      value.split('/').contains('..') ||
      value.contains('\u0000')) {
    throw const DevelopmentStorageException('归档包含越界路径，未安装。');
  }
  return p.posix.normalize(value);
}

Future<void> extractZipSafe(
  Archive archive,
  String target, {
  DownloadControl? control,
}) async {
  final seen = <String>{};
  // Validate every entry before any write, including case-insensitive macOS conflicts.
  for (final entry in archive) {
    final relative = safeArchivePath(entry.name);
    if (entry.isSymbolicLink || !seen.add(relative.toLowerCase())) {
      throw const DevelopmentStorageException('归档包含链接或重复路径，未安装。');
    }
  }
  await Directory(target).create(recursive: true);
  for (final entry in archive) {
    control?.check();
    final relative = safeArchivePath(entry.name);
    final out = p.join(target, relative);
    if (!p.isWithin(p.normalize(target), p.normalize(out))) {
      throw const DevelopmentStorageException('归档路径不合法。');
    }
    if (entry.isFile) {
      await File(out).parent.create(recursive: true);
      final stream = OutputFileStream(out);
      try {
        entry.writeContent(stream);
      } finally {
        stream.close();
      }
    } else {
      await Directory(out).create(recursive: true);
    }
  }
}

Map<String, String> parseGamePatch(String text) {
  final data = jsonDecode(text);
  final entries = data['md5'];
  if (entries is! Map || entries.isEmpty) {
    throw const DevelopmentStorageException('游戏补丁清单无效。');
  }
  final hashes = <String, String>{};
  final lower = <String>{};
  for (final entry in entries.entries) {
    final key = safeArchivePath(entry.key as String);
    if (entry.value is! String ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(entry.value) ||
        !lower.add(key.toLowerCase())) {
      throw const DevelopmentStorageException('游戏清单包含无效摘要或重复路径。');
    }
    hashes[key] = entry.value.toLowerCase();
  }
  if (!hashes.containsKey('Minecraft.Windows.exe')) {
    throw const DevelopmentStorageException('游戏清单缺少主程序。');
  }
  return hashes;
}

Future<void> verifyGameFiles(
  String root,
  Map<String, String> hashes, {
  DownloadControl? control,
  void Function(StorageMigrationProgress)? onProgress,
}) async {
  await rejectTreeLinks(root);
  // The authoritative patch is the allowlist: extra DLLs must not be loaded.
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File) {
      final relative = p.relative(entity.path, from: root);
      if (!hashes.containsKey(relative) &&
          !['patch.json', '.mcdev-game.json'].contains(relative)) {
        await entity.delete();
      }
    }
  }
  var count = 0;
  for (final entry in hashes.entries) {
    control?.check();
    final path = p.join(root, entry.key);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        (await md5.bind(File(path).openRead()).first).toString() !=
            entry.value) {
      throw DevelopmentStorageException('游戏文件校验失败：${entry.key}');
    }
    count++;
    if (count % 100 == 0 || count == hashes.length) {
      onProgress?.call(
        StorageMigrationProgress(
          '校验游戏文件',
          completed: count,
          total: hashes.length,
        ),
      );
    }
  }
}

Future<void> rejectTreeLinks(String root) async {
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw const DevelopmentStorageException('游戏或模组文件包含符号链接，请使用完整的实际文件。');
    }
  }
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

Future<List<ModPack>> discoverModPacks(String root) async {
  final result = <ModPack>[];
  final uuids = <String>{};
  Future<void> visit(String directory, int depth) async {
    final file = File(p.join(directory, 'manifest.json'));
    if (await file.exists()) {
      final manifest = jsonDecode(await file.readAsString());
      final header = manifest['header'];
      final modules = manifest['modules'];
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
      if (!uuids.add(uuid.toLowerCase())) {
        throw const DevelopmentStorageException('项目中存在重复 UUID。');
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
      return;
    }
    if (depth == 0) return;
    await for (final entry in Directory(directory).list(followLinks: false)) {
      if (entry is Directory &&
          !p.basename(entry.path).startsWith('.') &&
          !['build', 'node_modules'].contains(p.basename(entry.path))) {
        await visit(entry.path, depth - 1);
      }
    }
  }

  await visit(await Directory(root).resolveSymbolicLinks(), 4);
  // Each directory containing sibling packs is a project. Standard BP/RP
  // containers share their outer project directory. A single-pack import keeps
  // legacy name-based matching, allowing its companion to be imported later.
  if (result.length < 2) return result;
  return [
    for (final pack in result)
      ModPack(
        name: pack.name,
        uuid: pack.uuid,
        version: pack.version,
        type: pack.type,
        directory: pack.directory,
        projectRoot:
            [
              'behavior_packs',
              'resource_packs',
            ].contains(p.basename(p.dirname(pack.directory)).toLowerCase())
            ? p.dirname(p.dirname(pack.directory))
            : p.dirname(pack.directory),
      ),
  ];
}
