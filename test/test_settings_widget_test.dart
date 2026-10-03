import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    testWidgets(
      'new world and seed are first-level controls, responsive and disabled while running ($dark)',
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
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('development-new-world'));
        final seed = find.byKey(const ValueKey('development-world-seed'));
        expect(tester.widget<OreCheckboxListTile>(toggle).value, isFalse);
        expect(seed, findsNothing);
        await tester.tap(find.text('使用新存档'));
        await tester.pumpAndSettle();
        expect(find.byType(OreAlertDialog), findsNothing);
        expect(seed.hitTestable(), findsOneWidget);
        await tester.enterText(seed, '-12345');
        await tester.tap(find.text('使用新存档'));
        await tester.pumpAndSettle();
        expect(seed, findsNothing);
        await tester.tap(find.text('使用新存档'));
        await tester.pumpAndSettle();
        expect(tester.widget<OreTextField>(seed).controller!.text, '-12345');
        for (final size in [
          const Size(720, 400),
          const Size(390, 844),
          const Size(1280, 800),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          await tester.ensureVisible(seed);
          await tester.pumpAndSettle();
          expect(seed.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byKey(const ValueKey('development-launch')));
        await tester.pumpAndSettle();
        expect(launcher.lastNewWorld, isTrue);
        expect(launcher.lastSeed, '-12345');
        expect(tester.widget<OreCheckboxListTile>(toggle).onChanged, isNull);
        expect(tester.widget<OreTextField>(seed).enabled, isFalse);
        await launcher.stopGame();
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        await tester.tap(find.text('仅打开游戏主菜单'));
        await tester.pumpAndSettle();
        expect(tester.widget<OreCheckboxListTile>(toggle).onChanged, isNull);
        expect(tester.widget<OreTextField>(seed).enabled, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'inline console and skin settings survive resizing a short desktop window',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 600);
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
      await tester.pumpAndSettle();

      final skin = find.widgetWithText(OreChoiceButtons, '史蒂夫（粗手臂）');
      expect(tester.widget<OreChoiceButtons>(skin).selectedIndex, 0);
      await tester.ensureVisible(find.text('艾利克斯（细手臂）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('艾利克斯（细手臂）'));
      await tester.pumpAndSettle();
      expect(launcher.playerSkin, TestPlayerSkin.alex);

      final console = find.widgetWithText(OreCheckboxListTile, '显示开发控制台');
      expect(tester.widget<OreCheckboxListTile>(console).value, isFalse);
      await tester.ensureVisible(console);
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示开发控制台'));
      await tester.pumpAndSettle();
      expect(launcher.showDeveloperConsole, isTrue);
      final shortcut = find.widgetWithText(
        OreCheckboxListTile,
        'Shift + Command 切换全屏',
      );
      expect(tester.widget<OreCheckboxListTile>(shortcut).value, isFalse);
      await tester.ensureVisible(shortcut);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shift + Command 切换全屏'));
      await tester.pumpAndSettle();
      expect(launcher.fullscreenShortcut, isTrue);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(tester.widget<OreChoiceButtons>(skin).selectedIndex, 1);
      expect(tester.widget<OreCheckboxListTile>(console).value, isTrue);
      expect(tester.widget<OreCheckboxListTile>(shortcut).value, isTrue);

      await tester.ensureVisible(find.text('仅打开游戏主菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅打开游戏主菜单'));
      await tester.pumpAndSettle();
      expect(tester.widget<OreChoiceButtons>(skin).onChanged, isNull);
      expect(launcher.playerSkin, TestPlayerSkin.alex);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.ensureVisible(skin);
      await tester.pumpAndSettle();
      expect(skin.hitTestable(), findsOneWidget);
      await tester.ensureVisible(shortcut);
      await tester.pumpAndSettle();
      expect(shortcut.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('running games disable the inline test settings', (tester) async {
    final launcher = FakeLauncher()..running = true;
    await tester.pumpWidget(
      host(
        DevelopmentEnvironmentPanel(
          storage: FakeStorage(),
          launcherFactory: () async => launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试设置'), findsNothing);
    expect(find.text('管理版本'), findsNothing);
    expect(find.text('玩家皮肤'), findsOneWidget);
    final settings = find.byKey(const ValueKey('development-test-options'));
    for (final choice in tester.widgetList<OreChoiceButtons>(
      find.descendant(of: settings, matching: find.byType(OreChoiceButtons)),
    )) {
      expect(choice.onChanged, isNull);
    }
    for (final checkbox in tester.widgetList<OreCheckboxListTile>(
      find.descendant(of: settings, matching: find.byType(OreCheckboxListTile)),
    )) {
      expect(checkbox.onChanged, isNull);
    }
    expect(
      tester
          .widget<OreTextField>(
            find.byKey(const ValueKey('development-world-name')),
          )
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
