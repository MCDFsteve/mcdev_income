import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/secret_store.dart';
import 'desktop_secret_store_stub.dart'
    if (dart.library.io) 'desktop_secret_store_io.dart'
    as desktop;

/// Resolves the platform-native [SecretStore]:
/// - Desktop (Windows / macOS / Linux): OS vault via FFI, shared with CLI.
/// - Mobile (Android / iOS): OS Keystore / Keychain via MethodChannel.
/// - Web / Flutter test fallback: in-memory store (never writes plaintext).
class AppSecretStore {
  static const _channel = MethodChannel('mcdev_income/secure_storage');
  static final _memoryFallback = MemorySecretStore();

  /// Optional test hook allowing widget tests to inject a deterministic store.
  @visibleForTesting
  static SecretStore? testOverride;

  static Future<SecretStore> getInstance() async {
    final override = testOverride;
    if (override != null) return override;

    final desktopStore = await desktop.openDesktopSecretStore();
    if (desktopStore != null) return desktopStore;

    if (kIsWeb) return _memoryFallback;

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return const _MethodChannelSecretStore(_channel);
    }
    return _memoryFallback;
  }
}

class _MethodChannelSecretStore implements SecretStore {
  const _MethodChannelSecretStore(this._channel);

  final MethodChannel _channel;

  @override
  Future<String?> read(String key) async {
    return _channel.invokeMethod<String>('read', {'key': key});
  }

  @override
  Future<void> write(String key, String value) async {
    await _channel.invokeMethod<void>('write', {'key': key, 'value': value});
  }

  @override
  Future<void> delete(String key) async {
    await _channel.invokeMethod<void>('delete', {'key': key});
  }
}
