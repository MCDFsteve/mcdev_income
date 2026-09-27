import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:mcdev_income/ui/ore_material.dart';
import 'package:mcdev_income/utils/image_crop.dart';

Future<Uint8List?> showResourceImageCropDialog(
  BuildContext context, {
  required Uint8List bytes,
  required String label,
  int? width,
  int? height,
  int? maxBytes,
}) => showOreDialog<Uint8List>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ResourceImageCropDialog(
    bytes: bytes,
    label: label,
    width: width,
    height: height,
    maxBytes: maxBytes,
  ),
);

class ResourceImageCropDialog extends StatefulWidget {
  const ResourceImageCropDialog({
    super.key,
    required this.bytes,
    required this.label,
    this.width,
    this.height,
    this.maxBytes,
  }) : assert(
         (width == null && height == null) ||
             (width != null && height != null && width > 0 && height > 0),
       );

  final Uint8List bytes;
  final String label;
  final int? width, height, maxBytes;

  @override
  State<ResourceImageCropDialog> createState() =>
      _ResourceImageCropDialogState();
}

class _ResourceImageCropDialogState extends State<ResourceImageCropDialog> {
  ui.Image? _image;
  ImageCropSelection? _selection;
  String? _error;
  bool _encoding = false;
  Rect? _dragStartRect;
  Offset? _dragStart;
  int? _corner;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
        _selection = ImageCropSelection(
          Size(frame.image.width.toDouble(), frame.image.height.toDouble()),
          aspectRatio: widget.width == null
              ? null
              : widget.width! / widget.height!,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取这张图片，请取消后重新选择 PNG 或 JPG 图片。');
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_encoding || _image == null) return;
    setState(() {
      _encoding = true;
      _error = null;
    });
    // Keep a separate handle alive if the route is removed while encoding.
    final image = _image!.clone();
    var completed = false;
    try {
      final bytes = await encodeImageCrop(
        image,
        _selection!,
        width: widget.width,
        height: widget.height,
      );
      if (widget.maxBytes != null && bytes.length > widget.maxBytes!) {
        throw StateError(
          '裁剪后的图片超过 ${widget.maxBytes! ~/ (1024 * 1024)} MB，请缩小选区或换一张图片',
        );
      }
      if (mounted) {
        completed = true;
        Navigator.of(context).pop(bytes);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      image.dispose();
      // Keep actions disabled through the closing animation to prevent a
      // second confirmation from popping the underlying editor route.
      if (mounted && !completed) setState(() => _encoding = false);
    }
  }

  void _change(VoidCallback action) {
    if (_encoding) return;
    setState(() {
      action();
      _error = null;
    });
  }

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      final selection = _selection!;
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      final scale = math.min(
        (viewport.width - 32) / selection.size.width,
        (viewport.height - 32) / selection.size.height,
      );
      if (scale <= 0) return const SizedBox.shrink();
      final origin = Offset(
        (viewport.width - selection.size.width * scale) / 2,
        (viewport.height - selection.size.height * scale) / 2,
      );
      final rect = selection.rect;
      final corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ];
      return Semantics(
        label: '图片裁剪区域。拖动选区移动，拖动四角调整大小，也可使用下方按钮缩放。',
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && !_encoding) {
              GestureBinding.instance.pointerSignalResolver.register(event, (
                _,
              ) {
                _change(
                  () => selection.zoom(
                    selection.rect,
                    math.exp(event.scrollDelta.dy.clamp(-200, 200) / 500),
                  ),
                );
              });
            }
          },
          child: MouseRegion(
            cursor: _encoding
                ? SystemMouseCursors.wait
                : SystemMouseCursors.move,
            child: GestureDetector(
              key: const ValueKey('image-crop-canvas'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onScaleStart: _encoding
                  ? null
                  : (details) {
                      _dragStart = details.localFocalPoint;
                      _dragStartRect = selection.rect;
                      _corner = null;
                      var distance = 28.0;
                      for (var i = 0; i < corners.length; i++) {
                        final next =
                            (corners[i] * scale +
                                    origin -
                                    details.localFocalPoint)
                                .distance;
                        if (next < distance) {
                          _corner = i;
                          distance = next;
                        }
                      }
                    },
              onScaleUpdate: _encoding
                  ? null
                  : (details) {
                      if (_dragStartRect == null) return;
                      final delta =
                          (details.localFocalPoint - _dragStart!) / scale;
                      _change(() {
                        if (details.pointerCount > 1) {
                          selection.zoom(_dragStartRect!, 1 / details.scale);
                          selection.move(selection.rect, delta);
                        } else if (_corner != null) {
                          selection.resize(_dragStartRect!, _corner!, delta);
                        } else {
                          selection.move(_dragStartRect!, delta);
                        }
                      });
                    },
              child: CustomPaint(
                painter: _CropPainter(
                  image: _image!,
                  rect: rect,
                  turns: selection.quarterTurns,
                  scale: scale,
                  origin: origin,
                  imageSize: selection.size,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final colors = OreTheme.of(context).colors;
    final rect = selection?.rect;
    final output = rect == null
        ? ''
        : '${widget.width ?? math.max(1, rect.width.round())} × ${widget.height ?? math.max(1, rect.height.round())}';
    return PopScope(
      canPop: !_encoding,
      child: OreDialog(
        surface: false,
        maxWidth: 1040,
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 800),
          child: OreCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '裁剪${widget.label}',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selection == null
                        ? (_error == null ? '正在读取图片…' : '请选择其他图片重试')
                        : '${widget.width == null ? '自由裁剪' : '固定比例'} · 输出 $output 像素'
                              '${widget.width != null && rect!.width < widget.width! ? '（选区将放大）' : ''}',
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xff202124),
                    child: selection == null
                        ? Center(
                            child: _error == null
                                ? const OreLoadingIndicator()
                                : const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                          )
                        : _canvas(),
                  ),
                ),
                const SizedBox(height: 10),
                // Scroll the controls in very short windows or with enlarged text.
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .42,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const Text('拖动选区移动，拖动四角裁剪；滚轮或双指缩放。'),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              OreButton(
                                size: OreButtonSize.sm,
                                onPressed: selection == null || _encoding
                                    ? null
                                    : () => _change(
                                        () =>
                                            selection.zoom(selection.rect, .8),
                                      ),
                                child: const Text('放大'),
                              ),
                              OreButton(
                                size: OreButtonSize.sm,
                                onPressed: selection == null || _encoding
                                    ? null
                                    : () => _change(
                                        () => selection.zoom(
                                          selection.rect,
                                          1.25,
                                        ),
                                      ),
                                child: const Text('缩小'),
                              ),
                              OreButton(
                                size: OreButtonSize.sm,
                                onPressed: selection == null || _encoding
                                    ? null
                                    : () => _change(selection.rotate),
                                child: const Text('旋转'),
                              ),
                              OreButton(
                                size: OreButtonSize.sm,
                                onPressed: selection == null || _encoding
                                    ? null
                                    : () => _change(() {
                                        selection.quarterTurns = 0;
                                        selection.reset();
                                      }),
                                child: const Text('重置'),
                              ),
                              OreButton(
                                size: OreButtonSize.sm,
                                onPressed: _encoding
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                              OreButton(
                                size: OreButtonSize.sm,
                                variant: OreButtonVariant.primary,
                                isLoading: _encoding,
                                onPressed: selection == null || _encoding
                                    ? null
                                    : _confirm,
                                child: Text(_encoding ? '正在处理…' : '裁剪并上传'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.image,
    required this.rect,
    required this.turns,
    required this.scale,
    required this.origin,
    required this.imageSize,
  });
  final ui.Image image;
  final Rect rect;
  final int turns;
  final double scale;
  final Offset origin;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = origin & (imageSize * scale);
    canvas.save();
    canvas.clipRect(bounds);
    // Checkerboard makes existing transparency visible without adding pixels.
    for (var y = bounds.top; y < bounds.bottom; y += 16) {
      for (var x = bounds.left; x < bounds.right; x += 16) {
        final odd =
            (((x - bounds.left) / 16).round() + ((y - bounds.top) / 16).round())
                .isOdd;
        canvas.drawRect(
          Rect.fromLTWH(x, y, 16, 16),
          Paint()..color = Color(odd ? 0xff999999 : 0xffcccccc),
        );
      }
    }
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    drawOrientedImage(canvas, image, turns);
    canvas.restore();
    final crop = Rect.fromLTWH(
      origin.dx + rect.left * scale,
      origin.dy + rect.top * scale,
      rect.width * scale,
      rect.height * scale,
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addRect(crop),
      Paint()..color = const Color(0x99000000),
    );
    final line = Paint()
      ..color = const Color(0x99ffffff)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(crop.left + crop.width * i / 3, crop.top),
        Offset(crop.left + crop.width * i / 3, crop.bottom),
        line,
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * i / 3),
        Offset(crop.right, crop.top + crop.height * i / 3),
        line,
      );
    }
    canvas.drawRect(
      crop,
      line
        ..color = Colors.white
        ..strokeWidth = 2,
    );
    for (final point in [
      crop.topLeft,
      crop.topRight,
      crop.bottomRight,
      crop.bottomLeft,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 12, height: 12),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 12, height: 12),
        Paint()
          ..color = const Color(0xff202124)
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.rect != rect ||
      oldDelegate.turns != turns ||
      oldDelegate.scale != scale ||
      oldDelegate.origin != origin;
}
