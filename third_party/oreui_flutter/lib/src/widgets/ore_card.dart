import 'package:flutter/widgets.dart';

import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';
import 'ore_surface.dart';

class OreCard extends StatelessWidget {
  const OreCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final colors = theme.colors;
    final depthUnit = theme.borderWidth;
    final highlightDepth = depthUnit;
    final shadowDepth = depthUnit * 2;

    return Container(
      margin: margin,
      child: OreSurface(
        color: color ?? colors.surface,
        borderColor: colors.border,
        highlightColor: colors.highlight,
        shadowColor: colors.shadow,
        borderWidth: theme.borderWidth,
        depth: shadowDepth,
        highlightDepth: highlightDepth,
        shadowDepth: shadowDepth,
        padding: padding ?? const EdgeInsets.all(OreTokens.gapMd),
        child: DefaultTextStyle.merge(
          style: theme.typography.body.copyWith(color: colors.textPrimary),
          child: child,
        ),
      ),
    );
  }
}
