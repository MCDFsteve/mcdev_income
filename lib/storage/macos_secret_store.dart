import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/secret_store.dart';
import 'file_lock.dart';

const _cfStringEncodingUtf8 = 0x08000100;
const _errSecSuccess = 0;
const _errSecDuplicateItem = -25299;
const _errSecItemNotFound = -25300;
const _serviceName = 'com.aimessoft.consmelt.session';
const _itemLabel = '我的世界开发者管理会话凭据';

typedef _CFStringCreateWithCStringNative =
    Pointer<Void> Function(
      Pointer<Void> alloc,
      Pointer<Utf8> cStr,
      Uint32 encoding,
    );
typedef _CFStringCreateWithCStringDart =
    Pointer<Void> Function(
      Pointer<Void> alloc,
      Pointer<Utf8> cStr,
      int encoding,
    );

typedef _CFDataCreateNative =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      Pointer<Uint8> bytes,
      IntPtr length,
    );
typedef _CFDataCreateDart =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      Pointer<Uint8> bytes,
      int length,
    );

typedef _CFDataGetLengthNative = IntPtr Function(Pointer<Void> data);
typedef _CFDataGetLengthDart = int Function(Pointer<Void> data);

typedef _CFDataGetBytePtrNative = Pointer<Uint8> Function(Pointer<Void> data);
typedef _CFDataGetBytePtrDart = Pointer<Uint8> Function(Pointer<Void> data);

typedef _CFDictionaryCreateMutableNative =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      IntPtr capacity,
      Pointer<Void> keyCallBacks,
      Pointer<Void> valueCallBacks,
    );
typedef _CFDictionaryCreateMutableDart =
    Pointer<Void> Function(
      Pointer<Void> allocator,
      int capacity,
      Pointer<Void> keyCallBacks,
      Pointer<Void> valueCallBacks,
    );

typedef _CFDictionarySetValueNative =
    Void Function(
      Pointer<Void> dict,
      Pointer<Void> key,
      Pointer<Void> value,
    );
typedef _CFDictionarySetValueDart =
    void Function(
      Pointer<Void> dict,
      Pointer<Void> key,
      Pointer<Void> value,
    );

typedef _CFReleaseNative = Void Function(Pointer<Void> cf);
typedef _CFReleaseDart = void Function(Pointer<Void> cf);

typedef _SecItemCopyMatchingNative =
    Int32 Function(Pointer<Void> query, Pointer<Pointer<Void>> result);
typedef _SecItemCopyMatchingDart =
    int Function(Pointer<Void> query, Pointer<Pointer<Void>> result);

typedef _SecItemAddNative =
    Int32 Function(Pointer<Void> attributes, Pointer<Pointer<Void>> result);
typedef _SecItemAddDart =
    int Function(Pointer<Void> attributes, Pointer<Pointer<Void>> result);

typedef _SecItemUpdateNative =
    Int32 Function(Pointer<Void> query, Pointer<Void> attributesToUpdate);
typedef _SecItemUpdateDart =
    int Function(Pointer<Void> query, Pointer<Void> attributesToUpdate);

typedef _SecItemDeleteNative = Int32 Function(Pointer<Void> query);
typedef _SecItemDeleteDart = int Function(Pointer<Void> query);

/// Stores session credentials in the macOS Keychain via Security.framework FFI.
/// Works in both GUI and `--headless` CLI processes without Flutter plugins.
class MacOsSecretStore implements SecretStore {
  MacOsSecretStore({required this.scope, required this.lockPath});

  final String scope;
  final String lockPath;

  static _MacKeychainBindings? _cachedBindings;
  static _MacKeychainBindings get _bindings =>
      _cachedBindings ??= _MacKeychainBindings();

  String _account(String key) => '$scope:$key';

  @override
  Future<String?> read(String key) => withFileLock(lockPath, () async {
    final b = _bindings;
    final serviceRef = _cfString(_serviceName);
    final accountRef = _cfString(_account(key));
    final query = _newDict();
    final resultPtr = calloc<Pointer<Void>>();
    try {
      b.cfDictionarySetValue(query, b.kSecClass, b.kSecClassGenericPassword);
      b.cfDictionarySetValue(query, b.kSecAttrService, serviceRef);
      b.cfDictionarySetValue(query, b.kSecAttrAccount, accountRef);
      b.cfDictionarySetValue(query, b.kSecReturnData, b.kCFBooleanTrue);
      b.cfDictionarySetValue(query, b.kSecMatchLimit, b.kSecMatchLimitOne);

      final status = b.secItemCopyMatching(query, resultPtr);
      if (status == _errSecItemNotFound) return null;
      if (status != _errSecSuccess) {
        throw StateError('读取 macOS 钥匙串失败 (OSStatus=$status)');
      }
      final dataRef = resultPtr.value;
      if (dataRef == nullptr) return null;
      try {
        final length = b.cfDataGetLength(dataRef);
        if (length <= 0) return '';
        final bytePtr = b.cfDataGetBytePtr(dataRef);
        if (bytePtr == nullptr) return '';
        return utf8.decode(Uint8List.fromList(bytePtr.asTypedList(length)));
      } finally {
        b.cfRelease(dataRef);
      }
    } finally {
      calloc.free(resultPtr);
      b.cfRelease(query);
      b.cfRelease(accountRef);
      b.cfRelease(serviceRef);
    }
  });

  @override
  Future<void> write(String key, String value) =>
      withFileLock(lockPath, () async {
        final b = _bindings;
        final serviceRef = _cfString(_serviceName);
        final accountRef = _cfString(_account(key));
        final labelRef = _cfString(_itemLabel);
        final dataRef = _cfData(Uint8List.fromList(utf8.encode(value)));
        final query = _newDict();
        final update = _newDict();
        final add = _newDict();
        try {
          b.cfDictionarySetValue(
            query,
            b.kSecClass,
            b.kSecClassGenericPassword,
          );
          b.cfDictionarySetValue(query, b.kSecAttrService, serviceRef);
          b.cfDictionarySetValue(query, b.kSecAttrAccount, accountRef);

          b.cfDictionarySetValue(update, b.kSecValueData, dataRef);
          b.cfDictionarySetValue(update, b.kSecAttrLabel, labelRef);
          b.cfDictionarySetValue(
            update,
            b.kSecAttrAccessible,
            b.kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
          );

          var status = b.secItemUpdate(query, update);
          if (status == _errSecSuccess) return;
          if (status == _errSecItemNotFound) {
            b.cfDictionarySetValue(
              add,
              b.kSecClass,
              b.kSecClassGenericPassword,
            );
            b.cfDictionarySetValue(add, b.kSecAttrService, serviceRef);
            b.cfDictionarySetValue(add, b.kSecAttrAccount, accountRef);
            b.cfDictionarySetValue(add, b.kSecAttrLabel, labelRef);
            b.cfDictionarySetValue(add, b.kSecValueData, dataRef);
            b.cfDictionarySetValue(
              add,
              b.kSecAttrAccessible,
              b.kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            );
            status = b.secItemAdd(add, nullptr);
            if (status == _errSecDuplicateItem) {
              status = b.secItemUpdate(query, update);
            }
          }
          if (status != _errSecSuccess) {
            throw StateError('写入 macOS 钥匙串失败 (OSStatus=$status)');
          }
        } finally {
          b.cfRelease(add);
          b.cfRelease(update);
          b.cfRelease(query);
          b.cfRelease(dataRef);
          b.cfRelease(labelRef);
          b.cfRelease(accountRef);
          b.cfRelease(serviceRef);
        }
      });

  @override
  Future<void> delete(String key) => withFileLock(lockPath, () async {
    final b = _bindings;
    final serviceRef = _cfString(_serviceName);
    final accountRef = _cfString(_account(key));
    final query = _newDict();
    try {
      b.cfDictionarySetValue(query, b.kSecClass, b.kSecClassGenericPassword);
      b.cfDictionarySetValue(query, b.kSecAttrService, serviceRef);
      b.cfDictionarySetValue(query, b.kSecAttrAccount, accountRef);

      final status = b.secItemDelete(query);
      if (status != _errSecSuccess && status != _errSecItemNotFound) {
        throw StateError('删除 macOS 钥匙串条目失败 (OSStatus=$status)');
      }
    } finally {
      b.cfRelease(query);
      b.cfRelease(accountRef);
      b.cfRelease(serviceRef);
    }
  });

  Pointer<Void> _newDict() {
    final b = _bindings;
    final dict = b.cfDictionaryCreateMutable(
      nullptr,
      0,
      b.kCFTypeDictionaryKeyCallBacks,
      b.kCFTypeDictionaryValueCallBacks,
    );
    if (dict == nullptr) {
      throw StateError('无法创建 CoreFoundation 字典');
    }
    return dict;
  }

  Pointer<Void> _cfString(String value) {
    final cStr = value.toNativeUtf8();
    try {
      final ref = _bindings.cfStringCreateWithCString(
        nullptr,
        cStr,
        _cfStringEncodingUtf8,
      );
      if (ref == nullptr) {
        throw StateError('无法创建 CFString');
      }
      return ref;
    } finally {
      calloc.free(cStr);
    }
  }

  Pointer<Void> _cfData(Uint8List bytes) {
    final native = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      if (bytes.isNotEmpty) {
        native.asTypedList(bytes.length).setAll(0, bytes);
      }
      final ref = _bindings.cfDataCreate(nullptr, native, bytes.length);
      if (ref == nullptr) {
        throw StateError('无法创建 CFData');
      }
      return ref;
    } finally {
      if (bytes.isNotEmpty) {
        native.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      }
      calloc.free(native);
    }
  }
}

class _MacKeychainBindings {
  _MacKeychainBindings()
    : _cf = DynamicLibrary.open(
        '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
      ),
      _sec = DynamicLibrary.open(
        '/System/Library/Frameworks/Security.framework/Security',
      ) {
    cfStringCreateWithCString = _cf
        .lookup<NativeFunction<_CFStringCreateWithCStringNative>>(
          'CFStringCreateWithCString',
        )
        .asFunction();
    cfDataCreate = _cf
        .lookup<NativeFunction<_CFDataCreateNative>>('CFDataCreate')
        .asFunction();
    cfDataGetLength = _cf
        .lookup<NativeFunction<_CFDataGetLengthNative>>('CFDataGetLength')
        .asFunction();
    cfDataGetBytePtr = _cf
        .lookup<NativeFunction<_CFDataGetBytePtrNative>>('CFDataGetBytePtr')
        .asFunction();
    cfDictionaryCreateMutable = _cf
        .lookup<NativeFunction<_CFDictionaryCreateMutableNative>>(
          'CFDictionaryCreateMutable',
        )
        .asFunction();
    cfDictionarySetValue = _cf
        .lookup<NativeFunction<_CFDictionarySetValueNative>>(
          'CFDictionarySetValue',
        )
        .asFunction();
    cfRelease = _cf
        .lookup<NativeFunction<_CFReleaseNative>>('CFRelease')
        .asFunction();

    kCFBooleanTrue = _cf.lookup<Pointer<Void>>('kCFBooleanTrue').value;
    kCFTypeDictionaryKeyCallBacks = _cf.lookup<Void>(
      'kCFTypeDictionaryKeyCallBacks',
    );
    kCFTypeDictionaryValueCallBacks = _cf.lookup<Void>(
      'kCFTypeDictionaryValueCallBacks',
    );

    secItemCopyMatching = _sec
        .lookup<NativeFunction<_SecItemCopyMatchingNative>>(
          'SecItemCopyMatching',
        )
        .asFunction();
    secItemAdd = _sec
        .lookup<NativeFunction<_SecItemAddNative>>('SecItemAdd')
        .asFunction();
    secItemUpdate = _sec
        .lookup<NativeFunction<_SecItemUpdateNative>>('SecItemUpdate')
        .asFunction();
    secItemDelete = _sec
        .lookup<NativeFunction<_SecItemDeleteNative>>('SecItemDelete')
        .asFunction();

    kSecClass = _sec.lookup<Pointer<Void>>('kSecClass').value;
    kSecClassGenericPassword = _sec
        .lookup<Pointer<Void>>('kSecClassGenericPassword')
        .value;
    kSecAttrService = _sec.lookup<Pointer<Void>>('kSecAttrService').value;
    kSecAttrAccount = _sec.lookup<Pointer<Void>>('kSecAttrAccount').value;
    kSecAttrLabel = _sec.lookup<Pointer<Void>>('kSecAttrLabel').value;
    kSecAttrAccessible = _sec.lookup<Pointer<Void>>('kSecAttrAccessible').value;
    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly = _sec
        .lookup<Pointer<Void>>(
          'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly',
        )
        .value;
    kSecValueData = _sec.lookup<Pointer<Void>>('kSecValueData').value;
    kSecReturnData = _sec.lookup<Pointer<Void>>('kSecReturnData').value;
    kSecMatchLimit = _sec.lookup<Pointer<Void>>('kSecMatchLimit').value;
    kSecMatchLimitOne = _sec.lookup<Pointer<Void>>('kSecMatchLimitOne').value;
  }

  final DynamicLibrary _cf;
  final DynamicLibrary _sec;

  late final _CFStringCreateWithCStringDart cfStringCreateWithCString;
  late final _CFDataCreateDart cfDataCreate;
  late final _CFDataGetLengthDart cfDataGetLength;
  late final _CFDataGetBytePtrDart cfDataGetBytePtr;
  late final _CFDictionaryCreateMutableDart cfDictionaryCreateMutable;
  late final _CFDictionarySetValueDart cfDictionarySetValue;
  late final _CFReleaseDart cfRelease;

  late final Pointer<Void> kCFBooleanTrue;
  late final Pointer<Void> kCFTypeDictionaryKeyCallBacks;
  late final Pointer<Void> kCFTypeDictionaryValueCallBacks;

  late final _SecItemCopyMatchingDart secItemCopyMatching;
  late final _SecItemAddDart secItemAdd;
  late final _SecItemUpdateDart secItemUpdate;
  late final _SecItemDeleteDart secItemDelete;

  late final Pointer<Void> kSecClass;
  late final Pointer<Void> kSecClassGenericPassword;
  late final Pointer<Void> kSecAttrService;
  late final Pointer<Void> kSecAttrAccount;
  late final Pointer<Void> kSecAttrLabel;
  late final Pointer<Void> kSecAttrAccessible;
  late final Pointer<Void> kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
  late final Pointer<Void> kSecValueData;
  late final Pointer<Void> kSecReturnData;
  late final Pointer<Void> kSecMatchLimit;
  late final Pointer<Void> kSecMatchLimitOne;
}
