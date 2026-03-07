import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class OrePixelIcon extends StatefulWidget {
  const OrePixelIcon({
    super.key,
    required this.icon,
    this.size,
    this.color,
    this.pixelSize = 1,
    this.supersample = 3,
    this.alphaThreshold = 0.5,
    this.semanticLabel,
    this.textDirection,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final double pixelSize;
  final int supersample;
  final double alphaThreshold;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  State<OrePixelIcon> createState() => _OrePixelIconState();
}

class _OrePixelIconState extends State<OrePixelIcon> {
  Uint8List? _pngBytes;
  bool _captureScheduled = false;
  int _captureToken = 0;

  @override
  void initState() {
    super.initState();
    _scheduleCapture();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleCapture();
  }

  @override
  void didUpdateWidget(covariant OrePixelIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon ||
        oldWidget.size != widget.size ||
        oldWidget.color != widget.color ||
        oldWidget.pixelSize != widget.pixelSize ||
        oldWidget.supersample != widget.supersample ||
        oldWidget.alphaThreshold != widget.alphaThreshold ||
        oldWidget.semanticLabel != widget.semanticLabel ||
        oldWidget.textDirection != widget.textDirection) {
      _scheduleCapture();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _scheduleCapture() {
    if (_captureScheduled) return;
    _captureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    _captureScheduled = false;
    if (!mounted) return;
    final theme = IconTheme.of(context);
    final size = widget.size ?? theme.size ?? 16;
    final pixelSize = widget.pixelSize <= 0 ? 1.0 : widget.pixelSize;
    final gridSize = math.max(1, (size / pixelSize).round());
    final supersample = widget.supersample <= 1 ? 1 : widget.supersample;
    final rasterSize = gridSize * supersample;
    final iconColor = widget.color ?? theme.color ?? Colors.white;
    final textDirection =
        widget.textDirection ?? Directionality.of(context);
    final token = ++_captureToken;

    final image = await _rasterizeIcon(
      icon: widget.icon,
      color: iconColor,
      size: rasterSize,
      textDirection: textDirection,
    );
    if (token != _captureToken) {
      image.dispose();
      return;
    }

    final processed = await _binarize(image, gridSize, supersample);
    image.dispose();
    if (processed == null) return;
    if (!mounted) {
      return;
    }
    final texture = await _renderTexture(
      processed,
      size.toDouble(),
      iconColor.withAlpha(255),
    );
    final bytes = await _encodePng(texture);
    texture.dispose();
    if (bytes == null) return;
    if (!mounted || token != _captureToken) {
      return;
    }
    setState(() {
      _pngBytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = widget.size ?? theme.size ?? 16;
    final image = _pngBytes == null
        ? SizedBox(width: size, height: size)
        : _PixelSnap(
            child: Image.memory(
              _pngBytes!,
              width: size,
              height: size,
              fit: BoxFit.none,
              alignment: Alignment.center,
              filterQuality: FilterQuality.none,
              isAntiAlias: false,
              gaplessPlayback: true,
            ),
          );

    return Align(
      alignment: Alignment.center,
      widthFactor: 1,
      heightFactor: 1,
      child: image,
    );
  }

  Future<ui.Image> _rasterizeIcon({
    required IconData icon,
    required Color color,
    required int size,
    required TextDirection textDirection,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    );

    final textSpan = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size.toDouble(),
        color: color,
      ),
    );
    final painter = TextPainter(
      text: textSpan,
      textDirection: textDirection,
    );
    painter.layout();

    final dx = (size - painter.width) / 2;
    final dy = (size - painter.height) / 2;
    if (icon.matchTextDirection &&
        textDirection == TextDirection.rtl) {
      final half = size / 2;
      canvas.translate(half, 0);
      canvas.scale(-1, 1);
      canvas.translate(-half, 0);
    }
    painter.paint(canvas, Offset(dx, dy));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    return image;
  }

  Future<_PixelMask?> _binarize(
    ui.Image source,
    int targetSize,
    int supersample,
  ) async {
    final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    final threshold = (widget.alphaThreshold.clamp(0, 1) * 255).round();
    final width = source.width;
    final height = source.height;
    final target = math.max(1, targetSize);
    final step = supersample <= 1 ? 1 : supersample;
    final mask = Uint8List(target * target);

    var outIndex = 0;
    for (var y = 0; y < target; y++) {
      final yStart = y * step;
      final yEnd = math.min(height, yStart + step);
      for (var x = 0; x < target; x++) {
        final xStart = x * step;
        final xEnd = math.min(width, xStart + step);
        var sum = 0;
        var count = 0;
        for (var sy = yStart; sy < yEnd; sy++) {
          final row = sy * width;
          for (var sx = xStart; sx < xEnd; sx++) {
            final index = (row + sx) * 4;
            sum += bytes[index + 3];
            count++;
          }
        }
        final avg = count == 0 ? 0 : (sum / count).round();
        if (avg >= threshold) {
          mask[outIndex] = 1;
        }
        outIndex++;
      }
    }

    return _PixelMask(width: target, height: target, data: mask);
  }

  Future<ui.Image> _renderTexture(
    _PixelMask mask,
    double size,
    Color color,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size, size),
    );
    final scaleX = size / mask.width;
    final scaleY = size / mask.height;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;

    var index = 0;
    for (var y = 0; y < mask.height; y++) {
      final dy = y * scaleY;
      for (var x = 0; x < mask.width; x++) {
        if (mask.data[index] == 1) {
          final dx = x * scaleX;
          canvas.drawRect(
            Rect.fromLTWH(dx, dy, scaleX, scaleY),
            paint,
          );
        }
        index++;
      }
    }

    final picture = recorder.endRecording();
    final image =
        await picture.toImage(size.round(), size.round());
    picture.dispose();
    return image;
  }

  Future<Uint8List?> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return data.buffer.asUint8List();
  }
}

class _PixelMask {
  const _PixelMask({
    required this.width,
    required this.height,
    required this.data,
  });

  final int width;
  final int height;
  final Uint8List data;
}

class _PixelSnap extends SingleChildRenderObjectWidget {
  const _PixelSnap({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPixelSnap(View.of(context).devicePixelRatio);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPixelSnap renderObject,
  ) {
    renderObject.devicePixelRatio = View.of(context).devicePixelRatio;
  }
}

class _RenderPixelSnap extends RenderProxyBox {
  _RenderPixelSnap(this._devicePixelRatio);

  double _devicePixelRatio;

  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final dpr = _devicePixelRatio <= 0 ? 1.0 : _devicePixelRatio;
    final snapped = Offset(
      (offset.dx * dpr).roundToDouble() / dpr,
      (offset.dy * dpr).roundToDouble() / dpr,
    );
    context.paintChild(child!, snapped);
  }
}
