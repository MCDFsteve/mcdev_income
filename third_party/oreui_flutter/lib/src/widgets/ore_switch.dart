import 'package:flutter/widgets.dart';

import '../theme/ore_control_colors.dart';
import '../theme/ore_highlight.dart';
import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';
import 'ore_knob.dart';
import 'ore_surface.dart';

class OreSwitch extends StatefulWidget {
  const OreSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<OreSwitch> createState() => _OreSwitchState();
}

class _SwitchMetrics {
  const _SwitchMetrics({
    required this.trackWidth,
    required this.trackHeight,
    required this.knobSize,
    required this.iconSize,
  });

  final double trackWidth;
  final double trackHeight;
  final double knobSize;
  final double iconSize;

  double get maxLeft => trackWidth - knobSize;
  double get iconBoxWidth => trackWidth / 2;
}

class _OreSwitchState extends State<OreSwitch>
    with SingleTickerProviderStateMixin {
  static const int _firstUpMs = 60;
  static const int _firstDownMs = 60;
  static const int _midPauseMs = 30;
  static const int _secondUpMs = 60;
  static const int _secondDownMs = 60;
  static const int _endPauseMs = 30;
  static const int _totalMs =
      _firstUpMs +
      _firstDownMs +
      _midPauseMs +
      _secondUpMs +
      _secondDownMs +
      _endPauseMs;

  bool _hovered = false;
  bool _pressed = false;
  late final AnimationController _wiggleController;
  late Animation<double> _leftAnimation;

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs),
    );
    _leftAnimation = const AlwaysStoppedAnimation(0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_wiggleController.isAnimating) {
      _syncStaticPosition();
    }
  }

  @override
  void didUpdateWidget(covariant OreSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final theme = OreTheme.of(context);
      final highlightDepth = theme.borderWidth;
      final metrics = _metrics(theme.borderWidth);
      final from = _leftAnimation.value;
      final to = widget.value ? metrics.maxLeft : 0.0;
      final direction = widget.value ? 1.0 : -1.0;
      final overshoot = to + highlightDepth * direction;
      _leftAnimation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: from, end: overshoot)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: _firstUpMs.toDouble(),
        ),
        TweenSequenceItem(
          tween: Tween(begin: overshoot, end: to)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: _firstDownMs.toDouble(),
        ),
        TweenSequenceItem(
          tween: ConstantTween(to),
          weight: _midPauseMs.toDouble(),
        ),
        TweenSequenceItem(
          tween: Tween(begin: to, end: overshoot)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: _secondUpMs.toDouble(),
        ),
        TweenSequenceItem(
          tween: Tween(begin: overshoot, end: to)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: _secondDownMs.toDouble(),
        ),
        TweenSequenceItem(
          tween: ConstantTween(to),
          weight: _endPauseMs.toDouble(),
        ),
      ]).animate(_wiggleController);
      _wiggleController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _wiggleController.dispose();
    super.dispose();
  }

  void _syncStaticPosition() {
    final theme = OreTheme.of(context);
    final metrics = _metrics(theme.borderWidth);
    final target = widget.value ? metrics.maxLeft : 0.0;
    _leftAnimation = AlwaysStoppedAnimation(target);
  }

  _SwitchMetrics _metrics(double unit) {
    final trackHeight = unit * OreTokens.switchTrackUnits;
    final trackWidth = trackHeight * OreTokens.switchAspect;
    final knobSize = unit * OreTokens.switchThumbUnits;
    final iconSize = unit * OreTokens.switchIconUnits;
    return _SwitchMetrics(
      trackWidth: trackWidth,
      trackHeight: trackHeight,
      knobSize: knobSize,
      iconSize: iconSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final colors = theme.colors;
    final controlColors = resolveControlColors(context, colors);
    final isOn = widget.value;
    final isHovered = _hovered && _enabled;
    final isPressed = _pressed && _enabled;
    final isInteracting = isHovered || isPressed;
    final depthUnit = theme.borderWidth;
    final metrics = _metrics(depthUnit);
    final highlightDepth = depthUnit;
    final shadowDepth = depthUnit * 2;
    final trackShadowDepth = 0.0;
    final knobTop = metrics.trackHeight - metrics.knobSize;

    final borderColor = _enabled ? colors.border : colors.borderLight;
    final trackColor = _enabled
        ? (isOn ? colors.accent : colors.borderLight)
        : colors.surface;
    final iconBoxWidth = metrics.iconBoxWidth;
    final trackHighlight = isOn
        ? OreHighlight.mutedColored()
        : OreHighlight.muted(colors: colors);
    const trackCornerHighlightFactor = 0.08;
    final knobHighlight = OreHighlight.resolve(
      colors: controlColors,
      colored: false,
      hovered: isHovered,
    );

    final track = SizedBox(
      width: metrics.trackWidth,
      height: metrics.trackHeight,
      child: OreSurface(
        color: trackColor,
        borderColor: borderColor,
        highlightColor: trackHighlight,
        shadowColor: colors.shadow,
        borderWidth: theme.borderWidth,
        depth: shadowDepth,
        highlightDepth: highlightDepth,
        shadowDepth: trackShadowDepth,
        swapHighlightOnPressed: false,
        pressed: false,
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        cornerHighlightFactor: trackCornerHighlightFactor,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (isOn)
              Positioned(
                left: 0,
                top: 0,
                width: iconBoxWidth,
                height: metrics.trackHeight,
                child: Center(
                  child: ClipRect(
                    child: Image.asset(
                      'assets/I.png',
                      package: 'oreui_flutter',
                      width: metrics.iconSize,
                      height: metrics.iconSize,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                      color: const Color(0xFFFFFFFF),
                      colorBlendMode: BlendMode.srcIn,
                    ),
                  ),
                ),
              )
            else
              Positioned(
                right: 0,
                top: 0,
                width: iconBoxWidth,
                height: metrics.trackHeight,
                child: Center(
                  child: ClipRect(
                    child: Image.asset(
                      'assets/O.png',
                      package: 'oreui_flutter',
                      width: metrics.iconSize,
                      height: metrics.iconSize,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                      color: borderColor,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final sliderColor = isInteracting
        ? controlColors.surfaceHover
        : controlColors.surface;

    final slider = OreKnob(
      size: metrics.knobSize,
      color: sliderColor,
      borderColor:
          _enabled ? controlColors.border : controlColors.borderLight,
      highlightColor: knobHighlight,
      shadowColor: controlColors.shadow,
      borderWidth: theme.borderWidth,
      depth: shadowDepth,
      highlightDepth: highlightDepth,
      shadowDepth: shadowDepth,
    );
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
        child: GestureDetector(
        onTap: _enabled ? () => widget.onChanged?.call(!isOn) : null,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: depthUnit),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              track,
              AnimatedBuilder(
                animation: _leftAnimation,
                child: slider,
                builder: (context, child) => Positioned(
                  left: _leftAnimation.value,
                  top: knobTop,
                  child: child!,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
