import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ore_control_colors.dart';
import '../theme/ore_highlight.dart';
import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';
import 'ore_surface.dart';

class OreScrollbar extends StatefulWidget {
  const OreScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.axis = Axis.vertical,
    this.thickness,
    this.trackThickness,
    this.thumbThickness,
    this.thumbMinLength,
    this.trackPadding,
    this.contentPadding,
    this.hideSystemScrollbar = true,
    this.thumbVisibility = true,
    this.trackVisibility = true,
  });

  final Widget child;
  final ScrollController? controller;
  final Axis axis;
  final double? thickness;
  final double? trackThickness;
  final double? thumbThickness;
  final double? thumbMinLength;
  final EdgeInsetsGeometry? trackPadding;
  final EdgeInsetsGeometry? contentPadding;
  final bool hideSystemScrollbar;
  final bool thumbVisibility;
  final bool trackVisibility;

  @override
  State<OreScrollbar> createState() => _OreScrollbarState();
}

class _OreScrollbarState extends State<OreScrollbar> {
  final ScrollController _fallbackController = ScrollController();
  bool _hovered = false;
  bool _pressed = false;
  bool _dragging = false;
  double _dragStartThumbOffset = 0.0;
  double _dragDelta = 0.0;

  ScrollController get _controller => widget.controller ?? _fallbackController;

  @override
  void dispose() {
    _fallbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (widget.contentPadding != null) {
      child = Padding(padding: widget.contentPadding!, child: child);
    }
    if (widget.controller == null) {
      child = PrimaryScrollController(
        controller: _fallbackController,
        child: child,
      );
    }
    if (widget.hideSystemScrollbar) {
      child = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      );
    }

    return Stack(
      children: [
        child,
        _buildScrollbar(context),
      ],
    );
  }

  Widget _buildScrollbar(BuildContext context) {
    if (!widget.thumbVisibility && !widget.trackVisibility) {
      return const SizedBox.shrink();
    }

    final theme = OreTheme.of(context);
    final unit = theme.borderWidth;
    final barThickness =
        widget.thickness ?? unit * OreTokens.scrollbarWidthUnits;
    final isVertical = widget.axis == Axis.vertical;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final bar = _ScrollbarBar(
      controller: _controller,
      axis: widget.axis,
      unit: unit,
      trackThickness:
          widget.trackThickness ?? unit * OreTokens.scrollbarTrackWidthUnits,
      thumbThickness:
          widget.thumbThickness ?? unit * OreTokens.scrollbarThumbWidthUnits,
      thumbMinLength: widget.thumbMinLength ??
          unit * OreTokens.scrollbarThumbMinLengthUnits,
      trackPadding: widget.trackPadding ??
          EdgeInsets.symmetric(
            vertical: unit * OreTokens.scrollbarTrackInsetUnits,
            horizontal: unit * OreTokens.scrollbarTrackInsetUnits,
          ),
      thumbVisibility: widget.thumbVisibility,
      trackVisibility: widget.trackVisibility,
      hovered: _hovered,
      pressed: _pressed || _dragging,
      onHoverChanged: _setHovered,
      onPressedChanged: _setPressed,
      onDragStart: _handleDragStart,
      onDragUpdate: _handleDragUpdate,
      onDragEnd: _handleDragEnd,
    );

    if (isVertical) {
      return Positioned(
        top: 0,
        bottom: 0,
        right: isRtl ? null : 0,
        left: isRtl ? 0 : null,
        width: barThickness,
        child: bar,
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: barThickness,
      child: bar,
    );
  }

  void _handleDragStart(double thumbOffset) {
    _dragging = true;
    _pressed = true;
    _dragStartThumbOffset = thumbOffset;
    _dragDelta = 0.0;
    setState(() {});
  }

  void _handleDragUpdate(
    _ScrollbarGeometry geometry,
    double delta,
  ) {
    if (!_dragging) return;
    final maxThumbOffset = geometry.maxThumbOffset;
    if (maxThumbOffset <= 0 || geometry.scrollableExtent <= 0) {
      return;
    }
    _dragDelta += delta;
    final nextThumbOffset =
        (_dragStartThumbOffset + _dragDelta).clamp(0.0, maxThumbOffset);
    final fraction = nextThumbOffset / maxThumbOffset;
    final target =
        geometry.minScrollExtent + fraction * geometry.scrollableExtent;
    _controller.jumpTo(target);
  }

  void _handleDragEnd() {
    if (!_dragging) return;
    _dragging = false;
    _pressed = false;
    setState(() {});
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

class _ScrollbarBar extends StatelessWidget {
  const _ScrollbarBar({
    required this.controller,
    required this.axis,
    required this.unit,
    required this.trackThickness,
    required this.thumbThickness,
    required this.thumbMinLength,
    required this.trackPadding,
    required this.thumbVisibility,
    required this.trackVisibility,
    required this.hovered,
    required this.pressed,
    required this.onHoverChanged,
    required this.onPressedChanged,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ScrollController controller;
  final Axis axis;
  final double unit;
  final double trackThickness;
  final double thumbThickness;
  final double thumbMinLength;
  final EdgeInsetsGeometry trackPadding;
  final bool thumbVisibility;
  final bool trackVisibility;
  final bool hovered;
  final bool pressed;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onPressedChanged;
  final ValueChanged<double> onDragStart;
  final void Function(_ScrollbarGeometry geometry, double delta) onDragUpdate;
  final VoidCallback onDragEnd;

  bool get isVertical => axis == Axis.vertical;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.hasClients) {
          return const SizedBox.shrink();
        }
        final position = controller.position;
        if (!position.hasContentDimensions || !position.hasViewportDimension) {
          return const SizedBox.shrink();
        }
        final scrollExtent = position.maxScrollExtent - position.minScrollExtent;
        if (scrollExtent <= 0 || position.viewportDimension <= 0) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final mainSize =
                isVertical ? constraints.maxHeight : constraints.maxWidth;
            final crossSize =
                isVertical ? constraints.maxWidth : constraints.maxHeight;
            if (mainSize.isInfinite || mainSize <= 0 || crossSize <= 0) {
              return const SizedBox.shrink();
            }

            final resolvedPadding =
                trackPadding.resolve(Directionality.of(context));
            final startPadding =
                isVertical ? resolvedPadding.top : resolvedPadding.left;
            final endPadding =
                isVertical ? resolvedPadding.bottom : resolvedPadding.right;
            final trackLength =
                math.max(0.0, mainSize - startPadding - endPadding);
            if (trackLength <= 0) {
              return const SizedBox.shrink();
            }

            final contentExtent =
                position.maxScrollExtent + position.viewportDimension;
            final idealThumbLength =
                (trackLength * position.viewportDimension / contentExtent)
                    .clamp(0.0, trackLength);
            final resolvedThumbLength = math.max(
              math.min(trackLength, thumbMinLength),
              idealThumbLength,
            );
            final maxThumbOffset =
                math.max(0.0, trackLength - resolvedThumbLength);
            final scrollFraction = (position.pixels - position.minScrollExtent) /
                scrollExtent;
            final clampedFraction = scrollFraction.isFinite
                ? scrollFraction.clamp(0.0, 1.0)
                : 0.0;
            final thumbOffset = maxThumbOffset * clampedFraction;
            final geometry = _ScrollbarGeometry(
              trackStart: startPadding,
              trackLength: trackLength,
              thumbOffset: thumbOffset,
              thumbLength: resolvedThumbLength,
              maxThumbOffset: maxThumbOffset,
              scrollableExtent: scrollExtent,
              minScrollExtent: position.minScrollExtent,
            );

            final resolvedTrackThickness = math.min(trackThickness, crossSize);
            final resolvedThumbThickness = math.min(thumbThickness, crossSize);
            final trackOffset = (crossSize - resolvedTrackThickness) / 2;
            final thumbOffsetCross = (crossSize - resolvedThumbThickness) / 2;

            final track = trackVisibility
                ? Positioned(
                    left: isVertical ? trackOffset : startPadding,
                    top: isVertical ? startPadding : trackOffset,
                    width: isVertical ? resolvedTrackThickness : trackLength,
                    height: isVertical ? trackLength : resolvedTrackThickness,
                    child: _buildTrack(context),
                  )
                : const SizedBox.shrink();

            final thumb = thumbVisibility
                ? Positioned(
                    left: isVertical
                        ? thumbOffsetCross
                        : startPadding + thumbOffset,
                    top: isVertical
                        ? startPadding + thumbOffset
                        : thumbOffsetCross,
                    width: isVertical ? resolvedThumbThickness : resolvedThumbLength,
                    height: isVertical ? resolvedThumbLength : resolvedThumbThickness,
                    child: _buildThumb(
                      context,
                      geometry,
                      resolvedThumbThickness,
                    ),
                  )
                : const SizedBox.shrink();

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: trackVisibility
                  ? (details) => _handleTrackTap(details, geometry)
                  : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  track,
                  thumb,
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTrack(BuildContext context) {
    final theme = OreTheme.of(context);
    final colors = theme.colors;
    final brightness = Theme.of(context).brightness;
    final trackColor = brightness == Brightness.dark
        ? Color.lerp(colors.surface, const Color(0xFFFFFFFF), 0.18)!
        : Color.lerp(colors.surfaceDark, colors.shadowStrong, 0.9)!;
    return Container(color: trackColor);
  }

  Widget _buildThumb(
    BuildContext context,
    _ScrollbarGeometry geometry,
    double resolvedThumbThickness,
  ) {
    final theme = OreTheme.of(context);
    final colors = resolveControlColors(context, theme.colors);
    final isPressed = pressed;
    final visualDepth = unit * 2;
    final highlightDepth = unit;
    final shadowDepth = visualDepth;
    final brightness = Theme.of(context).brightness;
    final shadowColor = brightness == Brightness.dark
        ? Color.lerp(colors.shadowStrong, const Color(0xFF000000), 0.4)!
        : Color.lerp(colors.shadow, colors.surface, 0.85)!;
    final background = colors.surface;
    final highlightColor = OreHighlight.resolve(
      colors: colors,
      colored: false,
      hovered: false,
    );

    final surface = OreSurface(
      color: background,
      borderColor: colors.border,
      highlightColor: highlightColor,
      shadowColor: shadowColor,
      borderWidth: unit,
      depth: visualDepth,
      highlightDepth: highlightDepth,
      shadowDepth: shadowDepth,
      swapHighlightOnPressed: false,
      pressed: isPressed,
      padding: EdgeInsets.zero,
      child: const SizedBox.expand(),
    );

    final pressedCut = isPressed ? visualDepth : 0.0;
    final pressedExtent =
        (geometry.thumbLength - pressedCut).clamp(0.0, geometry.thumbLength);

    const shadowStripHeight = 2.0;
    const shadowStripColor = Color(0x80000000);

    Widget thumbBody = SizedBox(
      width: isVertical ? resolvedThumbThickness : geometry.thumbLength,
      height: isVertical ? geometry.thumbLength : resolvedThumbThickness,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: isVertical ? resolvedThumbThickness : pressedExtent,
          height: isVertical ? pressedExtent : resolvedThumbThickness,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: surface),
              Positioned(
                left: 0,
                right: 0,
                bottom: -shadowStripHeight,
                height: shadowStripHeight,
                child: Container(color: shadowStripColor),
              ),
            ],
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      cursor: pressed
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onPressedChanged(true),
        onTapUp: (_) => onPressedChanged(false),
        onTapCancel: () => onPressedChanged(false),
        onVerticalDragStart:
            isVertical ? (_) => onDragStart(geometry.thumbOffset) : null,
        onVerticalDragUpdate: isVertical
            ? (details) => onDragUpdate(geometry, details.delta.dy)
            : null,
        onVerticalDragEnd: isVertical ? (_) => onDragEnd() : null,
        onHorizontalDragStart:
            isVertical ? null : (_) => onDragStart(geometry.thumbOffset),
        onHorizontalDragUpdate: isVertical
            ? null
            : (details) => onDragUpdate(geometry, details.delta.dx),
        onHorizontalDragEnd: isVertical ? null : (_) => onDragEnd(),
        child: thumbBody,
      ),
    );
  }

  void _handleTrackTap(
    TapDownDetails details,
    _ScrollbarGeometry geometry,
  ) {
    if (geometry.maxThumbOffset <= 0) return;
    final localPosition = details.localPosition;
    final tapOffset = isVertical ? localPosition.dy : localPosition.dx;
    final thumbStart = geometry.trackStart + geometry.thumbOffset;
    final thumbEnd = thumbStart + geometry.thumbLength;
    if (tapOffset >= thumbStart && tapOffset <= thumbEnd) {
      return;
    }
    final targetThumbOffset =
        (tapOffset - geometry.trackStart - geometry.thumbLength / 2)
            .clamp(0.0, geometry.maxThumbOffset);
    final fraction = geometry.maxThumbOffset <= 0
        ? 0.0
        : targetThumbOffset / geometry.maxThumbOffset;
    final target =
        geometry.minScrollExtent + fraction * geometry.scrollableExtent;
    controller.jumpTo(target);
  }
}

class _ScrollbarGeometry {
  const _ScrollbarGeometry({
    required this.trackStart,
    required this.trackLength,
    required this.thumbOffset,
    required this.thumbLength,
    required this.maxThumbOffset,
    required this.scrollableExtent,
    required this.minScrollExtent,
  });

  final double trackStart;
  final double trackLength;
  final double thumbOffset;
  final double thumbLength;
  final double maxThumbOffset;
  final double scrollableExtent;
  final double minScrollExtent;
}
