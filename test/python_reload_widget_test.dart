import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

class ReloadLauncher extends FakeLauncher {
  bool ready = false;
  int requests = 0;
  Completer<void>? pending;
  @override
  bool get pythonReloadAvailable => ready && !pythonReloadBusy;
  @override
  Future<void> reloadPython() async {
    requests++;
    pythonReloadBusy = true;
    notifyListeners();
    await pending?.future;
    pythonReloadBusy = false;
    notifyListeners();
  }

  void makeReady() {
    ready = true;
    running = true;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final path = Platform.environment['MCDEV_RELOAD_FONT'];
    if (path != null) {
      final data = ByteData.sublistView(await File(path).readAsBytes());
      for (final family in [
        'Ahem',
        'Roboto',
        'packages/oreui_flutter/Minecraft Seven v4',
      ]) {
        final loader = FontLoader(family)..addFont(Future.value(data));
        await loader.load();
      }
    }
  });
  for (final dark in [false, true]) {
    for (final width in [480.0, 1280.0]) {
      testWidgets(
        'reload button inside launch area, ${dark ? 'dark' : 'light'} $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final launcher = ReloadLauncher();
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: host(
                DevelopmentEnvironmentPanel(
                  storage: FakeStorage(),
                  launcherFactory: () async => launcher,
                ),
                dark: dark,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byKey(
            const ValueKey('development-python-reload'),
          );
          expect(button, findsOneWidget);
          expect(tester.widget<OreButton>(button).onPressed, isNull);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(find.text('启动游戏'), findsWidgets);
          launcher.makeReady();
          await tester.pumpAndSettle();
          expect(tester.widget<OreButton>(button).onPressed, isNotNull);
          launcher.pending = Completer<void>();
          await tester.tap(button);
          await tester.pump();
          expect(launcher.requests, 1);
          expect(tester.widget<OreButton>(button).onPressed, isNull);
          expect(find.text('正在热重载…'), findsOneWidget);
          launcher.pending!.complete();
          await tester.pumpAndSettle();
          expect(tester.widget<OreButton>(button).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
          if (Platform.environment['MCDEV_RELOAD_SCREENSHOTS'] == '1') {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('build/python-reload-ui').create(recursive: true);
              await File(
                'build/python-reload-ui/${dark ? 'dark' : 'light'}-${width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
