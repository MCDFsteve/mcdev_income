import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final supported in [true, false]) {
    testWidgets(
      'performance setting is ${supported ? 'available' : 'disabled'} and fits the desktop dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final launcher = FakeLauncher();
        if (!supported) {
          launcher.performanceOptimization = true;
          launcher.games = [const LocalGame('3.10.0.420447', '/game')];
          launcher.selectedVersion = '3.10.0.420447';
        }
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
        final setting = find.widgetWithText(OreCheckboxListTile, '图形性能优化');
        expect(tester.widget<OreCheckboxListTile>(setting).value, isFalse);
        if (supported) {
          await tester.ensureVisible(setting);
          await tester.tap(find.text('图形性能优化'));
          await tester.pumpAndSettle();
          expect(launcher.performanceOptimization, isTrue);
          expect(tester.widget<OreCheckboxListTile>(setting).value, isTrue);
        } else {
          expect(tester.widget<OreCheckboxListTile>(setting).onChanged, isNull);
        }
        final limit = find.widgetWithText(OreCheckboxListTile, '限制 60 帧');
        expect(tester.widget<OreCheckboxListTile>(limit).value, isTrue);
        await tester.ensureVisible(limit);
        await tester.tap(find.text('限制 60 帧'));
        await tester.pumpAndSettle();
        expect(launcher.limit60Fps, isFalse);
        expect(launcher.performanceOptimization, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'renderer changes on a supported version without changing frame or optimization preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final launcher = FakeLauncher()
        ..selectedVersion = '3.10.0.420447'
        ..performanceOptimization = true;
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
      await tester.ensureVisible(find.text('渲染龙'));
      await tester.tap(find.text('渲染龙'));
      await tester.pumpAndSettle();
      expect(launcher.renderer, GameRenderer.renderDragon);
      expect(launcher.performanceOptimization, isTrue);
      expect(launcher.limit60Fps, isTrue);
      final limit = find.widgetWithText(OreCheckboxListTile, '限制 60 帧');
      await tester.ensureVisible(limit);
      await tester.tap(find.text('限制 60 帧'));
      await tester.pumpAndSettle();
      expect(launcher.limit60Fps, isFalse);
      expect(launcher.renderer, GameRenderer.renderDragon);
      expect(tester.takeException(), isNull);
    },
  );
}
