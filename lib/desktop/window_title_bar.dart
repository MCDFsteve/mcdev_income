import 'package:flutter/services.dart';
import '../ui/ore_material.dart';

/// Window operations stay local to the process owning this Flutter view.
class DesktopWindowBridge {
  const DesktopWindowBridge();
  static const channel = MethodChannel('mcdev_income/window_chrome');

  Future<void> invoke(String action, [Object? arguments]) async {
    await channel.invokeMethod<void>(action, arguments);
  }
}

class OreWindowTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const OreWindowTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bridge = const DesktopWindowBridge(),
    this.trafficLights = true,
  });

  static const height = 48.0;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final DesktopWindowBridge bridge;
  final bool trafficLights;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final ore = OreTheme.of(context);
    final colors = OreColors.dark();
    return SizedBox(
      height: height,
      child: OreSurface(
        color: colors.surface,
        borderColor: colors.border,
        highlightColor: colors.highlight,
        shadowColor: colors.shadowStrong,
        borderWidth: ore.borderWidth,
        depth: ore.borderWidth,
        padding: EdgeInsets.zero,
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: Row(
            children: [
              SizedBox(width: trafficLights ? 86 : 12),
              Expanded(
                child: _WindowDragRegion(
                  bridge: bridge,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      subtitle == null ? title : '$title · $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ore.typography.choiceTitle.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              ...actions,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Register geometry ahead of the gesture so AppKit can start dragging on the
/// original mouse-down, without a round trip through an asynchronous channel.
class _WindowDragRegion extends StatefulWidget {
  const _WindowDragRegion({required this.bridge, required this.child});
  final DesktopWindowBridge bridge;
  final Widget child;

  @override
  State<_WindowDragRegion> createState() => _WindowDragRegionState();
}

class _WindowDragRegionState extends State<_WindowDragRegion> {
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
