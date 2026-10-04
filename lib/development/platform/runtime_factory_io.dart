import 'dart:io';
import '../development_storage.dart';
import 'game_runtime_io.dart';
import 'macos_game_runtime.dart';
import 'windows_game_runtime.dart';

GameRuntime createGameRuntime(DevelopmentStorage storage, String sessionId) {
  if (Platform.isWindows) return WindowsGameRuntime(storage, sessionId);
  if (Platform.isMacOS) return MacWineRuntime(storage, sessionId);
  throw const DevelopmentStorageException('此平台尚未接入游戏测试运行环境。');
}
