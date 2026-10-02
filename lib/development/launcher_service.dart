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
}) => backend.openDevelopmentLauncher(
  storage,
  preferences,
  cookieProvider: cookieProvider,
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
        name:
            modDisplayName(entry.value.first.name).isEmpty ||
                entry.value
                        .map((pack) => modDisplayName(pack.name))
                        .toSet()
                        .length >
                    1
            ? p.basename(
                entry.value.first.projectRoot ?? entry.value.first.directory,
              )
            : modDisplayName(entry.value.first.name),
        packs: List.unmodifiable(entry.value),
      ),
  ];
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
  });
  Future<void> stopGame();
  void cancel();
  Future<void> choosePerformanceOptimization(bool enabled) async {
    performanceOptimization = enabled;
    notifyListeners();
  }

  Future<void> chooseFrameLimit(bool enabled) async {
    limit60Fps = enabled;
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
