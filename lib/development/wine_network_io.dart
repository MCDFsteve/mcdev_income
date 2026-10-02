import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'development_storage.dart';

const wineNetworkLibraryHash =
    'aafc9cf3b40542072fd76e7be57c0dca86fb1734cd042298eb128ac66912f457';
const _asset = 'assets/development/ipv6-discovery.dylib';

/// Scope only Wine's unzoned IPv6 LAN discovery packets. The native helper
/// preserves configured interfaces and passes other traffic through unchanged.
Future<File> prepareWineNetworkLibrary(
  String runtimes, {
  AssetBundle? bundle,
}) async {
  final directory = Directory(p.join(runtimes, 'network-discovery-v1'));
  final target = File(p.join(directory.path, 'ipv6-discovery.dylib'));
  if (target.path.contains(':')) {
    throw const DevelopmentStorageException('游戏网络组件路径不能包含冒号，请调整开发数据目录。');
  }
  if (await target.exists() &&
      (await sha256.bind(target.openRead()).first).toString() ==
          wineNetworkLibraryHash) {
    return target;
  }
  final data = await (bundle ?? rootBundle).load(_asset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() != wineNetworkLibraryHash) {
    throw const DevelopmentStorageException('游戏网络组件校验失败，未启动。');
  }
  await directory.create(recursive: true);
  final staging = await directory.createTemp('.network-discovery-');
  try {
    final temporary = File(p.join(staging.path, 'ipv6-discovery.dylib'));
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  } finally {
    await staging.delete(recursive: true);
  }
  return target;
}

Map<String, String> wineNetworkEnvironment(
  String library, {
  Map<String, String>? inherited,
}) {
  final previous = (inherited ?? Platform.environment)['DYLD_INSERT_LIBRARIES'];
  return {
    'DYLD_INSERT_LIBRARIES': [
      if (previous != null && previous.isNotEmpty) previous,
      library,
    ].join(':'),
  };
}
