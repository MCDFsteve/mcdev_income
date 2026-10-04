import 'dart:math' as math;
import '../ui/ore_material.dart';
import 'window_controller.dart';

/// Shared captions for the manager and game host; native state stays behind
/// WindowController so UI does not depend on a particular platform plugin.
class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({super.key, required this.controller});
  final WindowController controller;

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons> {
  late Stream<bool> _maximized;

  @override
  void initState() {
    super.initState();
    _maximized = widget.controller.watchMaximized();
  }

  @override
  void didUpdateWidget(covariant WindowCaptionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _maximized = widget.controller.watchMaximized();
    }
  }

  Widget _button(
    String action,
    IconData icon,
    String tooltip, {
    double size = 22,
    bool flipped = false,
  }) {
    // Inherit the button's IconTheme: white at rest, OreUI hover/press colors.
    final graphic = OrePixelIcon(icon: icon, size: size);
    return OreIconButton(
      key: ValueKey('window-$action'),
      tooltip: tooltip,
      color: Colors.white,
      icon: flipped
          ? Transform.rotate(angle: math.pi, child: graphic)
          : graphic,
      onPressed: () => widget.controller.invoke(action),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _maximized,
    initialData: false,
    builder: (context, snapshot) {
      final maximized = snapshot.data ?? false;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button('minimize', Icons.remove_rounded, '最小化'),
          _button(
            'zoom',
            maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            maximized ? '还原' : '最大化',
            size: maximized ? 18 : 22,
            flipped: maximized,
          ),
          _button('close', Icons.close_rounded, '关闭'),
        ],
      );
    },
  );
}
