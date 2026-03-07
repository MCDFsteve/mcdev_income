import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/ore_control_colors.dart';
import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';
import 'ore_button.dart';
import 'ore_shadow.dart';

enum OreChoiceDock { bottom, top, left, right }

extension on OreChoiceDock {
  Axis get axis =>
      this == OreChoiceDock.left || this == OreChoiceDock.right
          ? Axis.vertical
          : Axis.horizontal;

  OreShadowSide get shadowSide {
    switch (this) {
      case OreChoiceDock.top:
        return OreShadowSide.top;
      case OreChoiceDock.bottom:
        return OreShadowSide.bottom;
      case OreChoiceDock.left:
        return OreShadowSide.left;
      case OreChoiceDock.right:
        return OreShadowSide.right;
    }
  }

  CrossAxisAlignment get crossAxisAlignment {
    switch (this) {
      case OreChoiceDock.top:
      case OreChoiceDock.left:
        return CrossAxisAlignment.start;
      case OreChoiceDock.bottom:
      case OreChoiceDock.right:
        return CrossAxisAlignment.end;
    }
  }
}

class OreChoiceButtons extends StatelessWidget {
  const OreChoiceButtons({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.size = OreButtonSize.md,
    this.fullWidth = false,
    this.buttonWidth,
    this.dock = OreChoiceDock.bottom,
  });

  final List<Widget> items;
  final int selectedIndex;
  final ValueChanged<int>? onChanged;
  final OreButtonSize size;
  final bool fullWidth;
  final double? buttonWidth;
  final OreChoiceDock dock;

  bool get _enabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final colors = resolveControlColors(context, theme.colors);
    final borderWidth = theme.borderWidth;
    final indicatorHeight =
        borderWidth * OreTokens.choiceIndicatorHeightUnits;
    final overlap = borderWidth;
    final axis = dock.axis;
    final pressedAxis =
        axis == Axis.vertical ? Axis.horizontal : Axis.vertical;
    final shadowSide = dock.shadowSide;
    final indicatorInset = borderWidth;

    final children = List.generate(items.length, (index) {
      final selected = index == selectedIndex;
      final isVertical = axis == Axis.vertical;
      final indicator = Align(
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor:
              isVertical ? 1 : OreTokens.choiceIndicatorWidthFactor,
          heightFactor:
              isVertical ? OreTokens.choiceIndicatorWidthFactor : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.textInverse),
          ),
        ),
      );
      final button = OreButton(
        onPressed: _enabled ? () => onChanged?.call(index) : null,
        size: size,
        variant:
            selected ? OreButtonVariant.primary : OreButtonVariant.secondary,
        forcePressed: selected,
        forcePressedKeepsColor: selected,
        width: buttonWidth,
        pressedAxis: pressedAxis,
        shadowSide: shadowSide,
        child: items[index],
      );
      final decorated = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          if (selected)
            if (isVertical)
              Positioned(
                top: 0,
                bottom: 0,
                width: indicatorHeight,
                left: dock == OreChoiceDock.left ? indicatorInset : null,
                right: dock == OreChoiceDock.right ? indicatorInset : null,
                child: indicator,
              )
            else
              Positioned(
                left: 0,
                right: 0,
                height: indicatorHeight,
                top: dock == OreChoiceDock.top ? indicatorInset : null,
                bottom:
                    dock == OreChoiceDock.bottom ? indicatorInset : null,
                child: indicator,
              ),
        ],
      );

      return decorated;
    });

    return _OverlapStack(
      axis: axis,
      overlap: overlap,
      expand: fullWidth && buttonWidth == null,
      crossAxisAlignment: dock.crossAxisAlignment,
      textDirection: Directionality.of(context),
      topIndex: selectedIndex,
      children: children,
    );
  }
}

class _OverlapStack extends MultiChildRenderObjectWidget {
  const _OverlapStack({
    required this.axis,
    required this.overlap,
    required this.expand,
    required this.crossAxisAlignment,
    required this.textDirection,
    required this.topIndex,
    required super.children,
  });

  final Axis axis;
  final double overlap;
  final bool expand;
  final CrossAxisAlignment crossAxisAlignment;
  final TextDirection textDirection;
  final int topIndex;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderOverlapStack(
      axis: axis,
      overlap: overlap,
      expand: expand,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: textDirection,
      topIndex: topIndex,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderOverlapStack renderObject,
  ) {
    renderObject
      ..axis = axis
      ..overlap = overlap
      ..expand = expand
      ..crossAxisAlignment = crossAxisAlignment
      ..textDirection = textDirection
      ..topIndex = topIndex;
  }
}

class _OverlapParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderOverlapStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OverlapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _OverlapParentData> {
  _RenderOverlapStack({
    required Axis axis,
    required double overlap,
    required bool expand,
    required CrossAxisAlignment crossAxisAlignment,
    required TextDirection textDirection,
    required int topIndex,
  })  : _axis = axis,
        _overlap = overlap,
        _expand = expand,
        _crossAxisAlignment = crossAxisAlignment,
        _textDirection = textDirection,
        _topIndex = topIndex;

  Axis _axis;
  double _overlap;
  bool _expand;
  CrossAxisAlignment _crossAxisAlignment;
  TextDirection _textDirection;
  int _topIndex;

  Axis get axis => _axis;
  set axis(Axis value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  double get overlap => _overlap;
  set overlap(double value) {
    if (_overlap == value) return;
    _overlap = value;
    markNeedsLayout();
  }

  bool get expand => _expand;
  set expand(bool value) {
    if (_expand == value) return;
    _expand = value;
    markNeedsLayout();
  }

  CrossAxisAlignment get crossAxisAlignment => _crossAxisAlignment;
  set crossAxisAlignment(CrossAxisAlignment value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  int get topIndex => _topIndex;
  set topIndex(int value) {
    if (_topIndex == value) return;
    _topIndex = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OverlapParentData) {
      child.parentData = _OverlapParentData();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final children = getChildrenAsList();
    if (children.isEmpty ||
        topIndex < 0 ||
        topIndex >= children.length) {
      defaultPaint(context, offset);
      return;
    }

    for (var i = 0; i < children.length; i++) {
      if (i == topIndex) continue;
      final child = children[i];
      final childParentData = child.parentData as _OverlapParentData;
      context.paintChild(child, offset + childParentData.offset);
    }

    final topChild = children[topIndex];
    final topParentData = topChild.parentData as _OverlapParentData;
    context.paintChild(topChild, offset + topParentData.offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result,
      {required Offset position}) {
    final children = getChildrenAsList();
    if (children.isEmpty) return false;

    bool hitChild(RenderBox child) {
      final childParentData = child.parentData as _OverlapParentData;
      return result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (result, transformed) {
          return child.hitTest(result, position: transformed);
        },
      );
    }

    if (topIndex >= 0 && topIndex < children.length) {
      if (hitChild(children[topIndex])) return true;
    }

    for (var i = children.length - 1; i >= 0; i--) {
      if (i == topIndex) continue;
      if (hitChild(children[i])) return true;
    }

    return false;
  }

  @override
  void performLayout() {
    final clampedOverlap = math.max(0.0, overlap);
    final children = getChildrenAsList();
    if (children.isEmpty) {
      size = constraints.constrain(Size.zero);
      return;
    }

    double maxCrossExtent = 0.0;
    double totalMainExtent = 0.0;

    final bool canExpand = axis == Axis.horizontal
        ? expand && constraints.hasBoundedWidth
        : expand && constraints.hasBoundedHeight;

    if (axis == Axis.horizontal) {
      if (canExpand) {
        final count = children.length;
        final width = constraints.maxWidth;
        final childWidth =
            (width + clampedOverlap * (count - 1)) / count;
        final childConstraints = BoxConstraints(
          minWidth: childWidth,
          maxWidth: childWidth,
          minHeight: 0,
          maxHeight: constraints.maxHeight,
        );

        for (final child in children) {
          child.layout(childConstraints, parentUsesSize: true);
          maxCrossExtent = math.max(maxCrossExtent, child.size.height);
        }
        totalMainExtent = width;
      } else {
        final childConstraints = constraints.loosen();
        for (final child in children) {
          child.layout(childConstraints, parentUsesSize: true);
          maxCrossExtent = math.max(maxCrossExtent, child.size.height);
          totalMainExtent += child.size.width;
        }
        totalMainExtent -= clampedOverlap * (children.length - 1);
      }

      size = constraints.constrain(Size(totalMainExtent, maxCrossExtent));

      if (children.isEmpty) return;

      if (canExpand) {
        final count = children.length;
        final childWidth =
            (totalMainExtent + clampedOverlap * (count - 1)) / count;
        double x = _textDirection == TextDirection.rtl
            ? size.width - childWidth
            : 0.0;
        final step = childWidth - clampedOverlap;

        for (final child in children) {
          final childParentData =
              child.parentData as _OverlapParentData;
          final y = _crossAxisOffset(
            size.height,
            child.size.height,
            axis,
          );
          childParentData.offset = Offset(x, y);
          x += _textDirection == TextDirection.rtl ? -step : step;
        }
      } else {
        double x = _textDirection == TextDirection.rtl
            ? size.width
            : 0.0;
        for (final child in children) {
          final childParentData =
              child.parentData as _OverlapParentData;
          final y = _crossAxisOffset(
            size.height,
            child.size.height,
            axis,
          );
          if (_textDirection == TextDirection.rtl) {
            x -= child.size.width;
            childParentData.offset = Offset(x, y);
            x += clampedOverlap;
          } else {
            childParentData.offset = Offset(x, y);
            x += child.size.width - clampedOverlap;
          }
        }
      }
    } else {
      if (canExpand) {
        final count = children.length;
        final height = constraints.maxHeight;
        final childHeight =
            (height + clampedOverlap * (count - 1)) / count;
        final childConstraints = BoxConstraints(
          minWidth: 0,
          maxWidth: constraints.maxWidth,
          minHeight: childHeight,
          maxHeight: childHeight,
        );

        for (final child in children) {
          child.layout(childConstraints, parentUsesSize: true);
          maxCrossExtent = math.max(maxCrossExtent, child.size.width);
        }
        totalMainExtent = height;
      } else {
        final childConstraints = constraints.loosen();
        for (final child in children) {
          child.layout(childConstraints, parentUsesSize: true);
          maxCrossExtent = math.max(maxCrossExtent, child.size.width);
          totalMainExtent += child.size.height;
        }
        totalMainExtent -= clampedOverlap * (children.length - 1);
      }

      size = constraints.constrain(Size(maxCrossExtent, totalMainExtent));

      if (children.isEmpty) return;

      if (canExpand) {
        final count = children.length;
        final childHeight =
            (totalMainExtent + clampedOverlap * (count - 1)) / count;
        double y = 0.0;
        final step = childHeight - clampedOverlap;

        for (final child in children) {
          final childParentData =
              child.parentData as _OverlapParentData;
          final x = _crossAxisOffset(
            size.width,
            child.size.width,
            axis,
          );
          childParentData.offset = Offset(x, y);
          y += step;
        }
      } else {
        double y = 0.0;
        for (final child in children) {
          final childParentData =
              child.parentData as _OverlapParentData;
          final x = _crossAxisOffset(
            size.width,
            child.size.width,
            axis,
          );
          childParentData.offset = Offset(x, y);
          y += child.size.height - clampedOverlap;
        }
      }
    }
  }

  double _crossAxisOffset(
    double crossExtent,
    double childExtent,
    Axis axis,
  ) {
    switch (crossAxisAlignment) {
      case CrossAxisAlignment.start:
        return 0.0;
      case CrossAxisAlignment.center:
        return (crossExtent - childExtent) / 2;
      case CrossAxisAlignment.end:
        return crossExtent - childExtent;
      case CrossAxisAlignment.stretch:
      case CrossAxisAlignment.baseline:
        return 0.0;
    }
  }
}
