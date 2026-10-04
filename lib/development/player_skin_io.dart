import 'dart:io';
import 'package:path/path.dart' as p;
import 'development_storage.dart';
import 'launcher_service.dart';

/// The game's external skin loader cannot reliably read paths containing
/// spaces. Each runtime supplies a session-local directory and its short,
/// absolute game-visible path. Preserve the official bytes: the development
/// client validates built-in skin IDs against the original PNG, not its pixels.
Future<Map<String, Object>> prepareTestPlayerSkin({
  required TestPlayerSkin skin,
  required String gameDirectory,
  required String skinDirectory,
  required String gameSkinDirectory,
}) async {
  final source = File(
    p.join(gameDirectory, 'data', 'skin_packs', 'vanilla', skin.textureFile),
  );
  if (!await source.exists()) {
    throw DevelopmentStorageException('游戏缺少所选皮肤 ${skin.textureFile}，请重新安装此版本。');
  }
  final directory = Directory(skinDirectory);
  await directory.create(recursive: true);
  final staging = await directory.createTemp('.skin-');
  try {
    final texture = await source.copy(p.join(staging.path, skin.textureFile));
    await texture.rename(p.join(directory.path, skin.textureFile));
  } finally {
    await staging.delete(recursive: true);
  }
  return skin.skinInfo(p.windows.join(gameSkinDirectory, skin.textureFile));
}
