import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// The app owns one desktop window implementation across Windows/macOS/Linux.
/// Embedded game windows can implement the same contract for their own process.
abstract class WindowController {
  const WindowController();

  /// Caption state comes from the owning window, including native gestures.
  Stream<bool> watchMaximized() => const Stream<bool>.empty();
  Widget dragRegion(Widget child) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onPanStart: (_) => invoke('drag'),
    onDoubleTap: () => invoke('zoom'),
    child: child,
  );
  Future<void> invoke(String action, [Object? arguments]);
}

bool get hasDesktopWindow =>
    !kIsWeb &&
    const {
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

Future<void> initializeDesktopWindow() async {
  if (!hasDesktopWindow) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: '我的世界开发者管理',
      minimumSize: Size(640, 480),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    ),
  );
  await windowManager.show();
}

class ManagedWindowController extends WindowController {
  const ManagedWindowController();
  @override
  Stream<bool> watchMaximized() {
    late final StreamController<bool> states;
    var active = true;
    var revision = 0;
    final listener = _MaximizedWindowListener((maximized) {
      revision++;
      states.add(maximized);
    });
    states = StreamController<bool>(
      onListen: () {
        windowManager.addListener(listener);
        final initialRevision = revision;
        windowManager.isMaximized().then(
          (maximized) {
            // A native event can arrive before the initial query returns.
            if (active && revision == initialRevision) states.add(maximized);
          },
          onError: (Object error, StackTrace stack) {
            if (active) states.addError(error, stack);
          },
        );
      },
      onCancel: () {
        active = false;
        windowManager.removeListener(listener);
      },
    );
    return states.stream.distinct();
  }

  @override
  Future<void> invoke(String action, [Object? arguments]) async {
    switch (action) {
      case 'drag':
        await windowManager.startDragging();
      case 'minimize':
        await windowManager.minimize();
      case 'zoom':
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      case 'fullscreen':
        await windowManager.setFullScreen(!await windowManager.isFullScreen());
      case 'close':
        await windowManager.close();
      default:
        throw UnsupportedError('Unknown window action: $action');
    }
  }
}

class _MaximizedWindowListener extends WindowListener {
  _MaximizedWindowListener(this.onChanged);
  final ValueChanged<bool> onChanged;
  @override
  void onWindowMaximize() => onChanged(true);
  @override
  void onWindowUnmaximize() => onChanged(false);
}
