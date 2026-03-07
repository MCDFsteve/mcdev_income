import 'package:flutter/material.dart';

import '../theme/ore_highlight.dart';
import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';
import 'ore_surface.dart';

class OreCheckbox extends StatefulWidget {
  const OreCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.tristate = false,
    this.contentPadding,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? label;
  final bool tristate;
  final EdgeInsetsGeometry? contentPadding;

  @override
  State<OreCheckbox> createState() => _OreCheckboxState();
}

class _OreCheckboxState extends State<OreCheckbox> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final colors = theme.colors;
    final isChecked = widget.value == true;
    final isMixed = widget.tristate && widget.value == null;
    final isPressed = _pressed && _enabled;
    final isHovered = _hovered && _enabled;
    final depthUnit = theme.borderWidth;
    final highlightDepth = depthUnit;
    final visualDepth = depthUnit * 2;
    final shadowDepth = isPressed ? 0.0 : visualDepth;
    final indicatorSize = depthUnit * OreTokens.checkboxSizeUnits;
    final markSize = depthUnit * OreTokens.checkboxMarkUnits;
    final mixedWidth = depthUnit * OreTokens.checkboxMixedWidthUnits;
    final mixedHeight = depthUnit * OreTokens.checkboxMixedHeightUnits;

    final background = _resolveBackground(
      colors,
      isChecked || isMixed,
      isHovered,
      isPressed,
      _enabled,
    );
    final borderColor = _enabled ? colors.border : colors.borderLight;
    final shadowColor =
        isChecked || isMixed ? colors.accentPressed : colors.shadow;
    final highlightColor = OreHighlight.resolve(
      colors: colors,
      colored: isChecked || isMixed,
      hovered: isHovered,
    );

    final pressedCut = isPressed ? visualDepth : 0.0;
    final pressedHeight =
        (indicatorSize - pressedCut).clamp(0.0, indicatorSize);
    final contentOffsetY = isPressed ? 0.0 : -visualDepth / 2;

    Widget mark = Center(
      child: _buildMark(
        colors,
        isChecked,
        isMixed,
        _enabled,
        checkSize: markSize,
        mixedWidth: mixedWidth,
        mixedHeight: mixedHeight,
      ),
    );
    mark = AnimatedContainer(
      duration: OreTokens.fast,
      transform: Matrix4.translationValues(0, contentOffsetY, 0),
      child: mark,
    );

    final indicator = SizedBox(
      width: indicatorSize,
      height: indicatorSize,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: indicatorSize,
          height: pressedHeight,
          child: OreSurface(
            color: background,
            borderColor: borderColor,
            highlightColor: highlightColor,
            shadowColor: shadowColor,
            borderWidth: theme.borderWidth,
            depth: visualDepth,
            highlightDepth: highlightDepth,
            shadowDepth: shadowDepth,
            swapHighlightOnPressed: false,
            pressed: isPressed,
            padding: EdgeInsets.zero,
            child: mark,
          ),
        ),
      ),
    );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        if (widget.label != null) ...[
          const SizedBox(width: OreTokens.gapSm),
          DefaultTextStyle(
            style: theme.typography.body.copyWith(
              color: _enabled ? colors.textPrimary : colors.textDisabled,
            ),
            child: widget.label!,
          ),
        ],
      ],
    );

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        onTap: _enabled ? _toggle : null,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: widget.contentPadding ?? const EdgeInsets.all(OreTokens.gapXs),
          child: row,
        ),
      ),
    );
  }

  Widget _buildMark(
    OreColors colors,
    bool isChecked,
    bool isMixed,
    bool enabled, {
    required double checkSize,
    required double mixedWidth,
    required double mixedHeight,
  }) {
    if (isChecked) {
      return Icon(
        Icons.check,
        size: checkSize,
        color: colors.textInverse,
      );
    }
    if (isMixed) {
      return Container(
        width: mixedWidth,
        height: mixedHeight,
        color: colors.textInverse,
      );
    }
    return const SizedBox.shrink();
  }

  Color _resolveBackground(
    OreColors colors,
    bool selected,
    bool hovered,
    bool pressed,
    bool enabled,
  ) {
    if (!enabled) {
      return colors.surface;
    }
    if (selected) {
      if (pressed) return colors.accentPressed;
      if (hovered) return colors.accentHover;
      return colors.accent;
    }
    if (pressed) return colors.shadow;
    if (hovered) return colors.surfaceHover;
    return colors.borderLight;
  }

  void _toggle() {
    if (!widget.tristate) {
      widget.onChanged?.call(!(widget.value ?? false));
      return;
    }
    if (widget.value == null) {
      widget.onChanged?.call(true);
    } else if (widget.value == true) {
      widget.onChanged?.call(false);
    } else {
      widget.onChanged?.call(null);
    }
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }
}
