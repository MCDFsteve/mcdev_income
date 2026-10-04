import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

class PendingProjectPicker extends FilePicker {
  final result = Completer<String?>();
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) => result.future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    testWidgets(
      'expanded projects share actions and fit narrow windows ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final launcher = FakeLauncher()
          ..projectSortOrder = ProjectSortOrder.nameAscending
          ..packs = [
            for (var i = 0; i < 40; i++)
              ModPack(
                name: 'Project ${i.toString().padLeft(2, '0')}',
                uuid: 'id-$i',
                version: const [1, 0, 0],
                type: 'data',
                directory: '/projects/$i',
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
        final original = find.byKey(
          const PageStorageKey('development-projects'),
        );
        final originalHeight = tester.getSize(original).height;
        final originalController = tester
            .widget<ListView>(original)
            .controller!;
        await tester.tap(find.text('展开查看'));
        await tester.pumpAndSettle();
        final dialog = find.byKey(
          const ValueKey('development-projects-dialog'),
        );
        final list = find.byKey(
          const PageStorageKey('development-projects-expanded'),
        );
        Finder inside(Finder finder) =>
            find.descendant(of: dialog, matching: finder);
        expect(tester.getSize(list).height, greaterThan(originalHeight * 1.5));
        final scrollable = find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          inside(find.text('Project 39')),
          300,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(originalController.offset, 0);
        await tester.tap(inside(find.text('Project 39')));
        await tester.pumpAndSettle();
        expect(launcher.selectedPacks, {'id-39'});
        expect(inside(find.text('1 / 40 已选')), findsOneWidget);
        final project = launcher.projects.singleWhere(
          (p) => p.name == 'Project 39',
        );
        await tester.tap(
          inside(find.byKey(ValueKey('project-details-${project.id}'))),
        );
        await tester.pumpAndSettle();
        expect(find.text('/projects/39'), findsOneWidget);
        await tester.tap(find.widgetWithText(OreButton, '移除项目'));
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
        expect(launcher.projects, hasLength(39));
        expect(launcher.selectedPacks, isEmpty);
        expect(inside(find.text('0 / 39 已选')), findsOneWidget);
        await tester.tap(
          inside(find.byKey(const ValueKey('development-project-sort'))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(ProjectSortOrder.nameDescending.label));
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(launcher.projectSortOrder, ProjectSortOrder.nameDescending);
        tester.widget<ListView>(list).controller!.jumpTo(0);
        await tester.pumpAndSettle();
        expect(inside(find.text('Project 38')).hitTestable(), findsOneWidget);
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(inside(find.text('关闭')).hitTestable(), findsOneWidget);
        expect(tester.getSize(list).height, greaterThan(400));
        await tester.tap(inside(find.text('Project 38')));
        await tester.pumpAndSettle();
        expect(launcher.selectedPacks, {'id-38'});
        await tester.tap(inside(find.text('关闭')));
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        await tester.scrollUntilVisible(
          find.text('本地项目'),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('development-single-column')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('1 / 39 已选'), findsOneWidget);
        expect(launcher.projectSortOrder, ProjectSortOrder.nameDescending);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'expanded import disables duplicate picking and keeps empty state visible',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousPicker = FilePicker.platform;
      final picker = PendingProjectPicker();
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = previousPicker);
      final launcher = FakeLauncher()..packs = [];
      await tester.pumpWidget(
        host(
          DevelopmentEnvironmentPanel(
            storage: FakeStorage(),
            launcherFactory: () async => launcher,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开查看'));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const ValueKey('development-projects-dialog'));
      Finder inside(Finder finder) =>
          find.descendant(of: dialog, matching: finder);
      expect(inside(find.text('尚未导入项目。')), findsOneWidget);
      await tester.tap(inside(find.text('导入项目文件夹')));
      await tester.pumpAndSettle();
      for (final label in ['导入项目文件夹', '导入模组归档']) {
        expect(
          tester
              .widget<OreButton>(inside(find.widgetWithText(OreButton, label)))
              .onPressed,
          isNull,
        );
      }
      picker.result.complete(null);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OreButton>(
              inside(find.widgetWithText(OreButton, '导入项目文件夹')),
            )
            .onPressed,
        isNotNull,
      );
      launcher.running = true;
      launcher.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OreButton>(
              inside(find.widgetWithText(OreButton, '导入项目文件夹')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(inside(find.text('关闭')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
