import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'console and skin can be changed and survive reopening a short desktop dialog',
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
      await tester.tap(find.text('测试设置'));
      await tester.pumpAndSettle();

      final skin = find.widgetWithText(OreChoiceButtons, '史蒂夫（粗手臂）');
      expect(tester.widget<OreChoiceButtons>(skin).selectedIndex, 0);
      await tester.ensureVisible(find.text('艾利克斯（细手臂）'));
      await tester.tap(find.text('艾利克斯（细手臂）'));
      await tester.pumpAndSettle();
      expect(launcher.playerSkin, TestPlayerSkin.alex);

      final console = find.widgetWithText(OreCheckboxListTile, '显示开发控制台');
      expect(tester.widget<OreCheckboxListTile>(console).value, isFalse);
      await tester.ensureVisible(console);
      await tester.tap(find.text('显示开发控制台'));
      await tester.pumpAndSettle();
      expect(launcher.showDeveloperConsole, isTrue);
      final shortcut = find.widgetWithText(
        OreCheckboxListTile,
        'Shift + Command 切换全屏',
      );
      expect(tester.widget<OreCheckboxListTile>(shortcut).value, isFalse);
      await tester.ensureVisible(shortcut);
      await tester.tap(find.text('Shift + Command 切换全屏'));
      await tester.pumpAndSettle();
      expect(launcher.fullscreenShortcut, isTrue);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试设置'));
      await tester.pumpAndSettle();
      expect(tester.widget<OreChoiceButtons>(skin).selectedIndex, 1);
      expect(tester.widget<OreCheckboxListTile>(console).value, isTrue);
      expect(tester.widget<OreCheckboxListTile>(shortcut).value, isTrue);

      await tester.ensureVisible(find.text('仅打开游戏主菜单'));
      await tester.tap(find.text('仅打开游戏主菜单'));
      await tester.pumpAndSettle();
      expect(tester.widget<OreChoiceButtons>(skin).onChanged, isNull);
      expect(launcher.playerSkin, TestPlayerSkin.alex);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.ensureVisible(skin);
      expect(skin.hitTestable(), findsOneWidget);
      await tester.ensureVisible(shortcut);
      expect(shortcut.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('running games disable the test settings entry', (tester) async {
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
    expect(
      tester
          .widget<OreButton>(find.widgetWithText(OreButton, '测试设置'))
          .onPressed,
      isNull,
    );
    expect(find.text('玩家皮肤'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
