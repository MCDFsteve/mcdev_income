import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/launcher_service.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

class ProjectPicker extends FilePicker {
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => '/duplicate-addon';
}

class ManifestActionLauncher extends FakeLauncher {
  bool? importRefreshed;
  int randomizations = 0;
  int upgrades = 0;

  @override
  Future<void> importMods(
    String path, {
    Future<bool> Function()? confirmUuidRefresh,
  }) async {
    busy = true;
    notifyListeners();
    importRefreshed = await confirmUuidRefresh!();
    busy = false;
    notifyListeners();
  }

  @override
  Future<void> randomizeProjectUuids(String projectId) async {
    randomizations++;
    _update(uuid: 'new-uuid-$randomizations');
  }

  @override
  Future<void> upgradeProjectVersion(String projectId) async {
    upgrades++;
    final version = [...packs.single.version];
    version[2]++;
    _update(version: version);
  }

  void _update({String? uuid, List<int>? version}) {
    final pack = packs.single;
    packs = [
      ModPack(
        name: pack.name,
        uuid: uuid ?? pack.uuid,
        version: version ?? pack.version,
        type: pack.type,
        directory: pack.directory,
      ),
    ];
    notifyListeners();
  }

  void setBlocked({bool isBusy = false, bool isRunning = false}) {
    busy = isBusy;
    running = isRunning;
    notifyListeners();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final accepted in [false, true]) {
    testWidgets('duplicate import dialog forwards choice ($accepted)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = FilePicker.platform;
      FilePicker.platform = ProjectPicker();
      addTearDown(() => FilePicker.platform = previous);
      final launcher = ManifestActionLauncher();
      await tester.pumpWidget(
        host(
          DevelopmentEnvironmentPanel(
            storage: FakeStorage(),
            launcherFactory: () async => launcher,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入项目文件夹'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('项目 UUID 重复'), findsOneWidget);
      expect(find.textContaining('会修改源 manifest.json'), findsOneWidget);
      await tester.tap(find.text(accepted ? '刷新 UUID 并导入' : '取消导入'));
      await tester.pumpAndSettle();
      expect(launcher.importRefreshed, accepted);
      expect(find.byType(OreAlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    for (final width in [420.0, 1280.0]) {
      testWidgets(
        'detail actions refresh values and respect busy state ($dark, $width)',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final launcher = ManifestActionLauncher();
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
          final details = find.byWidgetPredicate(
            (widget) => widget is OreIconButton && widget.tooltip == '查看项目包详情',
          );
          await tester.ensureVisible(details);
          await tester.pumpAndSettle();
          await tester.tap(details);
          await tester.pumpAndSettle();
          expect(find.text('UUID：id'), findsOneWidget);
          await tester.tap(find.text('随机 UUID'));
          await tester.pumpAndSettle();
          expect(launcher.randomizations, 1);
          expect(find.text('UUID：new-uuid-1'), findsOneWidget);
          expect(find.text('UUID：id'), findsNothing);
          await tester.tap(find.text('升级版本号'));
          await tester.pumpAndSettle();
          expect(launcher.upgrades, 1);
          expect(find.text('Test pack · 1.0.1'), findsOneWidget);
          for (final running in [false, true]) {
            launcher.setBlocked(isBusy: !running, isRunning: running);
            await tester.pump(const Duration(milliseconds: 300));
            for (final action in ['随机 UUID', '升级版本号']) {
              expect(
                tester
                    .widget<OreButton>(find.widgetWithText(OreButton, action))
                    .onPressed,
                isNull,
              );
            }
          }
          launcher.setBlocked();
          await tester.pumpAndSettle();
          await tester.tap(find.text('关闭'));
          await tester.pumpAndSettle();
          expect(find.textContaining('1.0.1'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
