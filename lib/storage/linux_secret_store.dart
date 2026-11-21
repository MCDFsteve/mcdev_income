import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../core/secret_store.dart';
import 'file_lock.dart';

const _schemaName = 'com.aimessoft.consmelt.session';
const _itemLabel = '我的世界开发者管理会话凭据';
const _collectionDefault = 'default';

final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Utf8> message;
}

typedef _GHashTableNewNative =
    Pointer<Void> Function(Pointer<Void> hashFunc, Pointer<Void> keyEqualFunc);
typedef _GHashTableNewDart =
    Pointer<Void> Function(Pointer<Void> hashFunc, Pointer<Void> keyEqualFunc);

typedef _GHashTableInsertNative =
    Int32 Function(Pointer<Void> table, Pointer<Void> key, Pointer<Void> value);
typedef _GHashTableInsertDart =
    int Function(Pointer<Void> table, Pointer<Void> key, Pointer<Void> value);

typedef _GHashTableUnrefNative = Void Function(Pointer<Void> table);
typedef _GHashTableUnrefDart = void Function(Pointer<Void> table);

typedef _GErrorFreeNative = Void Function(Pointer<_GError> error);
typedef _GErrorFreeDart = void Function(Pointer<_GError> error);

typedef _SecretSchemaNewvNative =
    Pointer<Void> Function(
      Pointer<Utf8> name,
      Int32 flags,
      Pointer<Void> attributeNamesAndTypes,
    );
typedef _SecretSchemaNewvDart =
    Pointer<Void> Function(
      Pointer<Utf8> name,
      int flags,
      Pointer<Void> attributeNamesAndTypes,
    );

typedef _SecretSchemaUnrefNative = Void Function(Pointer<Void> schema);
typedef _SecretSchemaUnrefDart = void Function(Pointer<Void> schema);

typedef _SecretPasswordStorevSyncNative =
    Int32 Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Utf8> collection,
      Pointer<Utf8> label,
      Pointer<Utf8> password,
      Pointer<Void> cancellable,
      Pointer<Pointer<_GError>> error,
    );
typedef _SecretPasswordStorevSyncDart =
    int Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Utf8> collection,
      Pointer<Utf8> label,
      Pointer<Utf8> password,
      Pointer<Void> cancellable,
      Pointer<Pointer<_GError>> error,
    );

typedef _SecretPasswordLookupvSyncNative =
    Pointer<Utf8> Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Void> cancellable,
      Pointer<Pointer<_GError>> error,
    );
typedef _SecretPasswordLookupvSyncDart =
    Pointer<Utf8> Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Void> cancellable,
      Pointer<Pointer<_GError>> error,
    );

typedef _SecretPasswordClearvSyncNative =
    Int32 Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Void> cancellable,
      Pointer<Pointer<_GError>> error,
    );
typedef _SecretPasswordClearvSyncDart =
    int Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Void> cancellable,
      Pointer<Pointer<_GError>> error,
    );

typedef _SecretPasswordFreeNative = Void Function(Pointer<Utf8> password);
typedef _SecretPasswordFreeDart = void Function(Pointer<Utf8> password);

/// Stores session credentials in the Linux Secret Service (GNOME Keyring /
/// KWallet) via runtime `libsecret-1.so.0` FFI, with `secret-tool` (stdin)
/// fallback when `libsecret` is not directly loadable. Never falls back to
/// plaintext files.
class LinuxSecretStore implements SecretStore {
  LinuxSecretStore({required this.scope, required this.lockPath});

  final String scope;
  final String lockPath;

  static _LibSecretBindings? _bindings;
  static bool _bindingsProbed = false;

  static _LibSecretBindings? _tryBindings() {
    if (!_bindingsProbed) {
      _bindingsProbed = true;
      try {
        _bindings = _LibSecretBindings();
      } catch (_) {
        _bindings = null;
      }
    }
    return _bindings;
  }

  @override
  Future<String?> read(String key) => withFileLock(lockPath, () async {
    final b = _tryBindings();
    if (b != null) return _readFfi(b, key);
    return _readSecretTool(key);
  });

  @override
  Future<void> write(String key, String value) =>
      withFileLock(lockPath, () async {
        final b = _tryBindings();
        if (b != null) {
          _writeFfi(b, key, value);
          return;
        }
        await _writeSecretTool(key, value);
      });

  @override
  Future<void> delete(String key) => withFileLock(lockPath, () async {
    final b = _tryBindings();
    if (b != null) {
      _deleteFfi(b, key);
      return;
    }
    await _deleteSecretTool(key);
  });

  T _withAttributes<T>(
    _LibSecretBindings b,
    String key,
    T Function(Pointer<Void> schema, Pointer<Void> attrs) action,
  ) {
    final schemaName = _schemaName.toNativeUtf8();
    final scopeAttr = 'scope'.toNativeUtf8();
    final keyAttr = 'key'.toNativeUtf8();
    final scopeVal = scope.toNativeUtf8();
    final keyVal = key.toNativeUtf8();
    final schemaTypes = b.gHashTableNew(b.gStrHash, b.gStrEqual);
    final attrs = b.gHashTableNew(b.gStrHash, b.gStrEqual);
    Pointer<Void> schema = nullptr;
    try {
      // SECRET_SCHEMA_ATTRIBUTE_STRING == 0
      b.gHashTableInsert(schemaTypes, scopeAttr.cast(), Pointer.fromAddress(0));
      b.gHashTableInsert(schemaTypes, keyAttr.cast(), Pointer.fromAddress(0));
      schema = b.secretSchemaNewv(schemaName, 0, schemaTypes);
      if (schema == nullptr) {
        throw StateError('无法初始化 Linux Secret Service Schema');
      }
      b.gHashTableInsert(attrs, scopeAttr.cast(), scopeVal.cast());
      b.gHashTableInsert(attrs, keyAttr.cast(), keyVal.cast());
      return action(schema, attrs);
    } finally {
      if (schema != nullptr) b.secretSchemaUnref(schema);
      b.gHashTableUnref(attrs);
      b.gHashTableUnref(schemaTypes);
      calloc.free(keyVal);
      calloc.free(scopeVal);
      calloc.free(keyAttr);
      calloc.free(scopeAttr);
      calloc.free(schemaName);
    }
  }

  Never _throwGError(_LibSecretBindings b, String action, Pointer<_GError> err) {
    try {
      final msg = err.ref.message == nullptr
          ? 'unknown error'
          : err.ref.message.toDartString();
      throw StateError(
        '$action失败（需要运行中的系统密钥环如 GNOME Keyring / KWallet；无桌面环境请使用 MCDEV_COOKIE）：$msg',
      );
    } finally {
      b.gErrorFree(err);
    }
  }

  String? _readFfi(_LibSecretBindings b, String key) =>
      _withAttributes(b, key, (schema, attrs) {
        final errPtr = calloc<Pointer<_GError>>();
        try {
          errPtr.value = nullptr;
          final result = b.secretPasswordLookupvSync(
            schema,
            attrs,
            nullptr,
            errPtr,
          );
          if (errPtr.value != nullptr) {
            _throwGError(b, '读取 Linux 密钥环', errPtr.value);
          }
          if (result == nullptr) return null;
          try {
            return result.toDartString();
          } finally {
            b.secretPasswordFree(result);
          }
        } finally {
          calloc.free(errPtr);
        }
      });

  void _writeFfi(_LibSecretBindings b, String key, String value) =>
      _withAttributes(b, key, (schema, attrs) {
        final collection = _collectionDefault.toNativeUtf8();
        final label = _itemLabel.toNativeUtf8();
        final secret = value.toNativeUtf8();
        final secretByteLen = utf8.encode(value).length;
        final errPtr = calloc<Pointer<_GError>>();
        try {
          errPtr.value = nullptr;
          final ok = b.secretPasswordStorevSync(
            schema,
            attrs,
            collection,
            label,
            secret,
            nullptr,
            errPtr,
          );
          if (errPtr.value != nullptr) {
            _throwGError(b, '写入 Linux 密钥环', errPtr.value);
          }
          if (ok == 0) {
            throw StateError('写入 Linux 密钥环失败');
          }
        } finally {
          if (secretByteLen > 0) {
            secret.cast<Uint8>().asTypedList(secretByteLen).fillRange(
              0,
              secretByteLen,
              0,
            );
          }
          calloc.free(errPtr);
          calloc.free(secret);
          calloc.free(label);
          calloc.free(collection);
        }
      });

  void _deleteFfi(_LibSecretBindings b, String key) =>
      _withAttributes(b, key, (schema, attrs) {
        final errPtr = calloc<Pointer<_GError>>();
        try {
          errPtr.value = nullptr;
          b.secretPasswordClearvSync(schema, attrs, nullptr, errPtr);
          if (errPtr.value != nullptr) {
            _throwGError(b, '删除 Linux 密钥环条目', errPtr.value);
          }
        } finally {
          calloc.free(errPtr);
        }
      });

  Future<String?> _readSecretTool(String key) async {
    try {
      final result = await Process.run('secret-tool', [
        'lookup',
        'service',
        _schemaName,
        'scope',
        scope,
        'key',
        key,
      ]);
      if (result.exitCode == 0) {
        return (result.stdout as String);
      }
      if (result.exitCode == 1 && (result.stderr as String).trim().isEmpty) {
        return null;
      }
      throw StateError(
        '读取 Linux 密钥环失败（需要运行中的系统密钥环；无桌面环境请使用 MCDEV_COOKIE）：${result.stderr}',
      );
    } on ProcessException {
      throw StateError(
        '系统未安装 libsecret 或 secret-tool，无法安全保存登录会话；请安装 libsecret 或使用 MCDEV_COOKIE 环境变量。',
      );
    }
  }

  Future<void> _writeSecretTool(String key, String value) async {
    try {
      final process = await Process.start('secret-tool', [
        'store',
        '--label=$_itemLabel',
        'service',
        _schemaName,
        'scope',
        scope,
        'key',
        key,
      ]);
      process.stdin.write(value);
      await process.stdin.close();
      final stderrText = await process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw StateError(
          '写入 Linux 密钥环失败（需要运行中的系统密钥环；无桌面环境请使用 MCDEV_COOKIE）：$stderrText',
        );
      }
    } on ProcessException {
      throw StateError(
        '系统未安装 libsecret 或 secret-tool，无法安全保存登录会话；请安装 libsecret 或使用 MCDEV_COOKIE 环境变量。',
      );
    }
  }

  Future<void> _deleteSecretTool(String key) async {
    try {
      final result = await Process.run('secret-tool', [
        'clear',
        'service',
        _schemaName,
        'scope',
        scope,
        'key',
        key,
      ]);
      if (result.exitCode != 0) {
        throw StateError('删除 Linux 密钥环条目失败：${result.stderr}');
      }
    } on ProcessException {
      throw StateError(
        '系统未安装 libsecret 或 secret-tool，无法访问系统密钥环。',
      );
    }
  }
}

class _LibSecretBindings {
  _LibSecretBindings()
    : _glib = DynamicLibrary.open('libglib-2.0.so.0'),
      _secret = DynamicLibrary.open('libsecret-1.so.0') {
    gHashTableNew = _glib
        .lookup<NativeFunction<_GHashTableNewNative>>('g_hash_table_new')
        .asFunction();
    gHashTableInsert = _glib
        .lookup<NativeFunction<_GHashTableInsertNative>>('g_hash_table_insert')
        .asFunction();
    gHashTableUnref = _glib
        .lookup<NativeFunction<_GHashTableUnrefNative>>('g_hash_table_unref')
        .asFunction();
    gErrorFree = _glib
        .lookup<NativeFunction<_GErrorFreeNative>>('g_error_free')
        .asFunction();
    gStrHash = _glib.lookup<Void>('g_str_hash');
    gStrEqual = _glib.lookup<Void>('g_str_equal');

    secretSchemaNewv = _secret
        .lookup<NativeFunction<_SecretSchemaNewvNative>>('secret_schema_newv')
        .asFunction();
    secretSchemaUnref = _secret
        .lookup<NativeFunction<_SecretSchemaUnrefNative>>('secret_schema_unref')
        .asFunction();
    secretPasswordStorevSync = _secret
        .lookup<NativeFunction<_SecretPasswordStorevSyncNative>>(
          'secret_password_storev_sync',
        )
        .asFunction();
    secretPasswordLookupvSync = _secret
        .lookup<NativeFunction<_SecretPasswordLookupvSyncNative>>(
          'secret_password_lookupv_sync',
        )
        .asFunction();
    secretPasswordClearvSync = _secret
        .lookup<NativeFunction<_SecretPasswordClearvSyncNative>>(
          'secret_password_clearv_sync',
        )
        .asFunction();
    secretPasswordFree = _secret
        .lookup<NativeFunction<_SecretPasswordFreeNative>>(
          'secret_password_free',
        )
        .asFunction();
  }

  final DynamicLibrary _glib;
  final DynamicLibrary _secret;

  late final _GHashTableNewDart gHashTableNew;
  late final _GHashTableInsertDart gHashTableInsert;
  late final _GHashTableUnrefDart gHashTableUnref;
  late final _GErrorFreeDart gErrorFree;
  late final Pointer<Void> gStrHash;
  late final Pointer<Void> gStrEqual;

  late final _SecretSchemaNewvDart secretSchemaNewv;
  late final _SecretSchemaUnrefDart secretSchemaUnref;
  late final _SecretPasswordStorevSyncDart secretPasswordStorevSync;
  late final _SecretPasswordLookupvSyncDart secretPasswordLookupvSync;
  late final _SecretPasswordClearvSyncDart secretPasswordClearvSync;
  late final _SecretPasswordFreeDart secretPasswordFree;
}
