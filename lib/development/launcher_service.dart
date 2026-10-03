import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/preferences.dart';
import 'development_storage.dart';
import 'mcs_api.dart';
import 'performance_patch.dart';
import 'game_graphics.dart';
import 'render_dragon.dart';
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
    // Match the MCS PNG-skin path. The game's local-only slots are not
    // populated consistently by the RenderDragon development client.
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
  });
  final String name;
  final String uuid;
  final List<int> version;
  final String type;
  final String directory;

  /// Source project directory. Absent in older registrations / single packs.
  final String? projectRoot;
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

  bool? selection(Set<String> selected) {
    final count = uuids.where(selected.contains).length;
    return count == 0
        ? false
        : count == packs.length
        ? true
        : null;
  }
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
  bool fullscreenShortcut = false;
  bool useNewWorld = false;
  String newWorldSeed = '';
  TestPlayerSkin playerSkin = TestPlayerSkin.steve;
  GameRenderer renderer = GameRenderer.openGL;
  bool get rendererSwitchSupported => supportsRendererSwitch(selectedVersion);
  GameRenderer get effectiveRenderer =>
      rendererSwitchSupported ? renderer : GameRenderer.openGL;
  bool get performanceOptimizationSupported =>
      effectiveRenderer == GameRenderer.openGL &&
      supportsPerformancePatch(selectedVersion);
  bool get renderDragonCompatibilitySupported =>
      supportsRenderDragonPatch(selectedVersion);
  bool get vibrantVisualsSupported =>
      renderDragonCompatibilitySupported &&
      effectiveRenderer == GameRenderer.renderDragon;
  final Set<String> selectedPacks = {};
  List<ModProject> get projects => groupModProjects(packs);
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
