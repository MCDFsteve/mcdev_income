import 'dart:io';

import 'package:file_picker/file_picker.dart';

String _joinPath(String dir, String fileName) {
  if (dir.endsWith(Platform.pathSeparator)) {
    return '$dir$fileName';
  }
  return '$dir${Platform.pathSeparator}$fileName';
}

List<String> _candidateDirectories() {
  final home = Platform.environment['HOME'];
  final userProfile = Platform.environment['USERPROFILE'];
  final docs = Platform.environment['DOCUMENTS'];
  final dirs = <String>[];

  if (Platform.isMacOS || Platform.isLinux) {
    if (home != null && home.isNotEmpty) {
      dirs.add(_joinPath(home, 'Downloads'));
      dirs.add(_joinPath(home, 'Documents'));
    }
  } else if (Platform.isWindows) {
    if (userProfile != null && userProfile.isNotEmpty) {
      dirs.add(_joinPath(userProfile, 'Downloads'));
      dirs.add(_joinPath(userProfile, 'Documents'));
    }
  }

  if (docs != null && docs.isNotEmpty) {
    dirs.add(docs);
  }
  dirs.add(Directory.current.path);

  return dirs;
}

String _normalizeCsvPath(String path) {
  final trimmed = path.trim();
  if (trimmed.toLowerCase().endsWith('.csv')) {
    return trimmed;
  }
  return '$trimmed.csv';
}

Future<String?> saveCsvToFile({
  required String fileName,
  required String content,
}) async {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出CSV',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['csv'],
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) {
        return null;
      }
      final file = File(_normalizeCsvPath(selectedPath));
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      return file.path;
    } catch (_) {
      // Fall through to default directory fallback when picker is unavailable.
    }
  }

  for (final dirPath in _candidateDirectories()) {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        continue;
      }
      final file = File(_joinPath(dir.path, fileName));
      await file.writeAsString(content, flush: true);
      return file.path;
    } catch (_) {
      // Try next candidate directory.
    }
  }
  return null;
}
