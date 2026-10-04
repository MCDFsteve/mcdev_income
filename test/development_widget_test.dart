import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:mcdev_income/main.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/mcs_api.dart';
import 'package:mcdev_income/development/version_dialog.dart';

Widget host(Widget page, {bool dark = false}) => AppThemeController(
  notifier: ValueNotifier(ThemeMode.system),
  child: MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? OreThemeData.dark() : OreThemeData.light()],
    ),
    home: Scaffold(body: page),
  ),
);

class FakeStorage extends DevelopmentStorage {
  @override
  String get lockPath => '/test/development.lock';
  @override
  DevelopmentPaths paths = const DevelopmentPaths('/test/development');
  @override
  Future<DevelopmentStorageStatus> inspect() async =>
      const DevelopmentStorageStatus(initialized: false, exists: false);
  @override
  Future<void> initialize({String? root}) async {}
  @override
  Future<void> useExisting(String root) async {}
  @override
  Future<void> migrateTo(
    String root, {
    void Function(StorageMigrationProgress)? onProgress,
  }) async {}
  @override
  Future<void> reveal(String path) async {}
}

class FakeLauncher extends DevelopmentLauncher {
  FakeLauncher() {
    runtimeReady = true;
    loggedIn = true;
    games = [const LocalGame('3.8.0.313229', '/game')];
    selectedVersion = games.first.version;
    packs = [
      const ModPack(
        name: 'Test pack',
        uuid: 'id',
        version: [1, 0, 0],
        type: 'data',
        directory: '/project',
      ),
    ];
  }
  int launches = 0;
  int refreshes = 0;
  String? lastSeed;
  bool? lastNewWorld;
  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  Future<void> installWine() async {}
  @override
  Future<void> queryLatest() async {}
  @override
  Future<void> installLatest() async {}
  @override
  Future<void> queryVersions() async {
    notifyListeners();
  }

  final List<String> installations = [];
  @override
  Future<void> installVersion(String version) async {
    installations.add(version);
    games.add(LocalGame(version, '/game/$version'));
    notifyListeners();
  }

  @override
  Future<void> importGame(String directory) async {}
  @override
  Future<void> importMods(String path) async {}
  @override
  Future<void> removePack(String uuid) async {
    packs.removeWhere((pack) => pack.uuid == uuid);
    selectedPacks.remove(uuid);
    notifyListeners();
  }

  @override
  Future<void> launchTest({
    required String worldName,
    required bool creative,
    required bool menuOnly,
    String? seed,
  }) async {
    launches++;
    lastSeed = seed;
    lastNewWorld = useNewWorld;
    running = true;
    busy = true;
    notifyListeners();
  }

  @override
  Future<void> stopGame() async {
    running = false;
    busy = false;
    notice = 'stopped';
    notifyListeners();
  }

  @override
  void cancel() {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('development tab is hardware gated and lazily constructed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var built = 0;
    await tester.pumpWidget(
      host(
        HomeShell(
          developmentSupported: false,
          developmentPageBuilder: (_) {
            built++;
            return const Text('developer content');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('开发'), findsNothing);
    expect(built, 0);
    await tester.pumpWidget(
      host(
        HomeShell(
          key: UniqueKey(),
          developmentSupported: true,
          developmentPageBuilder: (_) {
            built++;
            return const Text('developer content');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built, 0);
    await tester.tap(find.text('开发'));
    await tester.pumpAndSettle();
    expect(find.text('developer content'), findsOneWidget);
    expect(built, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets('asynchronous hardware detection keeps Settings selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final support = Completer<bool>();
    await tester.pumpWidget(
      host(HomeShell(developmentSupportProbe: () => support.future)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    support.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('开发'), findsOneWidget);
    expect(find.text('开发').hitTestable(), findsOneWidget);
    expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'desktop groups projects, keeps test controls visible and shows pack dialog ${dark ? "dark" : "light"}',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final launcher = FakeLauncher()
          ..projectSortOrder = ProjectSortOrder.importedOldest;
        launcher.packs = [
          const ModPack(
            name: '§lProject  ',
            uuid: 'bp',
            version: [1, 0, 0],
            type: 'data',
            directory: '/project/BP',
            projectRoot: '/project',
          ),
          const ModPack(
            name: '§bProject textures ',
            uuid: 'rp',
            version: [1, 0, 0],
            type: 'resources',
            directory: '/project/RP',
            projectRoot: '/project',
          ),
          for (var i = 0; i < 30; i++)
            ModPack(
              name: 'Other $i',
              uuid: 'id-$i',
              version: const [1, 0, 0],
              type: 'data',
              directory: '/other/$i/BP',
            ),
        ];
        launcher.selectedPacks.add('bp');
        await tester.pumpWidget(
          host(
            DevelopmentEnvironmentPanel(
              storage: FakeStorage(),
              launcherFactory: () async => launcher,
              storageSection: const OreCard(child: Text('Directory')),
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('development-desktop')),
          findsOneWidget,
        );
        expect(find.text('Project'), findsNWidgets(2));
        expect(find.text('/project/BP'), findsNothing);
        expect(find.textContaining('部分启用'), findsOneWidget);
        final wine = tester.getRect(find.text('Wine 运行环境'));
        final projects = tester.getRect(find.text('本地项目'));
        expect(projects.left, greaterThan(wine.right));
        final launch = find.widgetWithText(OreButton, '启动测试');
        expect(launch.hitTestable(), findsOneWidget);
        await tester.tap(find.text('Project').last);
        await tester.pumpAndSettle();
        expect(launcher.selectedPacks, containsAll(['bp', 'rp']));
        expect(find.textContaining('部分启用'), findsNothing);
        final info = find
            .byWidgetPredicate(
              (widget) =>
                  widget is OreIconButton && widget.tooltip == '查看项目包详情',
            )
            .first;
        await tester.tap(info);
        await tester.pumpAndSettle();
        expect(find.byType(OreAlertDialog), findsOneWidget);
        expect(find.text('/project/BP'), findsOneWidget);
        expect(find.text('/project/RP'), findsOneWidget);
        expect(find.text('行为 / 脚本包'), findsOneWidget);
        expect(find.text('资源包'), findsOneWidget);
        await tester.tap(find.widgetWithText(OreButton, '移除项目'));
        await tester.pumpAndSettle();
        expect(launcher.projects.length, 30);
        expect(launcher.selectedPacks, isEmpty);
        expect(find.text('Project'), findsNothing);
        final projectList = find.byKey(
          const PageStorageKey('development-projects'),
        );
        await tester.drag(projectList, const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(launch.hitTestable(), findsOneWidget);
        await tester.tap(launch);
        await tester.pumpAndSettle();
        expect(launcher.launches, 1);
        await tester.tap(find.widgetWithText(OreButton, '退出测试'));
        await tester.pumpAndSettle();
        expect(launcher.running, false);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'launch has top priority and status never changes pane geometry',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final launcher = FakeLauncher();
      await tester.pumpWidget(
        host(
          DevelopmentEnvironmentPanel(
            storage: FakeStorage(),
            launcherFactory: () async => launcher,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final launch = find.byKey(const ValueKey('development-launch'));
      final projects = find.text('本地项目');
      final status = find.byKey(const ValueKey('development-status'));
      final launchRect = tester.getRect(launch);
      final projectRect = tester.getRect(projects);
      final statusRect = tester.getRect(status);
      expect(launchRect.bottom, lessThan(projectRect.top));
      for (final state in ['progress', 'error', 'notice', 'running']) {
        launcher.busy = state == 'progress';
        launcher.running = state == 'running';
        launcher.progress = state == 'progress'
            ? const StorageMigrationProgress('同步模组', completed: 1, total: 2)
            : null;
        launcher.error = state == 'error'
            ? List.filled(30, '长错误消息').join('\n')
            : null;
        launcher.notice = state == 'notice' ? '游戏准备完毕。' : null;
        launcher.notifyListeners();
        await tester.pumpAndSettle();
        expect(tester.getRect(launch), launchRect);
        expect(tester.getRect(projects), projectRect);
        expect(tester.getRect(status), statusRect);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'version manager filters beta, installs chosen package and selects one coexisting version',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final launcher = FakeLauncher();
      const stable = '3.8.0.313229', beta = '3.9.0.7';
      launcher.catalog = GameCatalog.fromJson({
        'stable_x64': stable,
        'beta_x64': beta,
        'entities': {
          for (final version in [stable, beta, '3.10.0.1'])
            version: {
              'url': 'https://x19.gdl.netease.com/Win64.$version/patch.json',
              'md5': 'a' * 32,
            },
          '2.0.0.1': {
            'url': 'https://x19.gdl.netease.com/Win32.2.0.0.1/patch.json',
            'md5': 'a' * 32,
          },
        },
      });
      await tester.pumpWidget(
        host(
          DevelopmentEnvironmentPanel(
            storage: FakeStorage(),
            launcherFactory: () async => launcher,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OreButton, '浏览可下载版本'));
      await tester.pumpAndSettle();
      expect(find.byType(DevelopmentVersionDialog), findsOneWidget);
      expect(find.text('3.10.0.1'), findsOneWidget);
      expect(find.text('2.0.0.1'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('version-channel-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(find.text(beta), findsOneWidget);
      expect(find.text('3.10.0.1'), findsNothing);
      await tester.tap(find.widgetWithText(OreButton, '安装'));
      await tester.pumpAndSettle();
      expect(launcher.installations, [beta]);
      expect(launcher.selectedVersion, stable);
      expect(launcher.games.length, 2);
      await tester.tap(find.widgetWithText(OreButton, '使用此版本'));
      await tester.pumpAndSettle();
      expect(find.byType(DevelopmentVersionDialog), findsNothing);
      expect(launcher.selectedVersion, beta);
      expect(find.text('$beta · 已安装'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('active-game-version')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$stable · 已安装'));
      await tester.pumpAndSettle();
      expect(launcher.selectedVersion, stable);
      expect(launcher.games.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'download version search and all architecture filter fit narrow dialog',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final launcher = FakeLauncher();
      launcher.catalog = GameCatalog.fromJson({
        'entities': {
          '2.0.0.1': {
            'url': 'https://x19.gdl.netease.com/Win32.2.0.0.1/patch.json',
            'md5': 'a' * 32,
          },
        },
      });
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => OreButton(
              onPressed: () => showOreDialog<void>(
                context: context,
                builder: (_) => DevelopmentVersionDialog(
                  launcher: launcher,
                  downloads: true,
                  onImport: () async {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('version-architecture-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部架构'));
      await tester.pumpAndSettle();
      expect(find.text('2.0.0.1'), findsOneWidget);
      await tester.enterText(find.byType(OreTextField), '9.9');
      await tester.pumpAndSettle();
      expect(find.text('没有符合筛选条件的版本。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final size in [
      const Size(800, 600),
      const Size(1024, 600),
      const Size(1100, 700),
      const Size(1440, 600),
    ]) {
      testWidgets(
        'desktop columns scroll independently $size ${dark ? "dark" : "light"}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final launcher = FakeLauncher();
          launcher.packs = [
            for (var i = 0; i < 30; i++)
              ModPack(
                name: 'Project $i',
                uuid: 'id-$i',
                version: const [1, 0, 0],
                type: 'data',
                directory: '/projects/$i',
              ),
          ];
          await tester.pumpWidget(
            host(
              HomeShell(
                developmentSupported: true,
                developmentPageBuilder: (_) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: DevelopmentEnvironmentPanel(
                    storage: FakeStorage(),
                    launcherFactory: () async => launcher,
                    storageSection: const OreCard(
                      child: SizedBox(height: 600, child: Text('Directory')),
                    ),
                  ),
                ),
              ),
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('开发'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('development-desktop')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('development-single-column')),
            findsNothing,
          );
          final environment = find.byKey(
            const PageStorageKey('development-environment'),
          );
          final projectRows = find.byKey(
            const PageStorageKey('development-projects'),
          );
          final projects = projectRows.evaluate().isNotEmpty
              ? projectRows
              : find.byKey(
                  const PageStorageKey('development-projects-compact'),
                );
          expect(environment, findsOneWidget);
          expect(projects, findsOneWidget);
          final environmentScrollable = find
              .descendant(of: environment, matching: find.byType(Scrollable))
              .first;
          final projectScrollable = find
              .descendant(of: projects, matching: find.byType(Scrollable))
              .first;
          final environmentPosition = tester
              .state<ScrollableState>(environmentScrollable)
              .position;
          final projectPosition = tester
              .state<ScrollableState>(projectScrollable)
              .position;
          expect(
            tester.getRect(projects).left,
            greaterThan(tester.getRect(environment).right),
          );
          final launchRegion = find.byKey(
            const ValueKey('development-launch-region'),
          );
          final launchRect = tester.getRect(launchRegion);
          final directoryRect = tester.getRect(find.text('Directory'));
          final status = find.byKey(const ValueKey('development-status'));
          final statusRect = tester.getRect(status);
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(projects),
              scrollDelta: const Offset(0, 240),
            ),
          );
          await tester.pumpAndSettle();
          expect(projectPosition.pixels, greaterThan(0));
          expect(environmentPosition.pixels, 0);
          expect(tester.getRect(find.text('Directory')), directoryRect);
          expect(tester.getRect(launchRegion), launchRect);
          expect(tester.getRect(status), statusRect);
          await tester.scrollUntilVisible(
            find.text('Project 29'),
            500,
            scrollable: projectScrollable,
          );
          await tester.pumpAndSettle();
          expect(find.text('Project 29').hitTestable(), findsOneWidget);
          expect(environmentPosition.pixels, 0);
          expect(tester.getRect(launchRegion), launchRect);
          expect(tester.getRect(status), statusRect);
          final projectOffset = projectPosition.pixels;
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(environment),
              scrollDelta: const Offset(0, 240),
            ),
          );
          await tester.pumpAndSettle();
          expect(environmentPosition.pixels, greaterThan(0));
          expect(projectPosition.pixels, projectOffset);
          expect(tester.getRect(launchRegion), launchRect);
          expect(tester.getRect(status), statusRect);
          await tester.scrollUntilVisible(
            find.text('Wine 运行环境'),
            300,
            scrollable: environmentScrollable,
          );
          await tester.pumpAndSettle();
          expect(find.text('Wine 运行环境').hitTestable(), findsOneWidget);
          expect(projectPosition.pixels, projectOffset);
          expect(
            find.byKey(const ValueKey('development-launch')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('tall desktop at the column breakpoint fits expanded settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final launcher = FakeLauncher()..useNewWorld = true;
    await tester.pumpWidget(
      host(
        DevelopmentEnvironmentPanel(
          storage: FakeStorage(),
          launcherFactory: () async => launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('development-desktop')), findsOneWidget);
    await tester.ensureVisible(find.text('本地项目'));
    await tester.pumpAndSettle();
    expect(find.text('本地项目').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text uses two columns when their scaled widths fit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final launcher = FakeLauncher()..useNewWorld = true;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: DevelopmentEnvironmentPanel(
              storage: FakeStorage(),
              launcherFactory: () async => launcher,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('development-desktop')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('development-world-name')),
      'Large text world',
    );
    await tester.ensureVisible(find.text('本地项目'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('本地项目')).left,
      greaterThan(tester.getRect(find.text('Wine 运行环境')).right),
    );
    expect(find.text('本地项目').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(800, 900);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('development-single-column')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('development-world-name')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Large text world'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive resize preserves launcher and test world input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final launcher = FakeLauncher();
    var factories = 0;
    await tester.pumpWidget(
      host(
        DevelopmentEnvironmentPanel(
          storage: FakeStorage(),
          launcherFactory: () async {
            factories++;
            return launcher;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(OreTextField), 'Retained world');
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('development-single-column')),
      findsOneWidget,
    );
    final launch = find.widgetWithText(OreButton, '启动测试');
    await tester.scrollUntilVisible(
      launch,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('development-single-column')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Retained world'), findsOneWidget);
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(factories, 1);
    expect(find.textContaining('Retained world'), findsOneWidget);
    expect(launch.hitTestable(), findsOneWidget);
    // Short desktop windows keep independent panes and scroll launch settings.
    tester.view.physicalSize = const Size(1280, 480);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('development-desktop')), findsOneWidget);
    expect(launch.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 320);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('development-desktop')), findsOneWidget);
    await tester.scrollUntilVisible(
      launch,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('development-launch-controls')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final supported in [true, false]) {
    testWidgets(
      'Vibrant Visuals is gated by the adapted version ($supported)',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final launcher = FakeLauncher();
        final version = supported ? '3.10.0.420447' : '3.9.0.1';
        launcher.games = [LocalGame(version, '/game')];
        launcher.selectedVersion = version;
        await tester.pumpWidget(
          host(
            DevelopmentEnvironmentPanel(
              storage: FakeStorage(),
              launcherFactory: () async => launcher,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        expect(find.text('灵动视效（实验性）'), findsNothing);
        await tester.tap(find.text('渲染龙'));
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(OreCheckboxListTile, '灵动视效（实验性）');
        expect(toggle, findsOneWidget);
        final widget = tester.widget<OreCheckboxListTile>(toggle);
        expect(widget.onChanged != null, supported);
        if (supported) {
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(launcher.vibrantVisuals, isTrue);
        } else {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is OreTooltip &&
                  widget.message.contains('当前版本尚未适配灵动视效'),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'development controls fit narrow ${dark ? 'dark' : 'light'} layout and launch/stop',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final launcher = FakeLauncher();
        await tester.pumpWidget(
          host(
            ListView(
              children: [
                DevelopmentEnvironmentPanel(
                  storage: FakeStorage(),
                  launcherFactory: () async => launcher,
                ),
              ],
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.widgetWithText(OreButton, '启动测试');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(launcher.launches, 1);
        final stop = find.widgetWithText(OreButton, '退出测试');
        expect(stop, findsOneWidget);
        await tester.ensureVisible(stop);
        await tester.tap(stop);
        await tester.pumpAndSettle();
        expect(launcher.running, false);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
