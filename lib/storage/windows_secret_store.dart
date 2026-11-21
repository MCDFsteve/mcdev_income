import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/secret_store.dart';
import 'file_lock.dart';

const _credTypeGeneric = 1;
const _credPersistLocalMachine = 2;
const _errorNotFound = 1168;
// Returned by CredReadW/CredWriteW in network/SSH logon sessions that have no
// interactive credential set; DPAPI (CryptProtectData) remains available there.
const _errorNoSuchLogonSession = 1312;
const _cryptProtectUiForbidden = 0x1;
const _chunkByteLimit = 2048;
const _chunkManifestKey = '__mcdev_chunks__';

final class _FileTime extends Struct {
  @Uint32()
  external int dwLowDateTime;

  @Uint32()
  external int dwHighDateTime;
}

final class _CredentialW extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int type;

  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  external _FileTime lastWritten;

  @Uint32()
  external int credentialBlobSize;

  external Pointer<Uint8> credentialBlob;

  @Uint32()
  external int persist;

  @Uint32()
  external int attributeCount;

  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CredReadWNative =
    Int32 Function(
      Pointer<Utf16> targetName,
      Uint32 type,
      Uint32 flags,
      Pointer<Pointer<_CredentialW>> credential,
    );
typedef _CredReadWDart =
    int Function(
      Pointer<Utf16> targetName,
      int type,
      int flags,
      Pointer<Pointer<_CredentialW>> credential,
    );

typedef _CredWriteWNative =
    Int32 Function(Pointer<_CredentialW> credential, Uint32 flags);
typedef _CredWriteWDart =
    int Function(Pointer<_CredentialW> credential, int flags);

typedef _CredDeleteWNative =
    Int32 Function(Pointer<Utf16> targetName, Uint32 type, Uint32 flags);
typedef _CredDeleteWDart =
    int Function(Pointer<Utf16> targetName, int type, int flags);

typedef _CredFreeNative = Void Function(Pointer<Void> buffer);
typedef _CredFreeDart = void Function(Pointer<Void> buffer);

typedef _CryptProtectDataNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Utf16> dataDescr,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> promptStruct,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptProtectDataDart =
    int Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Utf16> dataDescr,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> promptStruct,
      int flags,
      Pointer<_DataBlob> dataOut,
    );

typedef _CryptUnprotectDataNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Pointer<Utf16>> dataDescr,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> promptStruct,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptUnprotectDataDart =
    int Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Pointer<Utf16>> dataDescr,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> promptStruct,
      int flags,
      Pointer<_DataBlob> dataOut,
    );

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> mem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> mem);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// Stores session credentials in Windows Credential Manager via Win32 FFI.
/// In headless network/SSH logon sessions where Windows Credential Manager
/// returns `ERROR_NO_SUCH_LOGON_SESSION (1312)`, falls back to user-scoped
/// Windows DPAPI (`CryptProtectData` / `CryptUnprotectData`).
/// Works in both GUI and `--headless` CLI processes without Flutter plugins.
class WindowsSecretStore implements SecretStore {
  WindowsSecretStore({
    required this.directory,
    required this.scope,
    required this.lockPath,
  });

  final String directory;
  final String scope;
  final String lockPath;

  static _WinSecurityBindings? _cachedBindings;
  static _WinSecurityBindings get _bindings =>
      _cachedBindings ??= _WinSecurityBindings();

  File get _dpapiFile => File('$directory/session.dpapi');
  String _target(String key) => 'mcdev_income:$scope:$key';
  String _chunkTarget(String key, int index) => '${_target(key)}#$index';

  @override
  Future<String?> read(String key) => withFileLock(lockPath, () async {
    try {
      final value = _readCredManager(key);
      if (value != null) return value;
    } on _NoLogonSessionException {
      return _readDpapi(key);
    }
    return _readDpapi(key);
  });

  @override
  Future<void> write(String key, String value) =>
      withFileLock(lockPath, () async {
        try {
          _writeCredManager(key, value);
          await _deleteDpapiKey(key);
        } on _NoLogonSessionException {
          await _writeDpapi(key, value);
        }
      });

  @override
  Future<void> delete(String key) => withFileLock(lockPath, () async {
    try {
      _deleteCredManager(key);
    } on _NoLogonSessionException {
      // Continue to scrub the DPAPI store below.
    }
    await _deleteDpapiKey(key);
  });

  String? _readCredManager(String key) {
    final raw = _readRaw(_target(key));
    if (raw == null) return null;
    final chunkCount = _parseChunkCount(raw);
    if (chunkCount == null) {
      return utf8.decode(raw);
    }
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < chunkCount; i++) {
      final chunk = _readRaw(_chunkTarget(key, i));
      if (chunk == null) return null;
      builder.add(chunk);
    }
    return utf8.decode(builder.toBytes());
  }

  void _writeCredManager(String key, String value) {
    final bytes = Uint8List.fromList(utf8.encode(value));
    final previousRaw = _readRaw(_target(key));
    final previousChunks = previousRaw == null
        ? 0
        : (_parseChunkCount(previousRaw) ?? 0);

    if (bytes.length <= _chunkByteLimit) {
      _writeRaw(_target(key), bytes);
      for (var i = 0; i < previousChunks; i++) {
        _deleteRaw(_chunkTarget(key, i));
      }
      return;
    }

    final chunkCount = (bytes.length + _chunkByteLimit - 1) ~/ _chunkByteLimit;
    for (var i = 0; i < chunkCount; i++) {
      final start = i * _chunkByteLimit;
      final end = start + _chunkByteLimit > bytes.length
          ? bytes.length
          : start + _chunkByteLimit;
      _writeRaw(
        _chunkTarget(key, i),
        Uint8List.sublistView(bytes, start, end),
      );
    }
    final manifest = Uint8List.fromList(
      utf8.encode(jsonEncode({_chunkManifestKey: chunkCount})),
    );
    _writeRaw(_target(key), manifest);
    for (var i = chunkCount; i < previousChunks; i++) {
      _deleteRaw(_chunkTarget(key, i));
    }
  }

  void _deleteCredManager(String key) {
    final raw = _readRaw(_target(key));
    final chunkCount = raw == null ? 0 : (_parseChunkCount(raw) ?? 0);
    for (var i = 0; i < chunkCount; i++) {
      _deleteRaw(_chunkTarget(key, i));
    }
    _deleteRaw(_target(key));
  }

  int? _parseChunkCount(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map && decoded.length == 1) {
        final count = decoded[_chunkManifestKey];
        if (count is int && count > 0) return count;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Uint8List? _readRaw(String targetName) {
    final bindings = _bindings;
    final targetPtr = targetName.toNativeUtf16();
    final outPtr = calloc<Pointer<_CredentialW>>();
    try {
      final ok = bindings.credReadW(targetPtr, _credTypeGeneric, 0, outPtr);
      if (ok == 0) {
        final error = bindings.getLastError();
        if (error == _errorNotFound) return null;
        if (error == _errorNoSuchLogonSession) {
          throw const _NoLogonSessionException();
        }
        throw StateError('读取 Windows 凭据管理器失败 (error=$error)');
      }
      final credPtr = outPtr.value;
      if (credPtr == nullptr) return null;
      try {
        final size = credPtr.ref.credentialBlobSize;
        final blob = credPtr.ref.credentialBlob;
        if (size == 0 || blob == nullptr) return Uint8List(0);
        return Uint8List.fromList(blob.asTypedList(size));
      } finally {
        bindings.credFree(credPtr.cast());
      }
    } finally {
      calloc.free(outPtr);
      calloc.free(targetPtr);
    }
  }

  void _writeRaw(String targetName, Uint8List bytes) {
    final bindings = _bindings;
    final targetPtr = targetName.toNativeUtf16();
    final userPtr = 'mcdev_income'.toNativeUtf16();
    final commentPtr = '我的世界开发者管理会话凭据'.toNativeUtf16();
    final blobPtr = bytes.isEmpty ? nullptr : calloc<Uint8>(bytes.length);
    final credPtr = calloc<_CredentialW>();
    try {
      if (bytes.isNotEmpty) {
        blobPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      credPtr.ref
        ..flags = 0
        ..type = _credTypeGeneric
        ..targetName = targetPtr
        ..comment = commentPtr
        ..credentialBlobSize = bytes.length
        ..credentialBlob = blobPtr
        ..persist = _credPersistLocalMachine
        ..attributeCount = 0
        ..attributes = nullptr
        ..targetAlias = nullptr
        ..userName = userPtr;

      final ok = bindings.credWriteW(credPtr, 0);
      if (ok == 0) {
        final error = bindings.getLastError();
        if (error == _errorNoSuchLogonSession) {
          throw const _NoLogonSessionException();
        }
        throw StateError('写入 Windows 凭据管理器失败 (error=$error)');
      }
    } finally {
      if (blobPtr != nullptr) {
        blobPtr.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
        calloc.free(blobPtr);
      }
      calloc.free(credPtr);
      calloc.free(commentPtr);
      calloc.free(userPtr);
      calloc.free(targetPtr);
    }
  }

  void _deleteRaw(String targetName) {
    final bindings = _bindings;
    final targetPtr = targetName.toNativeUtf16();
    try {
      final ok = bindings.credDeleteW(targetPtr, _credTypeGeneric, 0);
      if (ok == 0) {
        final error = bindings.getLastError();
        if (error == _errorNotFound) return;
        if (error == _errorNoSuchLogonSession) {
          throw const _NoLogonSessionException();
        }
        throw StateError('删除 Windows 凭据管理器条目失败 (error=$error)');
      }
    } finally {
      calloc.free(targetPtr);
    }
  }

  Future<Map<String, String>> _readDpapiMap() async {
    if (!await _dpapiFile.exists()) return {};
    try {
      final decoded = jsonDecode(await _dpapiFile.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeDpapiMap(Map<String, String> entries) async {
    if (entries.isEmpty) {
      if (await _dpapiFile.exists()) await _dpapiFile.delete();
      return;
    }
    await Directory(directory).create(recursive: true);
    final temp = File(
      '$directory/.dpapi-$pid-${Random.secure().nextInt(1 << 32)}.tmp',
    );
    try {
      await temp.writeAsString(jsonEncode(entries), flush: true);
      await temp.rename(_dpapiFile.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<String?> _readDpapi(String key) async {
    final entries = await _readDpapiMap();
    final encoded = entries[key];
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final cipherBytes = base64Decode(encoded);
      final plainBytes = _dpapiUnprotect(
        cipherBytes,
        Uint8List.fromList(utf8.encode(_target(key))),
      );
      return utf8.decode(plainBytes);
    } catch (_) {
      entries.remove(key);
      await _writeDpapiMap(entries);
      return null;
    }
  }

  Future<void> _writeDpapi(String key, String value) async {
    final entries = await _readDpapiMap();
    final cipherBytes = _dpapiProtect(
      Uint8List.fromList(utf8.encode(value)),
      Uint8List.fromList(utf8.encode(_target(key))),
    );
    entries[key] = base64Encode(cipherBytes);
    await _writeDpapiMap(entries);
  }

  Future<void> _deleteDpapiKey(String key) async {
    if (!await _dpapiFile.exists()) return;
    final entries = await _readDpapiMap();
    if (entries.remove(key) != null) {
      await _writeDpapiMap(entries);
    } else if (entries.isEmpty) {
      await _dpapiFile.delete();
    }
  }

  Uint8List _dpapiProtect(Uint8List plain, Uint8List entropy) {
    final bindings = _bindings;
    final inBuf = calloc<Uint8>(plain.isEmpty ? 1 : plain.length);
    final entBuf = calloc<Uint8>(entropy.isEmpty ? 1 : entropy.length);
    final inBlob = calloc<_DataBlob>();
    final entBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    final descr = '我的世界开发者管理会话凭据'.toNativeUtf16();
    try {
      if (plain.isNotEmpty) inBuf.asTypedList(plain.length).setAll(0, plain);
      if (entropy.isNotEmpty) {
        entBuf.asTypedList(entropy.length).setAll(0, entropy);
      }
      inBlob.ref
        ..cbData = plain.length
        ..pbData = inBuf;
      entBlob.ref
        ..cbData = entropy.length
        ..pbData = entBuf;

      final ok = bindings.cryptProtectData(
        inBlob,
        descr,
        entBlob,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        outBlob,
      );
      if (ok == 0) {
        final error = bindings.getLastError();
        throw StateError('DPAPI 加密会话失败 (error=$error)');
      }
      try {
        final len = outBlob.ref.cbData;
        if (len == 0 || outBlob.ref.pbData == nullptr) return Uint8List(0);
        return Uint8List.fromList(outBlob.ref.pbData.asTypedList(len));
      } finally {
        if (outBlob.ref.pbData != nullptr) {
          bindings.localFree(outBlob.ref.pbData.cast());
        }
      }
    } finally {
      if (plain.isNotEmpty) {
        inBuf.asTypedList(plain.length).fillRange(0, plain.length, 0);
      }
      calloc.free(descr);
      calloc.free(outBlob);
      calloc.free(entBlob);
      calloc.free(inBlob);
      calloc.free(entBuf);
      calloc.free(inBuf);
    }
  }

  Uint8List _dpapiUnprotect(Uint8List cipher, Uint8List entropy) {
    final bindings = _bindings;
    final inBuf = calloc<Uint8>(cipher.isEmpty ? 1 : cipher.length);
    final entBuf = calloc<Uint8>(entropy.isEmpty ? 1 : entropy.length);
    final inBlob = calloc<_DataBlob>();
    final entBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    try {
      if (cipher.isNotEmpty) inBuf.asTypedList(cipher.length).setAll(0, cipher);
      if (entropy.isNotEmpty) {
        entBuf.asTypedList(entropy.length).setAll(0, entropy);
      }
      inBlob.ref
        ..cbData = cipher.length
        ..pbData = inBuf;
      entBlob.ref
        ..cbData = entropy.length
        ..pbData = entBuf;

      final ok = bindings.cryptUnprotectData(
        inBlob,
        nullptr,
        entBlob,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        outBlob,
      );
      if (ok == 0) {
        final error = bindings.getLastError();
        throw StateError('DPAPI 解密会话失败 (error=$error)');
      }
      try {
        final len = outBlob.ref.cbData;
        if (len == 0 || outBlob.ref.pbData == nullptr) return Uint8List(0);
        final outView = outBlob.ref.pbData.asTypedList(len);
        final copy = Uint8List.fromList(outView);
        outView.fillRange(0, len, 0);
        return copy;
      } finally {
        if (outBlob.ref.pbData != nullptr) {
          bindings.localFree(outBlob.ref.pbData.cast());
        }
      }
    } finally {
      calloc.free(outBlob);
      calloc.free(entBlob);
      calloc.free(inBlob);
      calloc.free(entBuf);
      calloc.free(inBuf);
    }
  }
}

class _NoLogonSessionException implements Exception {
  const _NoLogonSessionException();
}

class _WinSecurityBindings {
  _WinSecurityBindings()
    : _advapi32 = DynamicLibrary.open('advapi32.dll'),
      _crypt32 = DynamicLibrary.open('crypt32.dll'),
      _kernel32 = DynamicLibrary.open('kernel32.dll') {
    credReadW = _advapi32
        .lookup<NativeFunction<_CredReadWNative>>('CredReadW')
        .asFunction();
    credWriteW = _advapi32
        .lookup<NativeFunction<_CredWriteWNative>>('CredWriteW')
        .asFunction();
    credDeleteW = _advapi32
        .lookup<NativeFunction<_CredDeleteWNative>>('CredDeleteW')
        .asFunction();
    credFree = _advapi32
        .lookup<NativeFunction<_CredFreeNative>>('CredFree')
        .asFunction();
    cryptProtectData = _crypt32
        .lookup<NativeFunction<_CryptProtectDataNative>>('CryptProtectData')
        .asFunction();
    cryptUnprotectData = _crypt32
        .lookup<NativeFunction<_CryptUnprotectDataNative>>('CryptUnprotectData')
        .asFunction();
    localFree = _kernel32
        .lookup<NativeFunction<_LocalFreeNative>>('LocalFree')
        .asFunction();
    getLastError = _kernel32
        .lookup<NativeFunction<_GetLastErrorNative>>('GetLastError')
        .asFunction();
  }

  final DynamicLibrary _advapi32;
  final DynamicLibrary _crypt32;
  final DynamicLibrary _kernel32;
  late final _CredReadWDart credReadW;
  late final _CredWriteWDart credWriteW;
  late final _CredDeleteWDart credDeleteW;
  late final _CredFreeDart credFree;
  late final _CryptProtectDataDart cryptProtectData;
  late final _CryptUnprotectDataDart cryptUnprotectData;
  late final _LocalFreeDart localFree;
  late final _GetLastErrorDart getLastError;
}
