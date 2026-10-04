import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/desktop/game_chrome.dart';
import 'package:mcdev_income/desktop/game_chrome_backend.dart';
import 'package:mcdev_income/desktop/window_title_bar.dart';
import 'package:mcdev_income/ui/ore_material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows chrome uses shared controls and routes game actions to its host',
    (tester) async {
      final managed = <MethodCall>[];
      final game = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          managed.add(call);
          if (call.method.startsWith('is')) return false;
          return null;
        },
      );
      messenger.setMockMethodCallHandler(WindowsGameWindowController.channel, (
        call,
      ) async {
        game.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
        messenger.setMockMethodCallHandler(
          WindowsGameWindowController.channel,
          null,
        );
      });
      await tester.pumpWidget(
        const GameChromeApp(
          backend: WindowsGameChromeBackend(),
          displayName: '我的世界测试 · A',
        ),
      );
      expect(find.byType(PlatformMenuBar), findsNothing);
      expect(
        tester
            .widget<OreWindowTitleBar>(find.byType(OreWindowTitleBar))
            .trafficLights,
        isFalse,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is OreIconButton && widget.tooltip == '暂停 / 返回',
        ),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is OreIconButton && widget.tooltip == '切换全屏',
        ),
      );
      await tester.pump();
      expect(game.single.method, 'sendKey');
      expect(game.single.arguments, 'escape');
      expect(managed.last.method, 'setFullScreen');
      await const WindowsGameWindowController().invoke('close');
      expect(game.last.method, 'close');
      expect(managed.any((call) => call.method == 'close'), isFalse);
    },
  );
}
