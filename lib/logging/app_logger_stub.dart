import 'package:flutter/foundation.dart';

Future<void> init({String appFolderName = 'ConsMelt'}) async {}

String? get logFilePath => null;

void info(String message) => debugPrint(message);

void warn(String message) => debugPrint('WARN  $message');

void error(String message, Object error, StackTrace stack) {
  debugPrint('ERROR $message\n$error\n$stack');
}

void flutterError(FlutterErrorDetails details) {
  debugPrint('FLUTTER ${details.exceptionAsString()}');
  FlutterError.presentError(details);
}
