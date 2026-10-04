import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launch_tabs.dart';

import 'development_test.dart' show MemoryPreferences;
import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

void main() {
  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'running tabs do not freeze another session and stopping one leaves the other running',
    (tester) async {
      desktop(tester);
      final launchers = <String, FakeLauncher>{};
      final activity = <bool>[];
      await tester.pumpWidget(
        host(
          DevelopmentEnvironmentPanel(
            storage: FakeStorage(),
            onActivity: activity.add,
            sessionLauncherFactory: (id) async =>
                launchers[id] = FakeLauncher(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = launchers['default']!;
      first.selectedPacks.add('id');
      first.notifyListeners();
      await tester.pumpAndSettle();
      final launchRect = tester.getRect(
        find.byKey(const ValueKey('development-launch')),
      );
      final versionRect = tester.getRect(
        find.byKey(const ValueKey('active-game-version')),
      );
      expect(launchRect.right, lessThan(versionRect.left));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('development-test-tabs')),
          matching: find.text('Test pack'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('development-launch')));
      await tester.pumpAndSettle();
      expect(first.running, isTrue);
      await tester.tap(find.byKey(const ValueKey('development-add-tab')));
      await tester.pumpAndSettle();
      expect(launchers.length, 2);
      final secondId = launchers.keys.last;
      final second = launchers[secondId]!;
      expect(
        tester
            .widget<OreButton>(find.byKey(const ValueKey('development-launch')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('development-launch')));
      await tester.pumpAndSettle();
      expect(first.running && second.running, isTrue);
      expect(activity, [true]);

      await tester.tap(find.widgetWithText(OreButton, '退出测试'));
      await tester.pumpAndSettle();
      expect(second.running, isFalse);
      expect(first.running, isTrue);
      expect(activity, [true]);
      await tester.tap(find.byKey(const ValueKey('development-tab-default')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OreButton, '退出测试'));
      await tester.pumpAndSettle();
      expect(activity, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing a running tab asks before stopping and the final tab cannot be closed',
    (tester) async {
      desktop(tester);
      final launchers = <String, FakeLauncher>{};
      await tester.pumpWidget(
        host(
          DevelopmentEnvironmentPanel(
            storage: FakeStorage(),
            sessionLauncherFactory: (id) async =>
                launchers[id] = FakeLauncher(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OreButton>(
              find.byKey(const ValueKey('development-close-tab-default')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('development-add-tab')));
      await tester.pumpAndSettle();
      final id = launchers.keys.last;
      final second = launchers[id]!;
      await tester.tap(find.byKey(const ValueKey('development-launch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('development-close-tab-$id')));
      await tester.pumpAndSettle();
      expect(second.running, isTrue);
      await tester.tap(find.widgetWithText(OreButton, '保留标签'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('development-tab-$id')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('development-close-tab-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OreButton, '退出并关闭标签'));
      await tester.pumpAndSettle();
      expect(second.running, isFalse);
      expect(find.byKey(ValueKey('development-tab-$id')), findsNothing);
      expect(
        tester
            .widget<OreButton>(
              find.byKey(const ValueKey('development-close-tab-default')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'each tab preserves seed and test world settings across switching and reopen',
    (tester) async {
      desktop(tester);
      final preferences = MemoryPreferences();
      final launchers = <String, FakeLauncher>{};
      Widget panel() => host(
        DevelopmentEnvironmentPanel(
          key: UniqueKey(),
          storage: FakeStorage(),
          preferences: preferences,
          sessionLauncherFactory: (id) async =>
              launchers[id] = FakeLauncher()..useNewWorld = true,
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('development-world-seed')),
        '101',
      );
      await tester.enterText(
        find.byKey(const ValueKey('development-world-name')),
        'First world',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('生存'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OreCheckboxListTile, '仅打开游戏主菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('development-add-tab')));
      await tester.pumpAndSettle();
      final secondId = launchers.keys.last;
      await tester.enterText(
        find.byKey(const ValueKey('development-world-seed')),
        '202',
      );
      await tester.tap(find.byKey(const ValueKey('development-tab-default')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OreTextField>(
              find.byKey(const ValueKey('development-world-name')),
            )
            .controller!
            .text,
        'First world',
      );
      expect(
        tester
            .widget<OreTextField>(
              find.byKey(const ValueKey('development-world-seed')),
            )
            .controller!
            .text,
        '101',
      );
      await tester.tap(find.byKey(ValueKey('development-tab-$secondId')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OreTextField>(
              find.byKey(const ValueKey('development-world-seed')),
            )
            .controller!
            .text,
        '202',
      );
      expect(launchers[secondId]!.refreshes, 1);
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OreTextField>(
              find.byKey(const ValueKey('development-world-seed')),
            )
            .controller!
            .text,
        '202',
      );
      final store = DevelopmentTabsStore(preferences, '/test/development')
        ..load();
      expect(store.activeId, secondId);
      expect(store.tabs.first.worldName, 'First world');
      expect(store.tabs.first.creative, isFalse);
      expect(store.tabs.first.menuOnly, isTrue);
      expect(store.tabs.last.creative, isTrue);
      expect(store.tabs.last.menuOnly, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
