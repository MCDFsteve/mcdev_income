import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'ore_shadow.dart';

import '../theme/ore_theme.dart';

class OreSurface extends StatelessWidget {
  const OreSurface({
    super.key,
    required this.child,
    required this.color,
    required this.borderColor,
    required this.highlightColor,
    required this.shadowColor,
    required this.borderWidth,
    required this.depth,
    this.highlightDepth,
    this.shadowDepth,
    this.swapHighlightOnPressed = true,
    this.alignment = AlignmentDirectional.topStart,
    this.padding,
    this.pressed = false,
    this.ignoreShadowPadding = false,
    this.shadowOnTop = false,
    this.shadowSide,
    this.cornerHighlightFactor = 0.2,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final Color highlightColor;
  final Color shadowColor;
  final double borderWidth;
  final double depth;
  final double? highlightDepth;
  final double? shadowDepth;
  final bool swapHighlightOnPressed;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry? padding;
  final bool pressed;
  final bool ignoreShadowPadding;
  final bool shadowOnTop;
  final OreShadowSide? shadowSide;
  final double cornerHighlightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final shouldSwap = pressed && swapHighlightOnPressed;
    final highlight = shouldSwap ? shadowColor : highlightColor;
    final shadow = shouldSwap ? highlightColor : shadowColor;
    final cornerHighlight = highlight.a == 0
        ? highlight
        : Color.lerp(
            highlight, const Color(0xFFFFFFFF), cornerHighlightFactor)!;
    final resolvedHighlightDepth =
        math.max(0.0, highlightDepth ?? depth);
    final resolvedShadowDepth =
        math.max(0.0, shadowDepth ?? depth);
    final resolvedShadowSide =
        shadowSide ?? (shadowOnTop ? OreShadowSide.top : OreShadowSide.bottom);
    final weakHighlight = highlight.a == 0
        ? highlight
        : highlight.withValues(
            alpha: (highlight.a * 0.66).clamp(0.0, 1.0),
          );

    final resolvedPadding =
        padding?.resolve(Directionality.of(context)) ??
            EdgeInsets.all(theme.gap);
    final shadowOffsetTop =
        resolvedShadowSide == OreShadowSide.top ? resolvedShadowDepth : 0.0;
    final shadowOffsetBottom =
        resolvedShadowSide == OreShadowSide.bottom ? resolvedShadowDepth : 0.0;
    final shadowOffsetLeft =
        resolvedShadowSide == OreShadowSide.left ? resolvedShadowDepth : 0.0;
    final shadowOffsetRight =
        resolvedShadowSide == OreShadowSide.right ? resolvedShadowDepth : 0.0;
    final adjustedPadding = ignoreShadowPadding
        ? EdgeInsets.fromLTRB(
            math.max(0, resolvedPadding.left - shadowOffsetLeft),
            math.max(0, resolvedPadding.top - shadowOffsetTop),
            math.max(0, resolvedPadding.right - shadowOffsetRight),
            math.max(0, resolvedPadding.bottom - shadowOffsetBottom),
          )
        : resolvedPadding;
    final leftInset = borderWidth + shadowOffsetLeft;
    final rightInset = borderWidth + shadowOffsetRight;
    final topInset = borderWidth + shadowOffsetTop;
    final bottomInset = borderWidth + shadowOffsetBottom;

    return Container(
      decoration: BoxDecoration(color: color),
      child: Stack(
        alignment: alignment,
        children: [
          if (borderWidth > 0) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: borderWidth,
              child: Container(color: borderColor),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: borderWidth,
              child: Container(color: borderColor),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: borderWidth,
              child: Container(color: borderColor),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: borderWidth,
              child: Container(color: borderColor),
            ),
          ],
          if (resolvedHighlightDepth > 0) ...[
            // Top highlight (strong)
            Positioned(
              left: leftInset,
              right: rightInset,
              top: topInset,
              height: resolvedHighlightDepth,
              child: Container(color: highlight),
            ),
            // Left highlight (strong)
            Positioned(
              left: leftInset,
              top: topInset + resolvedHighlightDepth,
              bottom: bottomInset + resolvedHighlightDepth,
              width: resolvedHighlightDepth,
              child: Container(color: highlight),
            ),
            // Right highlight (weak)
            Positioned(
              right: rightInset,
              top: topInset + resolvedHighlightDepth,
              bottom: bottomInset + resolvedHighlightDepth,
              width: resolvedHighlightDepth,
              child: Container(color: weakHighlight),
            ),
            // Bottom highlight (weak) sits above shadow
            Positioned(
              left: leftInset,
              right: rightInset,
              bottom: bottomInset,
              height: resolvedHighlightDepth,
              child: Container(color: weakHighlight),
            ),
            // Bright corners (top-right, bottom-left)
            Positioned(
              right: rightInset,
              top: topInset,
              width: resolvedHighlightDepth,
              height: resolvedHighlightDepth,
              child: Container(color: cornerHighlight),
            ),
            Positioned(
              left: leftInset,
              bottom: bottomInset,
              width: resolvedHighlightDepth,
              height: resolvedHighlightDepth,
              child: Container(color: cornerHighlight),
            ),
          ],
          if (resolvedShadowDepth > 0) ...[
            if (resolvedShadowSide == OreShadowSide.bottom)
              Positioned(
                left: borderWidth,
                right: borderWidth,
                bottom: borderWidth,
                height: resolvedShadowDepth,
                child: Container(color: shadow),
              ),
            if (resolvedShadowSide == OreShadowSide.top)
              Positioned(
                left: borderWidth,
                right: borderWidth,
                top: borderWidth,
                height: resolvedShadowDepth,
                child: Container(color: shadow),
              ),
            if (resolvedShadowSide == OreShadowSide.left)
              Positioned(
                left: borderWidth,
                top: borderWidth,
                bottom: borderWidth,
                width: resolvedShadowDepth,
                child: Container(color: shadow),
              ),
            if (resolvedShadowSide == OreShadowSide.right)
              Positioned(
                right: borderWidth,
                top: borderWidth,
                bottom: borderWidth,
                width: resolvedShadowDepth,
                child: Container(color: shadow),
              ),
          ],
          Padding(
            padding: adjustedPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}
