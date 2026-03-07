import 'package:flutter/widgets.dart';

class OreKnob extends StatelessWidget {
  const OreKnob({
    super.key,
    required this.size,
    required this.color,
    required this.borderColor,
    required this.highlightColor,
    required this.shadowColor,
    required this.borderWidth,
    required this.depth,
    required this.highlightDepth,
    required this.shadowDepth,
  });

  final double size;
  final Color color;
  final Color borderColor;
  final Color highlightColor;
  final Color shadowColor;
  final double borderWidth;
  final double depth;
  final double highlightDepth;
  final double shadowDepth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: OreKnobPainter(
          color: color,
          borderColor: borderColor,
          highlightColor: highlightColor,
          shadowColor: shadowColor,
          borderWidth: borderWidth,
          depth: depth,
          highlightDepth: highlightDepth,
          shadowDepth: shadowDepth,
        ),
      ),
    );
  }
}

@immutable
class OreKnobPainter extends CustomPainter {
  const OreKnobPainter({
    required this.color,
    required this.borderColor,
    required this.highlightColor,
    required this.shadowColor,
    required this.borderWidth,
    required this.depth,
    required this.highlightDepth,
    required this.shadowDepth,
    this.swapHighlightOnPressed = false,
    this.pressed = false,
    this.cornerHighlightFactor = 0.2,
  });

  final Color color;
  final Color borderColor;
  final Color highlightColor;
  final Color shadowColor;
  final double borderWidth;
  final double depth;
  final double highlightDepth;
  final double shadowDepth;
  final bool swapHighlightOnPressed;
  final bool pressed;
  final double cornerHighlightFactor;

  @override
  void paint(Canvas canvas, Size size) {
    paintBevel(
      canvas: canvas,
      rect: Offset.zero & size,
      color: color,
      borderColor: borderColor,
      highlightColor: highlightColor,
      shadowColor: shadowColor,
      borderWidth: borderWidth,
      depth: depth,
      highlightDepth: highlightDepth,
      shadowDepth: shadowDepth,
      swapHighlightOnPressed: swapHighlightOnPressed,
      pressed: pressed,
      cornerHighlightFactor: cornerHighlightFactor,
    );
  }

  @override
  bool shouldRepaint(OreKnobPainter oldDelegate) {
    return color != oldDelegate.color ||
        borderColor != oldDelegate.borderColor ||
        highlightColor != oldDelegate.highlightColor ||
        shadowColor != oldDelegate.shadowColor ||
        borderWidth != oldDelegate.borderWidth ||
        depth != oldDelegate.depth ||
        highlightDepth != oldDelegate.highlightDepth ||
        shadowDepth != oldDelegate.shadowDepth ||
        swapHighlightOnPressed != oldDelegate.swapHighlightOnPressed ||
        pressed != oldDelegate.pressed ||
        cornerHighlightFactor != oldDelegate.cornerHighlightFactor;
  }

  static void paintBevel({
    required Canvas canvas,
    required Rect rect,
    required Color color,
    required Color borderColor,
    required Color highlightColor,
    required Color shadowColor,
    required double borderWidth,
    required double depth,
    bool paintFill = true,
    double? highlightDepth,
    double? shadowDepth,
    bool swapHighlightOnPressed = false,
    bool pressed = false,
    double cornerHighlightFactor = 0.2,
  }) {
    if (rect.isEmpty) return;

    final shouldSwap = pressed && swapHighlightOnPressed;
    final highlight = shouldSwap ? shadowColor : highlightColor;
    final shadow = shouldSwap ? highlightColor : shadowColor;
    final cornerHighlight = highlight.a == 0
        ? highlight
        : Color.lerp(
            highlight, const Color(0xFFFFFFFF), cornerHighlightFactor)!;
    final resolvedHighlightDepth =
        (highlightDepth ?? depth).clamp(0.0, 8.0).toDouble();
    final resolvedShadowDepth =
        (shadowDepth ?? depth).clamp(0.0, 8.0).toDouble();
    final weakHighlight = highlight.a == 0
        ? highlight
        : highlight.withValues(
            alpha: (highlight.a * 0.66).clamp(0.0, 1.0),
          );

    if (paintFill) {
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);
    }

    if (borderWidth > 0) {
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill;
      final bw = borderWidth;
      final topRect = Rect.fromLTWH(rect.left, rect.top, rect.width, bw);
      final leftRect = Rect.fromLTWH(rect.left, rect.top, bw, rect.height);
      final bottomRect =
          Rect.fromLTWH(rect.left, rect.bottom - bw, rect.width, bw);
      final rightRect =
          Rect.fromLTWH(rect.right - bw, rect.top, bw, rect.height);
      canvas.drawRect(topRect, borderPaint);
      canvas.drawRect(leftRect, borderPaint);
      canvas.drawRect(bottomRect, borderPaint);
      canvas.drawRect(rightRect, borderPaint);
    }

    if (resolvedHighlightDepth > 0) {
      final bw = borderWidth;
      final innerWidth = rect.width - bw * 2;
      final innerHeight = rect.height - bw * 2;
      final safeInnerWidth = innerWidth < 0 ? 0.0 : innerWidth;
      final safeInnerHeight = innerHeight < 0 ? 0.0 : innerHeight;
      final availableHeight =
          safeInnerHeight - resolvedShadowDepth - resolvedHighlightDepth * 2;
      final sideHeight = availableHeight < 0 ? 0.0 : availableHeight;
      final sideTop = rect.top + bw + resolvedHighlightDepth;

      final highlightPaint = Paint()
        ..color = highlight
        ..style = PaintingStyle.fill;
      final weakHighlightPaint = Paint()
        ..color = weakHighlight
        ..style = PaintingStyle.fill;
      final cornerPaint = Paint()
        ..color = cornerHighlight
        ..style = PaintingStyle.fill;

      final topRect = Rect.fromLTWH(
        rect.left + bw,
        rect.top + bw,
        safeInnerWidth,
        resolvedHighlightDepth,
      );
      final leftRect = Rect.fromLTWH(
        rect.left + bw,
        sideTop,
        resolvedHighlightDepth,
        sideHeight,
      );
      final rightRect = Rect.fromLTWH(
        rect.right - bw - resolvedHighlightDepth,
        sideTop,
        resolvedHighlightDepth,
        sideHeight,
      );
      final bottomRect = Rect.fromLTWH(
        rect.left + bw,
        rect.bottom - bw - resolvedShadowDepth - resolvedHighlightDepth,
        safeInnerWidth,
        resolvedHighlightDepth,
      );
      final topRightCorner = Rect.fromLTWH(
        rect.right - bw - resolvedHighlightDepth,
        rect.top + bw,
        resolvedHighlightDepth,
        resolvedHighlightDepth,
      );
      final bottomLeftCorner = Rect.fromLTWH(
        rect.left + bw,
        rect.bottom - bw - resolvedShadowDepth - resolvedHighlightDepth,
        resolvedHighlightDepth,
        resolvedHighlightDepth,
      );

      _drawRect(canvas, topRect, highlightPaint);
      _drawRect(canvas, leftRect, highlightPaint);
      _drawRect(canvas, rightRect, weakHighlightPaint);
      _drawRect(canvas, bottomRect, weakHighlightPaint);
      _drawRect(canvas, topRightCorner, cornerPaint);
      _drawRect(canvas, bottomLeftCorner, cornerPaint);
    }

    if (resolvedShadowDepth > 0) {
      final bw = borderWidth;
      final shadowPaint = Paint()
        ..color = shadow
        ..style = PaintingStyle.fill;
      final shadowRect = Rect.fromLTWH(
        rect.left + bw,
        rect.bottom - bw - resolvedShadowDepth,
        rect.width - bw * 2,
        resolvedShadowDepth,
      );
      _drawRect(canvas, shadowRect, shadowPaint);
    }
  }

  static void _drawRect(Canvas canvas, Rect rect, Paint paint) {
    if (rect.width <= 0 || rect.height <= 0) return;
    canvas.drawRect(rect, paint);
  }
}
