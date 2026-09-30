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
const wineMacPatched =
    'd210208bf0f38bc828f0379b9a2bf36bf0015bf1655f654df6766b4eddd3e009';
const wineGlOriginal =
    '5b6c30a03d988793dc6657b9dc2baa6057908b93e121cdb029165384154bae12';
const wineGlPatched =
    'd216354b5f6e953ca50f763ee59a4b0cdbf92ad49c5241f61f7705550fc51a56';

Future<bool> patchedWineReady(String root) async {
  for (final entry in {
    'lib/wine/x86_64-unix/winemac.so': wineMacPatched,
    'lib/wine/x86_64-windows/opengl32.dll': wineGlPatched,
  }.entries) {
    final file = File(p.join(root, entry.key));
    if (!await file.exists() ||
        (await sha256.bind(file.openRead()).first).toString() != entry.value) {
      return false;
    }
  }
  return File(p.join(root, 'bin/wine')).exists();
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
  if (signed.exitCode != 0 ||
      (await sha256.bind(mac.openRead()).first).toString() != wineMacPatched) {
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
