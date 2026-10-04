import 'package:flutter/foundation.dart';
import 'window_controller.dart';
import 'window_caption_buttons.dart';
export 'window_controller.dart';
export 'game_window_controller.dart';
import '../ui/ore_material.dart';

class OreWindowTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const OreWindowTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bridge = const ManagedWindowController(),
    this.trafficLights,
  });

  static const height = 48.0;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final WindowController bridge;
  final bool? trafficLights;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final lights =
        trafficLights ?? defaultTargetPlatform == TargetPlatform.macOS;
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
              SizedBox(width: lights ? 86 : 12),
              Expanded(
                child: bridge.dragRegion(
                  Align(
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
              if (!lights) WindowCaptionButtons(controller: bridge),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
