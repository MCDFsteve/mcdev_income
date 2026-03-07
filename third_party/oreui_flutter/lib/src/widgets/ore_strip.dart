import 'package:flutter/material.dart';

import '../theme/ore_theme.dart';

enum OreStripTone { surface, dark }

class OreStrip extends StatelessWidget {
  const OreStrip({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.highlightColor,
    this.shadowColor,
    this.alignment = Alignment.centerLeft,
    this.tone = OreStripTone.dark,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? highlightColor;
  final Color? shadowColor;
  final AlignmentGeometry alignment;
  final OreStripTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final colors = theme.colors;
    final stroke = theme.borderWidth;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final resolvedPadding = padding ?? EdgeInsets.zero;
    final resolvedColor = color ??
        (tone == OreStripTone.dark ? colors.background : colors.surface);
    final resolvedHighlight = highlightColor ??
        (isLight
            ? colors.highlight.withValues(alpha: 1)
            : (tone == OreStripTone.dark
                ? colors.highlight.withValues(alpha: 0.14)
                : colors.highlight));
    final resolvedShadow = shadowColor ??
        (isLight
            ? colors.shadow.withValues(alpha: 0.45)
            : (tone == OreStripTone.dark
                ? colors.border.withValues(alpha: 0.5)
                : colors.shadow));

    Widget body = Container(
      width: double.infinity,
      color: resolvedColor,
      child: Stack(
        alignment: alignment,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: stroke,
            child: Container(
              color: resolvedHighlight,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: stroke,
            child: Container(
              color: resolvedShadow,
            ),
          ),
          Padding(
            padding: resolvedPadding,
            child: child,
          ),
        ],
      ),
    );

    if (margin != null) {
      body = Padding(padding: margin!, child: body);
    }

    return body;
  }
}
