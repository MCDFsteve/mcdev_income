import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/preferences.dart';
import 'development_storage.dart';
import 'mcs_api.dart';
import 'performance_patch.dart';
import 'game_graphics.dart';
import 'render_dragon.dart';
import 'platform/development_capabilities.dart';
export 'game_graphics.dart' show GameRenderer, GameClientType;
import 'launcher_stub.dart' if (dart.library.io) 'launcher_io.dart' as backend;

Future<DevelopmentLauncher> openDevelopmentLauncher(
  DevelopmentStorage storage,
  PreferenceStore preferences, {
  Future<String> Function()? cookieProvider,
  String sessionId = 'default',
}) => backend.openDevelopmentLauncher(
  storage,
  preferences,
  cookieProvider: cookieProvider,
  sessionId: sessionId,
);

class LocalGame {
  const LocalGame(
    this.version,
    this.directory, {
    this.architecture = GameArchitecture.unknown,
    this.channels = const [],
    this.clientType = GameClientType.openGL,
  });
  final String version;
  final String directory;
  final GameArchitecture architecture;
  final List<GameChannel> channels;
  final GameClientType clientType;
}

enum TestPlayerSkin {
  steve('steve.png'),
  alex('alex.png');

  const TestPlayerSkin(this.textureFile);
  final String textureFile;

  Map<String, Object> skinInfo(String texturePath) => {
    'skin': texturePath,
    // MCS PNG-import metadata for Mac/Wine. Native Windows uses the runtime's
    // packaged-skin selection instead; its PNG imports can select the dummy.
    'sync': true,
    'in_package': false,
    'slim': this == TestPlayerSkin.alex,
    // Keep the built-in IDs used by MCS GetSkinItemId.
    'skin_iid': this == TestPlayerSkin.alex ? '-2' : '-1',
  };
}

class ModPack {
  const ModPack({
    required this.name,
    required this.uuid,
    required this.version,
    required this.type,
    required this.directory,
    this.projectRoot,
    this.importedAt,
    this.lastLaunchedAt,
  });
  final String name;
  final String uuid;
  final List<int> version;
  final String type;
  final String directory;

  /// Source project directory. Absent in older registrations / single packs.
  final String? projectRoot;
  final DateTime? importedAt;
  final DateTime? lastLaunchedAt;

  ModPack withLastLaunch(DateTime time) => ModPack(
    name: name,
    uuid: uuid,
    version: version,
    type: type,
    directory: directory,
    projectRoot: projectRoot,
    importedAt: importedAt,
    lastLaunchedAt: time,
  );
}

String modDisplayName(String name) =>
    name.replaceAll(RegExp(r'§[0-9a-fk-or]', caseSensitive: false), '').trim();

String _projectDisplayName(List<ModPack> packs) {
  // A paired resource pack can have a different title. Prefer the behavior
  // pack's manifest title rather than replacing both with the folder name.
  for (final pack in [
    ...packs.where((pack) => pack.type == 'data'),
    ...packs.where((pack) => pack.type != 'data'),
  ]) {
    final name = modDisplayName(pack.name);
    if (name.isNotEmpty) return name;
  }
  return p.basename(packs.first.projectRoot ?? packs.first.directory);
}

class ModProject {
  const ModProject({required this.id, required this.name, required this.packs});
  final String id;
  final String name;
  final List<ModPack> packs;
  Iterable<String> get uuids => packs.map((pack) => pack.uuid);

  DateTime? get importedAt => packs
      .map((pack) => pack.importedAt)
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (earliest, time) =>
            earliest == null || time.isBefore(earliest) ? time : earliest,
      );

  DateTime? get lastLaunchedAt => packs
      .map((pack) => pack.lastLaunchedAt)
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (latest, time) =>
            latest == null || time.isAfter(latest) ? time : latest,
      );

  bool? selection(Set<String> selected) {
    final count = uuids.where(selected.contains).length;
    return count == 0
        ? false
        : count == packs.length
        ? true
        : null;
  }
}

enum ProjectSortOrder {
  importedNewest('导入时间：最新在前'),
  importedOldest('导入时间：最早在前'),
  launchedNewest('启动时间：最近在前'),
  launchedOldest('启动时间：最早在前'),
  nameAscending('名称字母：A → Z'),
  nameDescending('名称字母：Z → A');

  const ProjectSortOrder(this.label);
  final String label;
}

List<ModProject> sortModProjects(
  Iterable<ModProject> projects,
  ProjectSortOrder order,
) {
  final indexed = projects.indexed.toList();
  int imported((int, ModProject) a, (int, ModProject) b) {
    final first = a.$2.importedAt;
    final second = b.$2.importedAt;
    // Legacy registrations have no timestamps. Their saved insertion order
    // remains the best available history, before newly imported projects.
    final comparison = first == null
        ? (second == null ? 0 : -1)
        : second == null
        ? 1
        : first.compareTo(second);
    return comparison != 0 ? comparison : a.$1.compareTo(b.$1);
  }

  indexed.sort((a, b) {
    switch (order) {
      case ProjectSortOrder.importedNewest:
        return imported(b, a);
      case ProjectSortOrder.importedOldest:
        return imported(a, b);
      case ProjectSortOrder.launchedNewest:
      case ProjectSortOrder.launchedOldest:
        final first = a.$2.lastLaunchedAt;
        final second = b.$2.lastLaunchedAt;
        // Unlaunched projects always follow launched ones, in either direction.
        if (first == null && second != null) return 1;
        if (second == null && first != null) return -1;
        final comparison = first == null ? 0 : first.compareTo(second!);
        if (comparison != 0) {
          return order == ProjectSortOrder.launchedNewest
              ? -comparison
              : comparison;
        }
        return imported(b, a);
      case ProjectSortOrder.nameAscending:
      case ProjectSortOrder.nameDescending:
        final comparison = a.$2.name.toLowerCase().compareTo(
          b.$2.name.toLowerCase(),
        );
        if (comparison != 0) {
          return order == ProjectSortOrder.nameAscending
              ? comparison
              : -comparison;
        }
        return a.$1.compareTo(b.$1);
    }
  });
  return indexed.map((entry) => entry.$2).toList();
}

List<ModProject> groupModProjects(Iterable<ModPack> packs) {
  final sources = packs.toList();
  final namedRoots = <String, Set<String>>{};
  for (final pack in sources) {
    if (pack.projectRoot != null) {
      namedRoots
          .putIfAbsent(p.normalize(pack.projectRoot!), () => {})
          .add(modDisplayName(pack.name));
    }
  }
  final groups = <String, List<ModPack>>{};
  for (final pack in sources) {
    final name = modDisplayName(pack.name);
    final root = p.normalize(pack.projectRoot ?? p.dirname(pack.directory));
    // Legacy rows have no import provenance. Match name only within one parent
    // directory, so identically named projects in different roots stay separate.
    final id =
        pack.projectRoot == null && !(namedRoots[root]?.contains(name) ?? false)
        ? '$root\u0000$name'
        : root;
    groups.putIfAbsent(id, () => []).add(pack);
  }
  return [
    for (final entry in groups.entries)
      ModProject(
        id: entry.key,
        name: _projectDisplayName(entry.value),
        packs: List.unmodifiable(entry.value),
      ),
  ];
}

enum DevelopmentPlayerStatus { starting, connected, disconnected, failed }

class DevelopmentPlayer {
  const DevelopmentPlayer({
    required this.id,
    required this.name,
    this.skin,
    required this.host,
    required this.status,
    this.canStop = false,
    this.error,
  });
  final String id;
  final String name;

  /// Only known for launcher-managed players. LAN reports do not include skin.
  final TestPlayerSkin? skin;
  final bool host;
  final DevelopmentPlayerStatus status;

  /// The launcher can close this local guest window, independently of whether
  /// its player is currently inside the world.
  final bool canStop;
  final String? error;
}

String? validateDevelopmentPlayerName(String value) {
  final name = value.trim();
  if (name.isEmpty) return '请输入玩家名字。';
  // mp_username is a 16-byte UTF-8 field in the game, not 16 characters.
  // Reject overlong names instead of allowing native truncation mid-character.
  if (utf8.encode(name).length > 16) {
    return '玩家名字最多 16 字节，中文通常最多 5 个字。';
  }
  if (RegExp(r'[\x00-\x1f\x7f§]').hasMatch(name)) {
    return '玩家名字不能包含控制字符或颜色代码。';
  }
  return null;
}

String suggestedDevelopmentPlayerName(Iterable<String> reservedNames) {
  final reserved = reservedNames.toSet();
  for (var index = 1; ; index++) {
    var name = '测试玩家$index';
    if (utf8.encode(name).length > 16) name = '玩家$index';
    if (utf8.encode(name).length > 16) name = 'P${index.toRadixString(36)}';
    if (!reserved.contains(name)) return name;
  }
}

abstract class DevelopmentLauncher extends ChangeNotifier {
  bool busy = false;
  bool running = false;
  bool runtimeReady = false;
  bool loggedIn = false;
  String? error;
  String? notice;
  String? logPath;
  StorageMigrationProgress? progress;
  GameCatalog? catalog;
  GamePackage? get latestPackage => catalog?.stable;
  List<GamePackage> get availableGames => catalog?.packages ?? const [];
  List<LocalGame> games = [];
  List<ModPack> packs = [];
  String? selectedVersion;
  bool performanceOptimization = false;
  bool limit60Fps = true;
  bool vibrantVisuals = false;
  bool showDeveloperConsole = false;
  bool disableCompanion = true;
  bool fullscreenShortcut = false;
  bool useNewWorld = false;
  String newWorldSeed = '';
  TestPlayerSkin playerSkin = TestPlayerSkin.steve;
  GameRenderer renderer = GameRenderer.openGL;
  DevelopmentCapabilities get capabilities => DevelopmentCapabilities.macOS;
  bool get rendererSwitchSupported => supportsRendererSwitch(selectedVersion);
  GameRenderer get effectiveRenderer =>
      rendererSwitchSupported ? renderer : GameRenderer.openGL;
  bool get performanceOptimizationSupported =>
      capabilities.performancePatch &&
      effectiveRenderer == GameRenderer.openGL &&
      supportsPerformancePatch(selectedVersion);
  bool get renderDragonCompatibilitySupported =>
      capabilities.metalRenderer && supportsRenderDragonPatch(selectedVersion);
  bool get vibrantVisualsSupported =>
      renderDragonCompatibilitySupported &&
      effectiveRenderer == GameRenderer.renderDragon;
  final Set<String> selectedPacks = {};
  ProjectSortOrder projectSortOrder = ProjectSortOrder.importedNewest;
  List<ModProject> get projects => groupModProjects(packs);
  List<ModProject> get sortedProjects =>
      sortModProjects(projects, projectSortOrder);
  String get tabTitle {
    final names = projects
        .where((project) => project.uuids.any(selectedPacks.contains))
        .map((project) => project.name);
    return names.isEmpty ? '原版测试' : names.join(' + ');
  }

  String get gameDisplayName => '我的世界测试 · $tabTitle';

  bool get lanAvailable => false;
  String get lanUnavailableReason => '请等待此测试页的世界加载完成。';
  bool get hasLanPlayers => false;
  List<DevelopmentPlayer> get players => const [];
  Future<void> launchLanPlayer({
    required String name,
    required TestPlayerSkin skin,
  }) => Future.error(const DevelopmentStorageException('请先启动此测试页的世界。'));
  Future<void> stopLanPlayer(String id) async {}

  Future<void> refresh();
  Future<void> installWine();

  /// Platform-neutral entry point; installWine remains for existing clients.
  Future<void> installRuntime() => installWine();
  Future<void> queryLatest();
  Future<void> installLatest();
  Future<void> queryVersions();
  Future<void> installVersion(String version);
  Future<void> importGame(String directory);
  Future<void> importMods(String path);
  Future<void> removePack(String uuid);
  Future<void> launchTest({
    required String worldName,
    required bool creative,
    required bool menuOnly,
    String? seed,
  });
  Future<void> stopGame();
  void cancel();
  Future<void> chooseProjectSortOrder(ProjectSortOrder value) async {
    projectSortOrder = value;
    notifyListeners();
  }

  Future<void> chooseNewWorld(bool enabled) async {
    useNewWorld = enabled;
    notifyListeners();
  }

  Future<void> choosePerformanceOptimization(bool enabled) async {
    performanceOptimization = enabled;
    notifyListeners();
  }

  Future<void> chooseFrameLimit(bool enabled) async {
    limit60Fps = enabled;
    notifyListeners();
  }

  Future<void> chooseDeveloperConsole(bool enabled) async {
    showDeveloperConsole = enabled;
    notifyListeners();
  }

  Future<void> chooseDisableCompanion(bool disabled) async {
    disableCompanion = disabled;
    notifyListeners();
  }

  Future<void> chooseFullscreenShortcut(bool enabled) async {
    fullscreenShortcut = enabled;
    notifyListeners();
  }

  Future<void> choosePlayerSkin(TestPlayerSkin value) async {
    playerSkin = value;
    notifyListeners();
  }

  Future<void> chooseRenderer(GameRenderer value) async {
    renderer = value;
    notifyListeners();
  }

  Future<void> chooseVibrantVisuals(bool enabled) async {
    vibrantVisuals = enabled;
    notifyListeners();
  }

  Future<void> chooseVersion(String version) async {
    selectedVersion = version;
    notifyListeners();
  }

  Future<void> togglePack(String uuid, bool selected) async {
    await togglePacks([uuid], selected);
  }

  Future<void> togglePacks(Iterable<String> uuids, bool selected) async {
    selected ? selectedPacks.addAll(uuids) : selectedPacks.removeAll(uuids);
    notifyListeners();
  }

  Future<void> removePacks(Iterable<String> uuids) async {
    for (final uuid in uuids.toList()) {
      await removePack(uuid);
    }
  }
}
