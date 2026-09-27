import 'dart:async';
import 'dart:io';

final _pendingLocks = <String, Future<void>>{};

/// POSIX locks are process-scoped, so also serialize isolates' callers locally.
Future<T> withFileLock<T>(
  String path,
  Future<T> Function() action, {
  bool wait = true,
}) async {
  final file = File(path).absolute;
  final previous = _pendingLocks[file.path];
  if (!wait && previous != null) throw FileSystemException('任务正被其他命令使用', path);
  final done = Completer<void>();
  _pendingLocks[file.path] = done.future;
  if (previous != null) await previous;
  RandomAccessFile? lock;
  try {
    await file.parent.create(recursive: true);
    lock = await file.open(mode: FileMode.append);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['600', file.path]);
      if (result.exitCode != 0) throw FileSystemException('无法限制锁文件权限', path);
    }
    try {
      await lock.lock(wait ? FileLock.blockingExclusive : FileLock.exclusive);
    } on FileSystemException {
      throw FileSystemException('状态正在使用中，请等待正在运行的命令结束', path);
    }
    return await action();
  } finally {
    await lock?.close();
    done.complete();
    if (identical(_pendingLocks[file.path], done.future)) {
      _pendingLocks.remove(file.path);
    }
  }
}
