import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/secret_store.dart';
import 'file_preferences.dart';
import 'linux_secret_store.dart';
import 'macos_secret_store.dart';
import 'windows_secret_store.dart';

final _testStoresByScope = <String, MemorySecretStore>{};

/// Clears in-memory desktop secret stores used during `flutter test`.
void resetTestDesktopSecretStores() => _testStoresByScope.clear();

String desktopSecretScope(String directory) {
  final normalized = p.normalize(Directory(directory).absolute.path);
  final canonical = Platform.isWindows ? normalized.toLowerCase() : normalized;
  return sha256.convert(utf8.encode(canonical)).toString().substring(0, 16);
}

/// Opens the desktop OS secret store scoped to [directory] (defaulting to
/// [mcdevHome]). In `FLUTTER_TEST` mode, returns a per-directory in-memory
/// store so unit tests never touch the developer's real OS keychain.
Future<SecretStore?> openDesktopSecretStore([String? directory]) async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return null;
  }
  final dirPath = directory ?? mcdevHome();
  final scope = desktopSecretScope(dirPath);
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return _testStoresByScope.putIfAbsent(scope, MemorySecretStore.new);
  }
  return openNativeDesktopSecretStore(dirPath);
}

/// Opens the real OS credential vault for [directory], even in test processes.
Future<SecretStore> openNativeDesktopSecretStore(String directory) async {
  final dir = Directory(directory);
  await dir.create(recursive: true);
  final absDir = dir.absolute.path;
  final scope = desktopSecretScope(absDir);
  final lockPath = '$absDir/secrets.lock';
  if (Platform.isWindows) {
    return WindowsSecretStore(
      directory: absDir,
      scope: scope,
      lockPath: lockPath,
    );
  }
  if (Platform.isMacOS) {
    return MacOsSecretStore(scope: scope, lockPath: lockPath);
  }
  if (Platform.isLinux) {
    return LinuxSecretStore(scope: scope, lockPath: lockPath);
  }
  throw UnsupportedError('当前平台不支持桌面安全存储');
}
