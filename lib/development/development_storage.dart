import '../core/preferences.dart';
import 'storage_backend_stub.dart'
    if (dart.library.io) 'storage_backend_io.dart'
    as backend;
import 'package:path/path.dart' as p;

/// Hardware detection also recognizes Apple Silicon when the app uses Rosetta.
Future<bool> supportsDevelopment() => backend.supportsDevelopment();

Future<DevelopmentStorage> openDevelopmentStorage(
  PreferenceStore preferences,
) => backend.openDevelopmentStorage(preferences);

class DevelopmentPaths {
  const DevelopmentPaths(this.root);
  final String root;
  static const folders = ['runtimes', 'games', 'prefixes', 'downloads', 'logs'];
  String folder(String name) => p.join(root, name);
  String get runtimes => folder('runtimes');
  String get games => folder('games');
  String get prefixes => folder('prefixes');
  String get downloads => folder('downloads');
  String get logs => folder('logs');
}

class DevelopmentStorageStatus {
  const DevelopmentStorageStatus({
    required this.initialized,
    required this.exists,
    this.problem,
    this.entries = const {},
  });
  final bool initialized;
  final bool exists;
  final String? problem;
  final Map<String, int> entries;
}

class StorageMigrationProgress {
  const StorageMigrationProgress(
    this.message, {
    this.completed = 0,
    this.total = 0,
  });
  final String message;
  final int completed;
  final int total;
  double? get fraction => total == 0 ? null : completed / total;
}

class DevelopmentStorageException implements Exception {
  const DevelopmentStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class DevelopmentStorage {
  static const preferenceKey = 'development_data_root_v1';
  DevelopmentPaths get paths;
  String get lockPath;
  Future<DevelopmentStorageStatus> inspect();
  Future<void> initialize({String? root});
  Future<void> useExisting(String root);
  Future<void> migrateTo(
    String root, {
    void Function(StorageMigrationProgress)? onProgress,
  });
  Future<void> reveal(String path);
}
