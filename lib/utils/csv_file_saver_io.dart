import 'dart:io';

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

Future<String?> saveCsvToFile({
  required String fileName,
  required String content,
}) async {
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
