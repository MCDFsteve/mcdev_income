import 'package:flutter/material.dart';

import '../theme/ore_theme.dart';

class OreDivider extends StatelessWidget {
  const OreDivider({
    super.key,
    this.thickness = 2,
    this.color,
    this.margin,
  });

  final double thickness;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);

    Widget divider = Container(
      height: thickness,
      color: color ?? theme.colors.shadow,
    );

    if (margin != null) {
      divider = Padding(padding: margin!, child: divider);
    }

    return divider;
  }
}
