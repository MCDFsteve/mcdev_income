import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'development_storage.dart';

const gameWindowChromeHash =
    '9f1e6d9cfae7f4b224b386cb245045e4d16b4b9163c04bfdb6f0d990ee2c7651';
const _asset = 'assets/development/game-window-chrome.dylib';

class GameWindowChrome {
  const GameWindowChrome(this.library, this.application);
  final String library;
  final String application;

  Map<String, String> environment({
    required String loader,
    required String version,
    required String renderer,
    String displayName = '我的世界测试',
    Map<String, String>? inherited,
  }) {
    final previous =
        (inherited ?? Platform.environment)['DYLD_INSERT_LIBRARIES'];
    final frameworks = p.join(application, 'Contents', 'Frameworks');
    return {
      'DYLD_INSERT_LIBRARIES': [
        if (previous != null && previous.isNotEmpty) previous,
        library,
      ].join(':'),
      'MCDEV_CHROME_LOADER': loader,
      'MCDEV_CHROME_FLUTTER': p.join(
        frameworks,
        'FlutterMacOS.framework',
        'FlutterMacOS',
      ),
      'MCDEV_CHROME_APP': p.join(frameworks, 'App.framework'),
      'MCDEV_CHROME_VERSION': version,
      'MCDEV_CHROME_RENDERER': renderer,
      'MCDEV_CHROME_DISPLAY_NAME': displayName,
    };
  }
}

Future<GameWindowChrome> prepareGameWindowChrome(
  String runtimes, {
  AssetBundle? bundle,
  String? application,
}) async {
  final client =
      application ??
      Platform.environment['MCDEV_CHROME_CLIENT_APP'] ??
      p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
  for (final relative in [
    'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS',
    'Contents/Frameworks/App.framework/App',
  ]) {
    if (!await File(p.join(client, relative)).exists()) {
      throw const DevelopmentStorageException(
        '测试游戏顶栏需要完整的 macOS 客户端，请使用构建后的应用启动。',
      );
    }
  }
  final directory = Directory(p.join(runtimes, 'game-window-chrome-v1'));
  final target = File(p.join(directory.path, 'game-window-chrome.dylib'));
  if (target.path.contains(':')) {
    throw const DevelopmentStorageException('游戏窗口组件路径不能包含冒号，请调整开发数据目录。');
  }
  if (await target.exists() &&
      (await sha256.bind(target.openRead()).first).toString() ==
          gameWindowChromeHash) {
    return GameWindowChrome(target.path, client);
  }
  final data = await (bundle ?? rootBundle).load(_asset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() != gameWindowChromeHash) {
    throw const DevelopmentStorageException('游戏窗口组件校验失败，未启动。');
  }
  await directory.create(recursive: true);
  final stage = await directory.createTemp('.chrome-');
  try {
    final file = File(p.join(stage.path, 'game-window-chrome.dylib'));
    await file.writeAsBytes(bytes, flush: true);
    await file.rename(target.path);
  } finally {
    await stage.delete(recursive: true);
  }
  return GameWindowChrome(target.path, client);
}
