import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'development_storage.dart';

class DownloadCancelled implements Exception {}

class DownloadControl {
  bool cancelled = false;
  void check() {
    if (cancelled) throw DownloadCancelled();
  }
}

/// Partial archives remain resumable. A completed archive is published only
/// after its transport length and authoritative digest have been checked.
Future<File> downloadManaged(
  http.Client client,
  Uri url,
  File destination, {
  String? expectedSha256,
  String? expectedMd5,
  DownloadControl? control,
  void Function(StorageMigrationProgress)? onProgress,
}) async {
  Future<bool> valid(File file) async {
    if (!await file.exists()) return false;
    if (expectedSha256 != null &&
        (await sha256.bind(file.openRead()).first).toString() !=
            expectedSha256) {
      return false;
    }
    if (expectedMd5 != null &&
        (await md5.bind(file.openRead()).first).toString() != expectedMd5) {
      return false;
    }
    return expectedSha256 != null || expectedMd5 != null;
  }

  if (await valid(destination)) return destination;
  final part = File('${destination.path}.part');
  await destination.parent.create(recursive: true);
  for (var attempt = 0; attempt < 2; attempt++) {
    control?.check();
    var offset = await part.exists() ? await part.length() : 0;
    final request = http.Request('GET', url);
    request.headers['Accept-Encoding'] = 'identity';
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 416 && offset > 0) {
      await response.stream.drain<void>();
      if (await valid(part)) {
        return part.rename(destination.path);
      }
      await part.delete();
      continue;
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.drain<void>();
      throw DevelopmentStorageException(
        '下载失败（HTTP ${response.statusCode}），可以重试。',
      );
    }
    if (response.statusCode == 200) offset = 0;
    var total = response.contentLength == null
        ? 0
        : offset + response.contentLength!;
    if (response.statusCode == 206) {
      final range = RegExp(
        r'^bytes (\d+)-(\d+)/(\d+)$',
      ).firstMatch(response.headers['content-range'] ?? '');
      if (range == null || int.parse(range[1]!) != offset) {
        await response.stream.drain<void>();
        throw const DevelopmentStorageException('下载服务器返回了错误的续传范围。');
      }
      total = int.parse(range[3]!);
    }
    final output = part.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var completed = offset;
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        control?.check();
        output.add(chunk);
        completed += chunk.length;
        if (DateTime.now().difference(last).inMilliseconds >= 150) {
          last = DateTime.now();
          onProgress?.call(
            StorageMigrationProgress('下载中', completed: completed, total: total),
          );
        }
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (total != 0 && completed != total) {
      throw const DevelopmentStorageException('下载尚未完成，重试时会继续下载。');
    }
    control?.check();
    onProgress?.call(const StorageMigrationProgress('校验下载文件'));
    if ((expectedSha256 != null || expectedMd5 != null) && !await valid(part)) {
      await part.delete();
      if (attempt == 0) continue;
      throw const DevelopmentStorageException('下载文件校验失败，未安装。');
    }
    return part.rename(destination.path);
  }
  throw const DevelopmentStorageException('下载文件校验失败，请重试。');
}
