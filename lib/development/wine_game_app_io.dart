import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'development_storage.dart';

// The real Wine 11 x64 loader from the verified 11.0_1 download. bin/wine
// re-executes this outside any app bundle, losing the game's macOS identity.
const wineGameLoaderSourceHash =
    '61ae8ab79e35f4982d5f6be14a3a26dcc5383578a298d9f767811086b40020d3';
const wineGameIconHash =
    'f78d1745f5492194199a40de3469d60a48aff134653cc885ba2c038b3c0f1704';
const _iconFile = 'MinecraftBedrock.icns';

class WineGameApplication {
  const WineGameApplication(this.path);
  final String path;
  String get loader => p.join(path, 'Contents', 'MacOS', 'wine');
  Map<String, String> get environment => {
    'WINELOADER': loader,
    // This is already the real loader. Its normal bootstrap re-exec would
    // return to the unbundled runtime. Wine clears this flag during startup.
    'WINELOADERNOEXEC': '1',
  };
}

String _info(String identifier) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>我的世界测试</string>
<key>CFBundleDisplayName</key><string>我的世界测试</string>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleExecutable</key><string>wine</string>
<key>CFBundleIconFile</key><string>$_iconFile</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>NSPrincipalClass</key><string>WineApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><false/>
<key>LSMinimumSystemVersion</key><string>10.15</string>
<key>MCDevWineGameApplication</key><true/>
<key>MCDevLoaderSourceSHA256</key><string>$wineGameLoaderSourceHash</string>
</dict></plist>
''';

const _ntdllLink = '../../../lib/wine/x86_64-unix/ntdll.so';

Future<bool> _ready(String app, String identifier) async {
  try {
    if (await File(p.join(app, 'Contents', 'Info.plist')).readAsString() !=
            _info(identifier) ||
        await Link(p.join(app, 'Contents', 'MacOS', 'ntdll.so')).target() !=
            _ntdllLink ||
        !await File(p.join(app, 'Contents', 'MacOS', 'ntdll.so')).exists() ||
        !await File(p.join(app, 'Contents', 'MacOS', 'wine')).exists() ||
        !await File(p.join(app, 'Contents', 'Resources', _iconFile)).exists() ||
        (await sha256
                    .bind(
                      File(
                        p.join(app, 'Contents', 'Resources', _iconFile),
                      ).openRead(),
                    )
                    .first)
                .toString() !=
            wineGameIconHash) {
      return false;
    }
    return (await Process.run('/usr/bin/codesign', [
          '--verify',
          // Wine's libraries intentionally live in the sibling runtime. Check
          // that link ourselves above; codesign's strict symlink policy only
          // permits links within an entirely self-contained application.
          '--strict=sideband',
          '-R',
          '=identifier "$identifier"',
          app,
        ])).exitCode ==
        0;
  } on FileSystemException {
    return false;
  }
}

/// A small, signed app containing the actual loader, not a wrapper that execs
/// bin/wine. Libraries stay in the downloaded runtime; relative links survive
/// data-directory migration. Helper programs continue using the normal CLI.
Future<WineGameApplication> prepareWineGameApplication(
  String runtime, {
  required bool metal,
  AssetBundle? bundle,
}) async {
  final source = File(p.join(runtime, 'lib/wine/x86_64-unix/wine'));
  final ntdll = File(p.join(runtime, 'lib/wine/x86_64-unix/ntdll.so'));
  if (!await source.exists() ||
      !await ntdll.exists() ||
      (await sha256.bind(source.openRead()).first).toString() !=
          wineGameLoaderSourceHash) {
    throw const DevelopmentStorageException('Wine 游戏窗口组件与支持的版本不匹配。');
  }
  final identifier =
      'com.aimessoft.mcdev.winegame.${metal ? 'metal' : 'opengl'}';
  final app = p.join(runtime, '我的世界测试.app');
  if (await _ready(app, identifier)) return WineGameApplication(app);
  final stage = await Directory(runtime).createTemp('.mcdev-game-app-');
  // Stage at the same depth as the installed app, so the sealed relative
  // ntdll link resolves both during signing and after the atomic rename.
  final staged = '${stage.path}.app';
  final previous = Directory(p.join(stage.path, 'previous.app'));
  try {
    final contents = p.join(staged, 'Contents');
    final macos = p.join(contents, 'MacOS');
    await Directory(macos).create(recursive: true);
    await source.copy(p.join(macos, 'wine'));
    await Link(p.join(macos, 'ntdll.so')).create(_ntdllLink);
    final iconData = await (bundle ?? rootBundle).load(
      'assets/development/minecraft-bedrock-icon.icns',
    );
    final iconBytes = iconData.buffer.asUint8List(
      iconData.offsetInBytes,
      iconData.lengthInBytes,
    );
    if (sha256.convert(iconBytes).toString() != wineGameIconHash) {
      throw const DevelopmentStorageException('测试游戏图标资源校验失败。');
    }
    final icon = File(p.join(contents, 'Resources', _iconFile));
    await icon.parent.create(recursive: true);
    await icon.writeAsBytes(iconBytes, flush: true);
    await File(p.join(contents, 'Info.plist')).writeAsString(_info(identifier));
    await File(p.join(contents, 'PkgInfo')).writeAsString('APPL????');
    final permissions = await Process.run('/bin/chmod', [
      '755',
      p.join(macos, 'wine'),
    ]);
    final signed = await Process.run('/usr/bin/codesign', [
      '--force',
      '--sign',
      '-',
      '--timestamp=none',
      '--identifier',
      identifier,
      staged,
    ]);
    if (permissions.exitCode != 0 ||
        signed.exitCode != 0 ||
        !await _ready(staged, identifier)) {
      throw const DevelopmentStorageException('准备 Wine 游戏窗口组件失败。');
    }
    if (await FileSystemEntity.type(app, followLinks: false) !=
        FileSystemEntityType.notFound) {
      final info = File(p.join(app, 'Contents', 'Info.plist'));
      if (await FileSystemEntity.type(app, followLinks: false) !=
              FileSystemEntityType.directory ||
          !await info.exists() ||
          !(await info.readAsString()).contains(
            '<key>MCDevWineGameApplication</key><true/>',
          )) {
        throw const DevelopmentStorageException('Wine 游戏应用目录已被其他文件占用。');
      }
      await Directory(app).rename(previous.path);
    }
    try {
      await Directory(staged).rename(app);
    } catch (_) {
      if (await previous.exists()) await previous.rename(app);
      rethrow;
    }
    return WineGameApplication(app);
  } finally {
    if (await Directory(staged).exists()) {
      await Directory(staged).delete(recursive: true);
    }
    if (await stage.exists()) await stage.delete(recursive: true);
  }
}
