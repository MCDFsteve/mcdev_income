import 'dart:io';
import 'game_diagnostics.dart';

/// Presentation is independent of process launch, downloads and the page.
/// A backend may decorate before launch (Wine) or attach afterwards (Win32).
abstract class GameWindowBackend {
  const GameWindowBackend();
  Stream<GameDiagnostic> get diagnostics => const Stream.empty();
  Future<GameWindowLaunch> prepare(GameWindowRequest request);
  Future<void> attach(Process game, GameWindowRequest request);
  Future<bool> requestClose() async => false;
  Future<void> close();
}

class GameWindowRequest {
  const GameWindowRequest({
    required this.executable,
    required this.version,
    required this.displayName,
    required this.renderer,
    required this.fullscreenShortcut,
  });
  final String executable;
  final String version;
  final String displayName;
  final String renderer;
  final bool fullscreenShortcut;
}

class GameWindowLaunch {
  const GameWindowLaunch({this.loader, this.environment = const {}});
  final String? loader;
  final Map<String, String> environment;
}

/// Explicitly injected by process-only tests and headless integrations.
class HeadlessGameWindow extends GameWindowBackend {
  const HeadlessGameWindow();
  @override
  Future<GameWindowLaunch> prepare(GameWindowRequest request) async =>
      const GameWindowLaunch();
  @override
  Future<void> attach(Process game, GameWindowRequest request) async {}
  @override
  Future<void> close() async {}
}
