import 'dart:io';
import '../wine_game_app_io.dart';
import '../input_guard_io.dart';
import '../wine_network_io.dart';
import '../game_window_chrome_io.dart';
import 'game_window_backend.dart';

class MacGameWindow extends GameWindowBackend {
  const MacGameWindow({
    required this.runtime,
    required this.runtimes,
    required this.metal,
    required this.sessionId,
  });
  final String runtime;
  final String runtimes;
  final bool metal;
  final String sessionId;
  @override
  Future<GameWindowLaunch> prepare(GameWindowRequest request) async {
    final app = await prepareWineGameApplication(
      runtime,
      metal: metal,
      sessionId: sessionId,
      displayName: request.displayName,
    );
    final network = await prepareWineNetworkLibrary(runtimes);
    final nativeEnvironment = wineNetworkEnvironment(network.path);
    final guard = !request.fullscreenShortcut
        ? await prepareFullscreenShortcutGuard(runtimes)
        : null;
    if (guard != null) {
      nativeEnvironment.addAll(
        fullscreenShortcutEnvironment(
          guard.path,
          inherited: {...Platform.environment, ...nativeEnvironment},
        ),
      );
    }
    final chrome = await prepareGameWindowChrome(runtimes);
    return GameWindowLaunch(
      loader: app.loader,
      environment: {
        ...app.environment,
        ...nativeEnvironment,
        ...chrome.environment(
          loader: app.loader,
          version: request.version,
          displayName: request.displayName,
          renderer: request.renderer,
          inherited: {...Platform.environment, ...nativeEnvironment},
        ),
      },
    );
  }

  @override
  Future<void> attach(Process game, GameWindowRequest request) async {}
  @override
  Future<void> close() async {}
}
