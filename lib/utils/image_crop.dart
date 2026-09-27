import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A crop in oriented source pixels, always contained by the source image.
class ImageCropSelection {
  ImageCropSelection(this.sourceSize, {this.aspectRatio}) {
    reset();
  }

  final ui.Size sourceSize;
  final double? aspectRatio;
  int quarterTurns = 0;
  late ui.Rect rect;

  ui.Size get size => quarterTurns.isOdd
      ? ui.Size(sourceSize.height, sourceSize.width)
      : sourceSize;

  void reset() {
    final ratio = aspectRatio ?? size.aspectRatio;
    final width = math.min(size.width, size.height * ratio);
    rect = ui.Rect.fromCenter(
      center: size.center(ui.Offset.zero),
      width: width,
      height: width / ratio,
    );
  }

  void rotate() {
    quarterTurns = (quarterTurns + 1) % 4;
    reset();
  }

  void move(ui.Rect from, ui.Offset delta) {
    rect = from.shift(
      ui.Offset(
        delta.dx.clamp(-from.left, size.width - from.right),
        delta.dy.clamp(-from.top, size.height - from.bottom),
      ),
    );
  }

  void zoom(ui.Rect from, double factor) {
    final maximum = math.min(
      size.width / from.width,
      size.height / from.height,
    );
    final minimum = math.min(
      maximum,
      math.max(1 / from.width, 1 / from.height),
    );
    final scale = factor.clamp(minimum, maximum);
    final width = math.min(size.width, from.width * scale);
    final height = math.min(size.height, from.height * scale);
    final left = (from.center.dx - width / 2).clamp(0.0, size.width - width);
    final top = (from.center.dy - height / 2).clamp(0.0, size.height - height);
    rect = ui.Rect.fromLTWH(left, top, width, height);
  }

  /// Corners are ordered top-left, top-right, bottom-right, bottom-left.
  void resize(ui.Rect from, int corner, ui.Offset delta) {
    final left = corner == 0 || corner == 3;
    final top = corner < 2;
    final anchor = ui.Offset(
      left ? from.right : from.left,
      top ? from.bottom : from.top,
    );
    final maxWidth = left ? anchor.dx : size.width - anchor.dx;
    final maxHeight = top ? anchor.dy : size.height - anchor.dy;
    var width = from.width + (left ? -delta.dx : delta.dx);
    var height = from.height + (top ? -delta.dy : delta.dy);
    final ratio = aspectRatio;
    if (ratio != null) {
      // Combine horizontal and vertical movement while keeping the ratio.
      width = (width + height * ratio) / 2;
      final maxAllowed = math.min(maxWidth, maxHeight * ratio);
      width = width.clamp(
        math.min(maxAllowed, math.max(1.0, ratio)),
        maxAllowed,
      );
      height = width / ratio;
    } else {
      width = width.clamp(math.min(1.0, maxWidth), maxWidth);
      height = height.clamp(math.min(1.0, maxHeight), maxHeight);
    }
    rect = ui.Rect.fromLTWH(
      left ? anchor.dx - width : anchor.dx,
      top ? anchor.dy - height : anchor.dy,
      width,
      height,
    );
  }
}

void drawOrientedImage(ui.Canvas canvas, ui.Image image, int quarterTurns) {
  canvas.save();
  switch (quarterTurns % 4) {
    case 1:
      canvas.translate(image.height.toDouble(), 0);
      canvas.rotate(math.pi / 2);
    case 2:
      canvas.translate(image.width.toDouble(), image.height.toDouble());
      canvas.rotate(math.pi);
    case 3:
      canvas.translate(0, image.width.toDouble());
      canvas.rotate(-math.pi / 2);
  }
  canvas.drawImage(
    image,
    ui.Offset.zero,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  canvas.restore();
}

/// Encode the actual selected pixels, resizing only when a channel requires it.
Future<Uint8List> encodeImageCrop(
  ui.Image image,
  ImageCropSelection selection, {
  int? width,
  int? height,
}) async {
  final crop = selection.rect;
  final outputWidth = width ?? math.max(1, crop.width.round());
  final outputHeight = height ?? math.max(1, crop.height.round());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.clipRect(
    ui.Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
  );
  canvas.scale(outputWidth / crop.width, outputHeight / crop.height);
  canvas.translate(-crop.left, -crop.top);
  drawOrientedImage(canvas, image, selection.quarterTurns);
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(outputWidth, outputHeight);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('无法生成裁剪图片，请重试');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    output?.dispose();
    picture.dispose();
  }
}
