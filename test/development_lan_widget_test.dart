import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';

import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

class _LanLauncher extends FakeLauncher {
  bool ready = false;
  String? unavailableMessage;
  final roster = <DevelopmentPlayer>[];
  final requests = <({String name, TestPlayerSkin skin})>[];
  final stopped = <String>[];

  @override
  bool get lanAvailable => ready;
  @override
  String get lanUnavailableReason =>
      unavailableMessage ?? super.lanUnavailableReason;
  @override
  bool get hasLanPlayers =>
      requests.isNotEmpty || roster.any((player) => !player.host);
  @override
  List<DevelopmentPlayer> get players => List.unmodifiable(roster);

  void readyHost(bool value) {
    ready = value;
    running = value;
    busy = value;
    roster.removeWhere((player) => player.host);
    if (value) {
      roster.insert(
        0,
        const DevelopmentPlayer(
          id: 'host',
          name: '房主玩家',
          skin: TestPlayerSkin.steve,
          host: true,
          status: DevelopmentPlayerStatus.connected,
        ),
      );
    }
    notifyListeners();
  }

  @override
  Future<void> launchLanPlayer({
    required String name,
    required TestPlayerSkin skin,
  }) async {
    requests.add((name: name, skin: skin));
    roster.add(
      DevelopmentPlayer(
        id: 'guest-${requests.length}',
        name: name,
        skin: skin,
        host: false,
        canStop: true,
        status: DevelopmentPlayerStatus.starting,
      ),
    );
    notifyListeners();
  }

  void setStatus(
    String id,
    DevelopmentPlayerStatus status, {
    String? error,
    bool? canStop,
  }) {
    final index = roster.indexWhere((player) => player.id == id);
    final player = roster[index];
    roster[index] = DevelopmentPlayer(
      id: player.id,
      name: player.name,
      skin: player.skin,
      host: player.host,
      status: status,
      canStop: canStop ?? player.canStop,
      error: error,
    );
    notifyListeners();
  }

  @override
  Future<void> stopLanPlayer(String id) async {
    stopped.add(id);
    setStatus(id, DevelopmentPlayerStatus.disconnected, canStop: false);
  }

  void addExternal(String name) {
    roster.add(
      DevelopmentPlayer(
        id: 'external-player',
        name: name,
        host: false,
        status: DevelopmentPlayerStatus.connected,
      ),
    );
    notifyListeners();
  }
}

void main() {
  void desktop(WidgetTester tester, {Size size = const Size(1280, 900)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> panel(WidgetTester tester, _LanLauncher launcher) async {
    await tester.pumpWidget(
      host(
        DevelopmentEnvironmentPanel(
          storage: FakeStorage(),
          launcherFactory: () async => launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey('development-$name'));

  Future<void> join(
    WidgetTester tester,
    String name, {
    bool alex = false,
  }) async {
    await tester.ensureVisible(key('lan-test'));
    await tester.tap(key('lan-test'));
    await tester.pumpAndSettle();
    await tester.enterText(key('lan-player-name'), name);
    if (alex) {
      await tester.tap(
        find.descendant(
          of: key('lan-launch-dialog'),
          matching: find.text('艾利克斯（细手臂）'),
        ),
      );
    }
    await tester.tap(key('start-lan-test'));
    await tester.pumpAndSettle();
  }

  testWidgets('LAN readiness enables repeated independent player launches', (
    tester,
  ) async {
    desktop(tester);
    final launcher = _LanLauncher();
    await panel(tester, launcher);
    expect(tester.widget<OreButton>(key('lan-test')).onPressed, isNull);
    expect(key('lan-players'), findsNothing);

    launcher.readyHost(true);
    await tester.pumpAndSettle();
    expect(launcher.busy, isTrue);
    expect(tester.widget<OreButton>(key('lan-test')).onPressed, isNotNull);
    await join(tester, '  测试玩家1  ', alex: true);
    expect(launcher.requests.single.name, '测试玩家1');
    expect(launcher.requests.single.skin, TestPlayerSkin.alex);
    expect(key('lan-players'), findsOneWidget);
    expect(tester.widget<OreButton>(key('lan-test')).onPressed, isNotNull);
    await tester.tap(key('lan-test'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OreTextField>(key('lan-player-name')).controller!.text,
      '测试玩家2',
    );
    await tester.tap(find.widgetWithText(OreButton, '取消'));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 8; i++) {
      await join(tester, '玩家$i');
    }
    expect(launcher.requests.length, 9);
    expect(launcher.requests.last.skin, TestPlayerSkin.steve);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player roster reflects actual join status and guest shutdown', (
    tester,
  ) async {
    desktop(tester);
    final launcher = _LanLauncher()..readyHost(true);
    await panel(tester, launcher);
    await join(tester, '加入的玩家');
    await tester.tap(key('lan-players'));
    await tester.pumpAndSettle();
    expect(find.text('当前世界内 1 人'), findsOneWidget);
    expect(find.textContaining('正在加入'), findsOneWidget);
    expect(key('stop-player-host'), findsNothing);

    launcher.setStatus('guest-1', DevelopmentPlayerStatus.connected);
    await tester.pumpAndSettle();
    expect(find.text('当前世界内 2 人'), findsOneWidget);
    expect(find.textContaining('正在加入'), findsNothing);
    launcher.setStatus('guest-1', DevelopmentPlayerStatus.disconnected);
    await tester.pumpAndSettle();
    expect(find.text('当前世界内 1 人'), findsOneWidget);
    expect(find.textContaining('已离开'), findsOneWidget);
    expect(key('stop-player-guest-1'), findsOneWidget);
    await tester.tap(key('stop-player-guest-1'));
    await tester.pumpAndSettle();
    expect(launcher.stopped, ['guest-1']);
    expect(find.text('当前世界内 1 人'), findsOneWidget);
    expect(find.textContaining('已离开'), findsOneWidget);
    expect(launcher.running, isTrue);
    expect(key('stop-player-guest-1'), findsNothing);

    launcher.setStatus(
      'guest-1',
      DevelopmentPlayerStatus.failed,
      error: '连接超时，请重试。',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('加入失败'), findsOneWidget);
    expect(find.text('连接超时，请重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'external world players have no fabricated skin or close action',
    (tester) async {
      desktop(tester);
      final launcher = _LanLauncher()
        ..readyHost(true)
        ..addExternal('其他电脑的玩家');
      await panel(tester, launcher);
      expect(key('lan-players'), findsOneWidget);
      await tester.tap(key('lan-players'));
      await tester.pumpAndSettle();
      expect(find.text('当前世界内 2 人'), findsOneWidget);
      final external = key('lan-player-external-player');
      expect(external, findsOneWidget);
      expect(
        find.descendant(of: external, matching: find.text('其他电脑的玩家')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: external, matching: find.textContaining('局域网玩家')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: external, matching: find.textContaining('史蒂夫')),
        findsNothing,
      );
      expect(
        find.descendant(of: external, matching: find.textContaining('艾利克斯')),
        findsNothing,
      );
      expect(
        find.descendant(of: external, matching: find.byType(OreIconButton)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('LAN dialogs and player lists stay with their own tab', (
    tester,
  ) async {
    desktop(tester);
    final launchers = <String, _LanLauncher>{};
    await tester.pumpWidget(
      host(
        DevelopmentEnvironmentPanel(
          storage: FakeStorage(),
          sessionLauncherFactory: (id) async =>
              launchers[id] = _LanLauncher()..readyHost(true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await join(tester, '第一页玩家');
    await tester.tap(key('add-tab'));
    await tester.pumpAndSettle();
    expect(key('lan-players'), findsNothing);
    await join(tester, '第二页玩家', alex: true);
    expect(launchers['default']!.requests.single.name, '第一页玩家');
    expect(launchers.values.last.requests.single.name, '第二页玩家');
    await tester.tap(key('lan-players'));
    await tester.pumpAndSettle();
    expect(find.text('第二页玩家'), findsOneWidget);
    expect(find.text('第一页玩家'), findsNothing);
    await tester.tap(key('stop-player-guest-1'));
    await tester.pumpAndSettle();
    expect(launchers.values.last.stopped, ['guest-1']);
    expect(launchers['default']!.stopped, isEmpty);
    expect(launchers.values.every((launcher) => launcher.running), isTrue);
    await tester.tap(find.widgetWithText(OreButton, '关闭'));
    await tester.pumpAndSettle();
    await tester.tap(key('tab-default'));
    await tester.pumpAndSettle();
    await tester.tap(key('lan-players'));
    await tester.pumpAndSettle();
    expect(find.text('第一页玩家'), findsOneWidget);
    expect(find.text('第二页玩家'), findsNothing);
    expect(key('stop-player-guest-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LAN dialog reserves names while departed windows remain open', (
    tester,
  ) async {
    desktop(tester);
    final launcher = _LanLauncher()..readyHost(true);
    await panel(tester, launcher);
    await join(tester, '测试玩家1');
    launcher.setStatus('guest-1', DevelopmentPlayerStatus.disconnected);
    await tester.pumpAndSettle();
    await tester.tap(key('lan-test'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OreTextField>(key('lan-player-name')).controller!.text,
      '测试玩家2',
    );
    for (final name in ['测试玩家1', '房主玩家']) {
      await tester.enterText(key('lan-player-name'), name);
      await tester.tap(key('start-lan-test'));
      await tester.pumpAndSettle();
      expect(key('lan-launch-dialog'), findsOneWidget);
      expect(find.text('这个玩家名字已经在当前世界使用，请换一个名字。'), findsOneWidget);
      expect(launcher.requests.length, 1);
    }
    await tester.enterText(key('lan-player-name'), '外来玩家');
    launcher.addExternal('外来玩家');
    await tester.pumpAndSettle();
    await tester.tap(key('start-lan-test'));
    await tester.pumpAndSettle();
    expect(key('lan-launch-dialog'), findsOneWidget);
    expect(launcher.requests.length, 1);
    await tester.tap(find.widgetWithText(OreButton, '取消'));
    await tester.pumpAndSettle();

    await launcher.stopLanPlayer('guest-1');
    await tester.pumpAndSettle();
    await tester.tap(key('lan-test'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<OreTextField>(key('lan-player-name')).controller!.text,
      '测试玩家1',
    );
    await tester.tap(key('start-lan-test'));
    await tester.pumpAndSettle();
    expect(launcher.requests.length, 2);
    expect(launcher.requests.last.name, '测试玩家1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('LAN name validation and host readiness prevent invalid launch', (
    tester,
  ) async {
    desktop(tester, size: const Size(520, 760));
    final launcher = _LanLauncher()..readyHost(true);
    await panel(tester, launcher);
    await tester.ensureVisible(key('lan-test'));
    await tester.tap(key('lan-test'));
    await tester.pumpAndSettle();
    for (final name in [
      ' ',
      '12345678901234567',
      '测试艾利克斯',
      '😀😀😀😀a',
      '§aPlayer',
      'bad\u0001name',
    ]) {
      await tester.enterText(key('lan-player-name'), name);
      await tester.tap(key('start-lan-test'));
      await tester.pumpAndSettle();
      expect(key('lan-launch-dialog'), findsOneWidget);
      expect(launcher.requests, isEmpty);
    }
    await tester.enterText(key('lan-player-name'), '允许的名字');
    launcher.readyHost(false);
    await tester.pumpAndSettle();
    expect(tester.widget<OreButton>(key('start-lan-test')).onPressed, isNull);
    expect(find.text(launcher.lanUnavailableReason), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported LAN version shows its specific unavailable reason', (
    tester,
  ) async {
    desktop(tester);
    final launcher = _LanLauncher()
      ..unavailableMessage = '当前游戏版本尚未适配局域网测试，请选择 3.10.0.420447。';
    await panel(tester, launcher);
    expect(tester.widget<OreButton>(key('lan-test')).onPressed, isNull);
    final tooltip = tester.widget<OreTooltip>(
      find.ancestor(of: key('lan-test'), matching: find.byType(OreTooltip)),
    );
    expect(tooltip.message, launcher.unavailableMessage);
    expect(tester.takeException(), isNull);
  });
}
