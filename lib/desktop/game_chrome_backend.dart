import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'game_window_controller.dart';
import 'window_controller.dart';

abstract class GameChromeBackend {
  const GameChromeBackend();
  WindowController get window;
  bool get nativeMenus;
  bool get trafficLights;
  Future<void> initialize(String title);
}

class MacGameChromeBackend extends GameChromeBackend {
  const MacGameChromeBackend();
  @override
  WindowController get window => const DesktopWindowBridge();
  @override
  bool get nativeMenus => true;
  @override
  bool get trafficLights => true;
  @override
  Future<void> initialize(String title) async {}
}

class WindowsGameChromeBackend extends GameChromeBackend {
  const WindowsGameChromeBackend();
  @override
  WindowController get window => const WindowsGameWindowController();
  @override
  bool get nativeMenus => false;
  @override
  bool get trafficLights => false;
  @override
  Future<void> initialize(String title) async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: title,
        minimumSize: const Size(640, 408),
        titleBarStyle: TitleBarStyle.hidden,
      ),
    );
    await windowManager.show();
    await windowManager.focus();
  }
}

class WindowsGameWindowController extends ManagedWindowController {
  const WindowsGameWindowController();
  static const channel = MethodChannel('mcdev_income/game_host');
  @override
  Future<void> invoke(String action, [Object? arguments]) async {
    if (const {'close', 'sendKey', 'focus'}.contains(action)) {
      await channel.invokeMethod<void>(action, arguments);
    } else {
      await super.invoke(action, arguments);
    }
  }
}

GameChromeBackend createGameChromeBackend() => switch (defaultTargetPlatform) {
  TargetPlatform.windows => const WindowsGameChromeBackend(),
  TargetPlatform.macOS => const MacGameChromeBackend(),
  _ => throw UnsupportedError('当前平台尚未实现游戏窗口宿主'),
};
