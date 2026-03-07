import 'package:flutter/widgets.dart';

import '../theme/ore_theme.dart';
import 'ore_switch.dart';

class OreThemeModeSwitch extends StatelessWidget {
  const OreThemeModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = OreThemeProvider.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return OreSwitch(
          value: controller.isDark,
          onChanged: (_) => controller.toggle(),
        );
      },
    );
  }
}
