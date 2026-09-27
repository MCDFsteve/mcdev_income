import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:crypto/crypto.dart';
import '../core.dart';
import 'common.dart';

class PreparedMedia {
  PreparedMedia({
    required this.path,
    required this.name,
    required this.type,
    required this.length,
    required this.digest,
    this.bytes,
    this.width,
    this.height,
  });
  final String path;
  final String name;
  final String type;
  final int length;
  final String digest;
  final Uint8List? bytes;
  final int? width;
  final int? height;
  Stream<List<int>> openRead() =>
      bytes == null ? File(path).openRead() : Stream.value(bytes!);
  Map<String, dynamic> get description => {
    'path': path,
    'name': name,
    'file_type': type,
    'bytes': length,
    'sha256': digest,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (type == 'image') 'crop': 'center',
  };
}

/// Same default selection as the GUI: largest centered rectangle, exact output.
/// PNG resource packages deliberately bypass this image pipeline.
Future<PreparedMedia> prepareMedia(
  String path, {
  required String type,
  int? width,
  int? height,
  int? maxBytes,
  List<String>? extensions,
}) async {
  final file = File(path).absolute;
  if (!await file.exists()) throw CliFailure('file_not_found', '找不到文件：$path');
  final name = file.uri.pathSegments.last;
  final extension = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  if (extensions != null && !extensions.contains(extension)) {
    throw CliFailure(
      'invalid_file_type',
      '$name 需要 ${extensions.join('/')} 格式',
    );
  }
  final length = await file.length();
  if (length == 0) throw CliFailure('empty_file', '$name 是空文件');
  if (type != 'image') {
    if (maxBytes != null && length > maxBytes) {
      throw CliFailure('file_too_large', '$name 超过 $maxBytes 字节');
    }
    return PreparedMedia(
      path: file.path,
      name: name,
      type: type,
      length: length,
      digest: (await sha256.bind(file.openRead()).first).toString(),
    );
  }
  if ((width == null) != (height == null) ||
      (width != null && (width <= 0 || height! <= 0))) {
    throw CliFailure('invalid_dimensions', '必须同时提供正整数 width 和 height');
  }
  if (width != null && width * height! > 40000000) {
    throw CliFailure('image_too_large', '目标图片超过 4000 万像素');
  }
  // Bound decoded memory before allocating the full raster.
  if (length > 100 * 1024 * 1024) {
    throw CliFailure('image_too_large', '图片文件不能超过 100 MB');
  }
  final bytes = await file.readAsBytes();
  final decoder = image.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 40000000) {
    throw CliFailure('invalid_image', '图片无法解码或超过 4000 万像素：$name');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw CliFailure('invalid_image', '无法解码图片：$name');
  var raster = image.bakeOrientation(decoded);
  if (width != null) {
    final ratio = width / height!;
    final cropWidth = raster.width / raster.height > ratio
        ? (raster.height * ratio).round()
        : raster.width;
    final cropHeight = raster.width / raster.height > ratio
        ? raster.height
        : (raster.width / ratio).round();
    raster = image.copyCrop(
      raster,
      x: (raster.width - cropWidth) ~/ 2,
      y: (raster.height - cropHeight) ~/ 2,
      width: cropWidth.clamp(1, raster.width),
      height: cropHeight.clamp(1, raster.height),
    );
    raster = image.copyResize(
      raster,
      width: width,
      height: height,
      interpolation: image.Interpolation.cubic,
    );
  }
  final output = Uint8List.fromList(image.encodePng(raster));
  if (maxBytes != null && output.length > maxBytes) {
    throw CliFailure('file_too_large', '裁剪后的 $name 超过 $maxBytes 字节');
  }
  return PreparedMedia(
    path: file.path,
    name: '${name.replaceFirst(RegExp(r'\.[^.]+$'), '')}-cropped.png',
    type: type,
    length: output.length,
    digest: sha256.convert(output).toString(),
    bytes: output,
    width: raster.width,
    height: raster.height,
  );
}

Future<UploadedResourceFile> uploadPrepared(
  McDevApi api,
  PreparedMedia media, {
  bool secure = false,
}) => api.uploadResourceFile(
  name: media.name,
  length: media.length,
  stream: media.openRead(),
  fileType: media.type,
  secure: secure,
);
