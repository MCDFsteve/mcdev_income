import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const developmentLogSaveChannel = MethodChannel(
  'mcdev_income/development_logs',
);

/// On macOS the save panel belongs to the Flutter window, rather than a
/// background helper process. Cancellation returns null without writing a file.
Future<String?> chooseDevelopmentLogExport(
  String fileName, {
  required bool filtered,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    return developmentLogSaveChannel.invokeMethod<String>('chooseLogExport', {
      'fileName': fileName,
      'filtered': filtered,
    });
  }
  return FilePicker.platform.saveFile(
    dialogTitle: filtered ? '导出筛选结果' : '导出原始日志',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['log', 'txt'],
  );
}
