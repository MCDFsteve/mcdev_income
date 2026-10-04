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
      'sort dialog applies list order, cancels edits and fits narrow windows ($dark)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final launcher = FakeLauncher()
          ..packs = [
            for (final name in ['Zulu', 'alpha', 'Bravo'])
              ModPack(
                name: name,
                uuid: name,
                version: const [1, 0, 0],
                type: 'data',
                directory: '/projects/$name',
              ),
          ];
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
        final button = find.byKey(const ValueKey('development-project-sort'));
        expect(tester.widget<OreIconButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('本地项目排序'), findsOneWidget);
        await tester.tap(find.text(ProjectSortOrder.nameAscending.label));
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(launcher.projectSortOrder, ProjectSortOrder.nameAscending);
        expect(
          tester.getTopLeft(find.text('alpha')).dy,
          lessThan(tester.getTopLeft(find.text('Bravo')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Bravo')).dy,
          lessThan(tester.getTopLeft(find.text('Zulu')).dy),
        );
        expect(launcher.tabTitle, '原版测试');

        await tester.tap(button);
        await tester.pumpAndSettle();
        for (final order in ProjectSortOrder.values) {
          expect(
            tester
                .widget<OreCheckboxListTile>(
                  find.byKey(ValueKey('project-sort-${order.name}')),
                )
                .value,
            order == ProjectSortOrder.nameAscending,
          );
        }
        await tester.tap(find.text(ProjectSortOrder.launchedNewest.label));
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(launcher.projectSortOrder, ProjectSortOrder.nameAscending);

        await tester.tap(button);
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('应用').hitTestable(), findsOneWidget);
        await tester.tap(find.text(ProjectSortOrder.nameDescending.label));
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(launcher.projectSortOrder, ProjectSortOrder.nameDescending);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
