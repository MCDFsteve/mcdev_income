import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'development_storage.dart';
import 'performance_patch.dart';

Future<void> validatePerformanceGame(String version, File executable) async {
  if (!supportsPerformancePatch(version) ||
      !await executable.exists() ||
      (await sha256.bind(executable.openRead()).first).toString() !=
          performanceGameHash) {
    throw const DevelopmentStorageException(
      '性能补丁与游戏文件不匹配。请关闭性能优化后启动，或重新下载受支持版本。',
    );
  }
}

Future<Directory> preparePerformancePatch(
  String runtimes, {
  AssetBundle? bundle,
}) async {
  final source = bundle ?? rootBundle;
  final directory = Directory(p.join(runtimes, 'graphics-patch-v1'));
  await directory.create(recursive: true);
  for (final entry in performancePatchAssets.entries) {
    final target = File(p.join(directory.path, entry.key));
    if (await target.exists() &&
        (await sha256.bind(target.openRead()).first).toString() ==
            entry.value) {
      continue;
    }
    final data = await source.load('assets/development/${entry.key}');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != entry.value) {
      throw const DevelopmentStorageException('性能补丁资源校验失败，未注入。');
    }
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  }
  return directory;
}

/// A failing helper never stops the game or kills its Wine prefix.
Future<bool> injectPerformancePatch({
  required String? wine,
  int? targetPid,
  required Map<String, String> environment,
  required String helper,
  required String dll,
  required String executable,
  Future<void>? cancelWhen,
  Duration timeout = const Duration(minutes: 2),
}) async {
  if (wine == null && (targetPid == null || targetPid <= 0)) return false;
  final child = await Process.start(
    wine ??
        p.join(p.dirname(Platform.resolvedExecutable), 'mcdev_game_helper.exe'),
    [
      if (wine != null) helper,
      dll,
      executable,
      if (wine == null) targetPid.toString(),
    ],
    environment: environment,
  );
  final subscriptions = [
    child.stdout.listen((_) {}, onError: (Object _, StackTrace _) {}),
    child.stderr.listen((_) {}, onError: (Object _, StackTrace _) {}),
  ];
  var finished = false;
  if (cancelWhen != null) {
    unawaited(
      cancelWhen.then<void>((_) {
        if (!finished) child.kill(ProcessSignal.sigterm);
      }, onError: (Object _, StackTrace _) {}),
    );
  }
  try {
    final code = await child.exitCode.timeout(timeout);
    // Wine background processes can inherit these pipes after the helper exits.
    // EOF is not proof of injection success; the helper's exit code is.
    return code == 0;
  } on TimeoutException {
    child.kill(ProcessSignal.sigterm);
    return false;
  } finally {
    finished = true;
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }
}
