import 'dart:io';

import 'package:flutter/foundation.dart';

String? _logFilePath;
bool _initialized = false;

Future<void> init({String appFolderName = 'ConsMelt'}) async {
  if (_initialized) {
    return;
  }
  _initialized = true;

  final logDir = _resolveLogDir(appFolderName);
  await Directory(logDir).create(recursive: true);
  _logFilePath = '$logDir${Platform.pathSeparator}app.log';
  _writeLine('===== app start =====');
  final path = _logFilePath;
  if (path != null) {
    _writeLine('log file: $path');
  }
}

String? get logFilePath => _logFilePath;

void info(String message) => _writeLine('INFO  $message');

void warn(String message) => _writeLine('WARN  $message');

void error(String message, Object error, StackTrace stack) {
  _writeLine('ERROR $message\n$error\n$stack');
}

void flutterError(FlutterErrorDetails details) {
  final stack = details.stack ?? StackTrace.empty;
  _writeLine('FLUTTER ${details.exceptionAsString()}\n$stack');
  FlutterError.presentError(details);
}

void _writeLine(String message) {
  final timestamp = DateTime.now().toIso8601String();
  final line = '[$timestamp] $message';
  debugPrint(line);
  final path = _logFilePath;
  if (path == null) {
    return;
  }
  try {
    File(path).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {
    // Best-effort logging; ignore file system errors.
  }
}

String _resolveLogDir(String appFolderName) {
  if (Platform.isWindows) {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
    if (base != null && base.isNotEmpty) {
      return '$base${Platform.pathSeparator}$appFolderName${Platform.pathSeparator}logs';
    }
  }

  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Logs${Platform.pathSeparator}$appFolderName';
    }
  }

  if (Platform.isLinux) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home${Platform.pathSeparator}.local${Platform.pathSeparator}share${Platform.pathSeparator}$appFolderName${Platform.pathSeparator}logs';
    }
  }

  return Directory.current.path;
}
