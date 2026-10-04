import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'window_controller.dart';

/// Window operations stay local to the process owning this Flutter view.
class DesktopWindowBridge extends WindowController {
  const DesktopWindowBridge();
  @override
  Widget dragRegion(Widget child) =>
      _GameWindowDragRegion(bridge: this, child: child);
  static const channel = MethodChannel('mcdev_income/window_chrome');

  @override
  Future<void> invoke(String action, [Object? arguments]) async {
    await channel.invokeMethod<void>(action, arguments);
  }
}

/// Register geometry ahead of the gesture so AppKit can start dragging on the
/// original mouse-down, without a round trip through an asynchronous channel.
class _GameWindowDragRegion extends StatefulWidget {
  const _GameWindowDragRegion({required this.bridge, required this.child});
  final WindowController bridge;
  final Widget child;

  @override
  State<_GameWindowDragRegion> createState() => _GameWindowDragRegionState();
}

class _GameWindowDragRegionState extends State<_GameWindowDragRegion> {
  Rect? _lastRect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastRect = null;
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || (route != null && !route.isCurrent)) return;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          if (rect == _lastRect) return;
          _lastRect = rect;
          widget.bridge.invoke('setDragRegion', {
            'x': rect.left,
            'y': rect.top,
            'width': rect.width,
            'height': rect.height,
          });
        });
        return widget.child;
      },
    );
  }
}
