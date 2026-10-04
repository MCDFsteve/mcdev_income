import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:mcdev_income/development/project_icon.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:path/path.dart' as p;

import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;
import 'image_crop_test.dart' show samplePng;

Future<ModProject> pairedProject(Directory root, {bool corrupt = false}) async {
  final bytes = await samplePng();
  final packs = <ModPack>[];
  for (final type in ['resources', 'data']) {
    final directory = await Directory(p.join(root.path, type)).create();
    await File(
      p.join(directory.path, 'pack_icon.png'),
    ).writeAsBytes(corrupt && type == 'data' ? [1, 2, 3] : bytes);
    packs.add(
      ModPack(
        name: type == 'data' ? 'Icon project' : 'Project textures',
        uuid: type,
        version: const [1, 0, 0],
        type: type,
        directory: directory.path,
        projectRoot: root.path,
      ),
    );
  }
  return groupModProjects(packs).single;
}

Future<void> waitForIcon(
  WidgetTester tester,
  Finder icon, {
  bool fallback = false,
}) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (fallback) {
      if (find
          .descendant(of: icon, matching: find.byIcon(Icons.extension))
          .evaluate()
          .isNotEmpty) {
        return;
      }
    } else {
      final images = tester.widgetList<RawImage>(
        find.descendant(of: icon, matching: find.byType(RawImage)),
      );
      if (images.any((image) => image.image != null)) return;
    }
  }
  fail('Project icon did not finish loading');
}

String displayedIconPath(WidgetTester tester, Finder icon) {
  final image = tester.widget<Image>(
    find.descendant(of: icon, matching: find.byType(Image)).last,
  );
  final provider = (image.image as ResizeImage).imageProvider as FileImage;
  return provider.file.path;
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'pack icon sits between checkbox and title and toggles the whole project ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('mcdev-project-icon-'),
        ))!;
        addTearDown(() => root.delete(recursive: true));
        final project = (await tester.runAsync(() => pairedProject(root)))!;
        final launcher = FakeLauncher()..packs = project.packs;
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
        final tile = find.byWidgetPredicate(
          (widget) =>
              widget is OreListTile &&
              widget.title is Text &&
              (widget.title as Text).data == project.name,
        );
        final icon = find.descendant(
          of: tile,
          matching: find.byType(ModProjectIcon),
        );
        await waitForIcon(tester, icon);
        expect(
          displayedIconPath(tester, icon),
          p.join(root.path, 'data', 'pack_icon.png'),
        );
        for (final size in [const Size(1280, 800), const Size(390, 844)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          if (size.width < 600) {
            await tester.scrollUntilVisible(
              tile,
              200,
              scrollable: find
                  .descendant(
                    of: find.byKey(const ValueKey('development-single-column')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
          } else {
            await tester.ensureVisible(tile);
          }
          await tester.pumpAndSettle();
          final checkbox = find.descendant(
            of: tile,
            matching: find.byType(OreCheckbox),
          );
          final title = find.descendant(
            of: tile,
            matching: find.text(project.name),
          );
          expect(
            tester.getRect(checkbox).right,
            lessThan(tester.getRect(icon).left),
          );
          expect(
            tester.getRect(icon).right,
            lessThan(tester.getRect(title).left),
          );
          expect(tester.getSize(icon), const Size(40, 40));
          await tester.tapAt(tester.getCenter(icon));
          await tester.pumpAndSettle();
          expect(
            launcher.selectedPacks,
            size.width > 1000 ? {'data', 'resources'} : isEmpty,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('corrupt behavior icon falls back to the resource pack', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('mcdev-project-icon-'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    final project = (await tester.runAsync(
      () => pairedProject(root, corrupt: true),
    ))!;
    await tester.pumpWidget(
      host(Center(child: ModProjectIcon(project: project))),
    );
    final icon = find.byType(ModProjectIcon);
    await waitForIcon(tester, icon);
    expect(
      displayedIconPath(tester, icon),
      p.join(root.path, 'resources', 'pack_icon.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing icons keep a same-size placeholder', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('mcdev-project-icon-'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    final project = ModProject(
      id: root.path,
      name: 'No icon',
      packs: [
        ModPack(
          name: 'No icon',
          uuid: 'id',
          version: const [1, 0, 0],
          type: 'data',
          directory: root.path,
        ),
      ],
    );
    await tester.pumpWidget(
      host(Center(child: ModProjectIcon(project: project))),
    );
    final icon = find.byType(ModProjectIcon);
    await waitForIcon(tester, icon, fallback: true);
    expect(tester.getSize(icon), const Size(40, 40));
    expect(tester.takeException(), isNull);
  });
}
