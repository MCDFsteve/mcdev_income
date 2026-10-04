import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/desktop/window_title_bar.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/platform/development_capabilities.dart';
import 'package:mcdev_income/ui/ore_material.dart';
import 'development_widget_test.dart' show FakeLauncher, FakeStorage, host;

class WindowsLauncher extends FakeLauncher {
  @override
  DevelopmentCapabilities get capabilities => DevelopmentCapabilities.windows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var maximized = false;
  setUp(() {
    calls.clear();
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'maximize') maximized = true;
          if (call.method == 'unmaximize') maximized = false;
          if (call.method.startsWith('is')) return false;
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    test('$platform initializes and operates through window_manager', () async {
      debugDefaultTargetPlatformOverride = platform;
      await initializeDesktopWindow();
      expect(
        calls.any(
          (call) =>
              call.method == 'setTitleBarStyle' &&
              (call.arguments as Map)['titleBarStyle'] == 'hidden',
        ),
        isTrue,
      );
      const controller = ManagedWindowController();
      await controller.invoke('drag');
      await controller.invoke('zoom');
      await controller.invoke('zoom');
      await controller.invoke('minimize');
      await controller.invoke('close');
      expect(
        calls.map((call) => call.method),
        containsAllInOrder([
          'startDragging',
          'isMaximized',
          'maximize',
          'isMaximized',
          'unmaximize',
          'minimize',
          'close',
        ]),
      );
    });
  }
  test('Android initializes without invoking desktop plugins', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await initializeDesktopWindow();
    expect(calls, isEmpty);
    expect(hasDesktopWindow, isFalse);
  });

  testWidgets('Windows caption buttons operate the shared window controller', (
    tester,
  ) async {
    await tester.pumpWidget(host(const OreWindowTitleBar(title: '开发')));
    await tester.pump();
    String? zoomTooltip() => tester
        .widget<OreIconButton>(find.byKey(const ValueKey('window-zoom')))
        .tooltip;
    expect(zoomTooltip(), '最大化');

    // Native maximize/restore (double-click, drag, OS shortcuts) must update
    // the caption even when no Flutter caption button was pressed.
    for (final state in [true, false]) {
      maximized = state;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onEvent', {
            'eventName': state ? 'maximize' : 'unmaximize',
          }),
        ),
        (_) {},
      );
      await tester.pump();
      expect(zoomTooltip(), state ? '还原' : '最大化');
    }
    for (final action in ['minimize', 'zoom', 'close']) {
      await tester.tap(find.byKey(ValueKey('window-$action')));
      await tester.pump();
    }
    expect(
      calls.map((call) => call.method),
      containsAllInOrder(['minimize', 'maximize', 'close']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows development hides Wine and macOS-only settings', (
    tester,
  ) async {
    final launcher = WindowsLauncher();
    await tester.pumpWidget(
      host(
        DevelopmentEnvironmentPanel(
          storage: FakeStorage(),
          launcherFactory: () async => launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wine 运行环境'), findsNothing);
    expect(find.text('Shift + Command 切换全屏'), findsNothing);
    expect(find.text('图形性能优化'), findsNothing);
    expect(find.text('启动测试'), findsOneWidget);
  });
}
