import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'development_storage.dart';
import 'download_io.dart';
import 'render_dragon.dart';
import 'wine_patch_io.dart';

Future<bool> _matches(File file, String digest) async =>
    await file.exists() &&
    (await sha256.bind(file.openRead()).first).toString() == digest;

Future<void> validateRenderDragonGame(String version, File executable) async {
  if (!supportsRenderDragonPatch(version) ||
      !await _matches(executable, renderDragonGameHash)) {
    throw const DevelopmentStorageException(
      '渲染龙适配与游戏文件不匹配，请重新下载 3.10.0.420447 Haldra x64，或切回 OpenGL。',
    );
  }
}

Future<File> _asset(
  String name,
  String hash,
  Directory target,
  AssetBundle source,
) async {
  final file = File(p.join(target.path, name));
  if (await _matches(file, hash)) return file;
  final data = await source.load('assets/development/$name');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() != hash) {
    throw const DevelopmentStorageException('渲染龙适配资源校验失败，未应用。');
  }
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(file.path);
  return file;
}

Future<Directory> prepareRendererPatch(
  String runtimes, {
  AssetBundle? bundle,
}) async {
  final directory = Directory(p.join(runtimes, 'renderer-patch-v1'));
  final source = bundle ?? rootBundle;
  await _asset('renderer-patch.dll', rendererPatchHash, directory, source);
  await _asset('renderer-inject.exe', rendererInjectorHash, directory, source);
  return directory;
}

Future<bool> renderDragonRuntimeReady(String runtime) async {
  for (final entry in {
    ...dxmtFiles.map((name, hash) => MapEntry('lib/wine/$name', hash)),
    'lib/wine/x86_64-unix/winemac.so': wineMetalBridgeHash,
    'lib/wine/x86_64-windows/opengl32.dll': wineGlPatched,
  }.entries) {
    if (!await _matches(File(p.join(runtime, entry.key)), entry.value)) {
      return false;
    }
  }
  return File(p.join(runtime, 'bin/wine')).exists();
}

/// Install a separate, hash-pinned runtime. The verified OpenGL runtime remains
/// the source of its loader/dependencies; no original file is replaced.
Future<String> prepareRenderDragonRuntime({
  required String baseRuntime,
  required String runtimes,
  required String downloads,
  required http.Client client,
  DownloadControl? control,
  void Function(StorageMigrationProgress)? onProgress,
  AssetBundle? bundle,
}) async {
  final system = await Process.run('/usr/bin/sw_vers', ['-productVersion']);
  final major = int.tryParse(system.stdout.toString().trim().split('.').first);
  if (system.exitCode != 0 || major == null || major < 14) {
    throw const DevelopmentStorageException('渲染龙 Metal 适配需要 macOS 14 或以上。');
  }
  final target = Directory(p.join(runtimes, 'wine-11.0_1-dxmt-0.80-v1'));
  if (await renderDragonRuntimeReady(target.path)) return target.path;
  if (!await patchedWineReady(baseRuntime)) {
    throw const DevelopmentStorageException('请先安装 Wine。');
  }
  if (await target.exists()) {
    throw const DevelopmentStorageException('渲染龙运行环境校验失败，请先备份并移走该运行时目录后重试。');
  }
  final archive = File(p.join(downloads, 'dxmt-v0.80-builtin.tar.gz'));
  var downloaded = false;
  onProgress?.call(const StorageMigrationProgress('下载渲染龙 Metal 组件（约 18 MB）'));
  for (final url in [
    dxmtArchiveUrl,
    'https://gh-proxy.com/$dxmtArchiveUrl',
    'https://ghfast.top/$dxmtArchiveUrl',
  ]) {
    try {
      await downloadManaged(
        client,
        Uri.parse(url),
        archive,
        expectedSha256: dxmtArchiveHash,
        control: control,
        onProgress: onProgress,
      );
      downloaded = true;
      break;
    } on DownloadCancelled {
      rethrow;
    } catch (_) {
      control?.check();
    }
  }
  if (!downloaded) {
    throw const DevelopmentStorageException('Metal 组件下载失败，可重试或切回 OpenGL。');
  }
  final stage = await Directory(runtimes).createTemp('.dragon-install-');
  try {
    control?.check();
    onProgress?.call(const StorageMigrationProgress('准备独立渲染龙运行环境'));
    final payload = p.join(stage.path, 'wine');
    // APFS clones share unchanged blocks. Other volumes fall back to a copy.
    var result = await Process.run('/bin/cp', ['-cR', baseRuntime, payload]);
    if (result.exitCode != 0) {
      if (await Directory(payload).exists()) {
        await Directory(payload).delete(recursive: true);
      }
      result = await Process.run('/usr/bin/ditto', [
        '--noextattr',
        '--norsrc',
        baseRuntime,
        payload,
      ]);
    }
    if (result.exitCode != 0) {
      throw const DevelopmentStorageException('复制 Wine 运行环境失败。');
    }
    control?.check();
    final extracted = await Process.run('/usr/bin/tar', [
      '-xzf',
      archive.path,
      '-C',
      stage.path,
      for (final name in dxmtFiles.keys) 'v0.80/$name',
    ]);
    if (extracted.exitCode != 0) {
      throw const DevelopmentStorageException('Metal 组件解压失败。');
    }
    for (final entry in dxmtFiles.entries) {
      control?.check();
      final file = File(p.join(stage.path, 'v0.80', entry.key));
      if (!await _matches(file, entry.value)) {
        throw const DevelopmentStorageException('Metal 组件校验失败，未安装。');
      }
      await file.copy(p.join(payload, 'lib', 'wine', entry.key));
    }
    final bridge = await _asset(
      'winemac-dxmt.so',
      wineMetalBridgeHash,
      stage,
      bundle ?? rootBundle,
    );
    await bridge.copy(p.join(payload, 'lib/wine/x86_64-unix/winemac.so'));
    if (!await renderDragonRuntimeReady(payload)) {
      throw const DevelopmentStorageException('渲染龙运行环境校验失败。');
    }
    control?.check();
    await Directory(payload).rename(target.path);
    return target.path;
  } finally {
    if (await stage.exists()) await stage.delete(recursive: true);
  }
}

Future<void> prepareWineMetalPrefix(String runtime, String prefix) async {
  final source = File(p.join(runtime, 'lib/wine/x86_64-windows/winemetal.dll'));
  final target = File(p.join(prefix, 'drive_c/windows/system32/winemetal.dll'));
  if (!await _matches(source, dxmtFiles['x86_64-windows/winemetal.dll']!)) {
    throw const DevelopmentStorageException('Wine Metal 组件不可用。');
  }
  if (await _matches(target, dxmtFiles['x86_64-windows/winemetal.dll']!)) {
    return;
  }
  await target.parent.create(recursive: true);
  final temp = File('${target.path}.mcdev-tmp');
  await source.copy(temp.path);
  await temp.rename(target.path);
}
