import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../storage/file_lock.dart';
import 'development_storage.dart';
import 'session_preferences.dart';
import 'platform/host_files_io.dart';

/// Hold a session lease through shutdown, but share installations only during
/// preparation. The callback must release preparation after its last shared write.
Future<void> withTestSessionLocks({
  required String storageLock,
  required String prefixes,
  required String sessionId,
  required Future<void> Function(void Function() releasePreparation) run,
}) async {
  final sessionLock = p.join(
    prefixes,
    '.session-${validateTestSessionId(sessionId)}.lock',
  );
  Future<void>? lifetime;
  final prepared = Completer<void>();
  void release() {
    if (!prepared.isCompleted) prepared.complete();
  }

  // Register the lifetime lease while holding the storage lock so migration
  // cannot pass its session scan immediately before a new lease appears.
  await withFileLock(storageLock, () async {
    lifetime = withFileLock(sessionLock, () => run(release), wait: false);
    unawaited(
      lifetime!.then<void>(
        (_) => release(),
        onError: (Object _, StackTrace _) => release(),
      ),
    );
    await prepared.future;
  });
  await lifetime;
}

/// Games write SDK state beside the executable. APFS clones isolate those
/// writes and share unchanged disk blocks with the downloaded installation.
Future<String> prepareSessionGame({
  required String source,
  required String prefix,
  required String version,
}) async {
  if (!RegExp(r'^\d+(\.\d+){1,5}$').hasMatch(version)) {
    throw const DevelopmentStorageException('游戏版本号无效。');
  }
  final parentPath = p.join(prefix, 'mcdev-games');
  final targetPath = p.join(parentPath, version);
  final parent = Directory(nativeFileSystemPath(parentPath));
  final marker = File(
    nativeFileSystemPath(p.join(targetPath, '.mcdev-session-game.json')),
  );
  final sourceStat = await File(
    nativeFileSystemPath(p.join(source, 'Minecraft.Windows.exe')),
  ).stat();
  final identity = jsonEncode({
    'schema': 1,
    'version': version,
    'size': sourceStat.size,
    'modified': sourceStat.modified.microsecondsSinceEpoch,
  });
  if (await marker.exists() &&
      await marker.readAsString() == identity &&
      await File(
        nativeFileSystemPath(p.join(targetPath, 'Minecraft.Windows.exe')),
      ).exists()) {
    return targetPath;
  }
  await parent.create(recursive: true);
  final stage = await Directory(parentPath).createTemp('.game-');
  final stagePath = stage.path;
  try {
    var copied = false;
    if (Platform.isMacOS) {
      copied =
          (await Process.run('/bin/cp', [
            '-cR',
            '$source/.',
            stagePath,
          ])).exitCode ==
          0;
    }
    if (!copied) {
      // Other volumes may not support clonefile; keep the same isolation using
      // a full copy. Never hardlink files the game might modify.
      await deleteTreeIfExists(stagePath);
      await Directory(nativeFileSystemPath(stagePath)).create();
      await copyDevelopmentTree(source, stagePath);
    }
    await File(
      nativeFileSystemPath(p.join(stagePath, '.mcdev-session-game.json')),
    ).writeAsString(identity, flush: true);
    await deleteTreeIfExists(targetPath);
    await renameDirectoryNative(stagePath, targetPath);
    return targetPath;
  } finally {
    await deleteTreeIfExists(stagePath);
  }
}
