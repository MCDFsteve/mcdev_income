import '../core/preferences.dart';
import 'development_storage.dart';

Future<bool> supportsDevelopment() async => false;
Future<DevelopmentStorage> openDevelopmentStorage(
  PreferenceStore preferences,
) =>
    Future.error(const DevelopmentStorageException('开发功能仅支持 Apple 芯片的 macOS。'));
