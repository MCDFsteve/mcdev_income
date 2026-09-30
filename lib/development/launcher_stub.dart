import '../core/preferences.dart';
import 'development_storage.dart';
import 'launcher_service.dart';

Future<DevelopmentLauncher> openDevelopmentLauncher(
  DevelopmentStorage storage,
  PreferenceStore preferences, {
  Future<String> Function()? cookieProvider,
}) => Future.error(const DevelopmentStorageException('开发环境仅支持 macOS。'));
