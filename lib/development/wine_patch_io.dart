import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'development_storage.dart';

const wineArchiveUrl =
    'https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz';
const wineArchiveHash =
    'b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388';
const wineMacOriginal =
    '7687c4095ea6dba1761052ac19d46db3409a36f2bc827b79c6e32bf779df59f4';
// Hash of the patched Mach-O after codesign --remove-signature, with the
// original __LINKEDIT reservation. Signing tools can resize that reservation;
// executable content remains pinned independently of signing metadata.
const wineMacPatchedUnsigned =
    'e3679793f1020d743d6e82b2760c9c90d4de8198493b148a8eda09aa5f1c8035';
// Verified after strict codesign validation on macOS 15.7.4.
const wineMacPatchedUnsignedMacOs15 =
    '4644219c17c222929181849c8d3e33155a46e3160fde7a2deecb41f95b534e14';
const wineGlOriginal =
    '5b6c30a03d988793dc6657b9dc2baa6057908b93e121cdb029165384154bae12';
const wineGlPatched =
    'd216354b5f6e953ca50f763ee59a4b0cdbf92ad49c5241f61f7705550fc51a56';

Future<bool> patchedWineReady(String root) async {
  final mac = File(p.join(root, 'lib/wine/x86_64-unix/winemac.so'));
  final gl = File(p.join(root, 'lib/wine/x86_64-windows/opengl32.dll'));
  if (!await mac.exists() ||
      !await gl.exists() ||
      (await sha256.bind(gl.openRead()).first).toString() != wineGlPatched) {
    return false;
  }
  return await _patchedWineMacReady(mac) &&
      await File(p.join(root, 'bin/wine')).exists();
}

Future<bool> _patchedWineMacReady(File mac) async {
  Directory? temp;
  try {
    // Validate the actual installed file before stripping only a scratch copy.
    final verified = await Process.run('/usr/bin/codesign', [
      '--verify',
      '--strict',
      mac.path,
    ]);
    if (verified.exitCode != 0) return false;
    temp = await Directory.systemTemp.createTemp('mcdev-wine-signature-');
    final unsigned = await mac.copy(p.join(temp.path, 'winemac.so'));
    final removed = await Process.run('/usr/bin/codesign', [
      '--remove-signature',
      unsigned.path,
    ]);
    if (removed.exitCode != 0) return false;
    final bytes = await unsigned.readAsBytes();
    if (bytes.length < 0x9e0) return false;
    final view = ByteData.sublistView(bytes);
    // Wine 11.0_1's __LINKEDIT vmsize is at this pinned offset. macOS 27
    // codesign shrinks its reservation from 64 KiB to 48 KiB. Accept only
    // these known layouts, then normalize this scratch buffer for hashing.
    final linkeditSize = view.getUint64(0x9d8, Endian.little);
    if (linkeditSize != 0x10000 && linkeditSize != 0xc000) return false;
    view.setUint64(0x9d8, 0x10000, Endian.little);
    final hash = sha256.convert(bytes).toString();
    return hash == wineMacPatchedUnsigned ||
        hash == wineMacPatchedUnsignedMacOs15;
  } on ProcessException {
    return false;
  } on FileSystemException {
    return false;
  } finally {
    if (temp != null) await temp.delete(recursive: true);
  }
}

void _replace(Uint8List data, int offset, List<int> before, List<int> after) {
  if (before.length != after.length || offset + before.length > data.length) {
    throw const DevelopmentStorageException('Wine 补丁布局无效。');
  }
  for (var i = 0; i < before.length; i++) {
    if (data[offset + i] != before[i]) {
      throw const DevelopmentStorageException('Wine 版本与补丁不匹配，未修改。');
    }
  }
  data.setAll(offset, after);
}

List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

Future<void> patchWine11(String root) async {
  final mac = File(p.join(root, 'lib/wine/x86_64-unix/winemac.so'));
  final gl = File(p.join(root, 'lib/wine/x86_64-windows/opengl32.dll'));
  final macData = await mac.readAsBytes();
  final glData = await gl.readAsBytes();
  if (sha256.convert(macData).toString() != wineMacOriginal ||
      sha256.convert(glData).toString() != wineGlOriginal) {
    throw const DevelopmentStorageException('Wine 原始文件与受支持版本不匹配。');
  }
  for (final (offset, before, after) in [
    (0x3197d, 'c745d000000000', 'c745d002000000'),
    (0x31987, '0f8438010000', '0f8493010000'),
    (0x31b22, '41bc01000000', '41bc03000000'),
    (0x31b28, 'b001', '31c0'),
    (0x31b6b, '7420', 'eb20'),
  ]) {
    _replace(macData, offset, _hex(before), _hex(after));
  }
  await mac.writeAsBytes(macData, flush: true);
  final signed = await Process.run('/usr/bin/codesign', [
    '--force',
    '--sign',
    '-',
    mac.path,
  ]);
  if (signed.exitCode != 0) {
    throw DevelopmentStorageException(
      'Wine 补丁签名失败：${signed.stderr.toString().trim()}',
    );
  }
  if (!await _patchedWineMacReady(mac)) {
    throw const DevelopmentStorageException('Wine 补丁签名校验失败。');
  }
  final result = buildPatchedOpenGl(glData);
  await gl.writeAsBytes(result, flush: true);
  if (!await patchedWineReady(root)) {
    throw const DevelopmentStorageException('Wine 补丁结果校验失败。');
  }
}

Uint8List buildPatchedOpenGl(Uint8List input) {
  if (sha256.convert(input).toString() != wineGlOriginal) {
    throw const DevelopmentStorageException('OpenGL 版本不匹配。');
  }
  final data = Uint8List(input.length + 0x1000)..setAll(0, input);
  final view = ByteData.sublistView(data);
  final pe = view.getUint32(0x3c, Endian.little);
  final optional = pe + 24;
  final table = optional + view.getUint16(pe + 20, Endian.little);
  final count = view.getUint16(pe + 6, Endian.little);
  final header = table + count * 40;
  if (count != 10 || data.sublist(header, header + 40).any((b) => b != 0)) {
    throw const DevelopmentStorageException('OpenGL 节布局不匹配。');
  }
  data.setAll(header, [0x2e, 0x6d, 0x63, 0x73, 0x66, 0x69, 0x78, 0]);
  for (final (offset, value) in [
    (8, 24),
    (12, 0x10f000),
    (16, 0x1000),
    (20, input.length),
    (36, 0x60000020),
  ]) {
    view.setUint32(header + offset, value, Endian.little);
  }
  view.setUint16(pe + 6, count + 1, Endian.little);
  view.setUint32(optional + 56, 0x110000, Endian.little);
  view.setUint32(optional + 64, 0, Endian.little);
  _replace(data, 0xa8471, _hex('0f84a9000000'), [0x0f, 0x84, 0, 0, 0, 0]);
  view.setInt32(0xa8473, 0x10f000 - (0xa8471 + 6), Endian.little);
  final raw = input.length;
  data.setAll(raw, _hex('488d0d000000004889daff1500000000e900000000'));
  view.setInt32(raw + 3, -(0x10f000 + 7), Endian.little);
  view.setInt32(raw + 12, 0x10b230 - (0x10f000 + 16), Endian.little);
  view.setInt32(raw + 17, 0xa8522 - (0x10f000 + 21), Endian.little);
  if (sha256.convert(data).toString() != wineGlPatched) {
    throw const DevelopmentStorageException('OpenGL 补丁结果不匹配。');
  }
  return data;
}
