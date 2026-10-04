import 'dart:async';

enum GameDiagnosticLevel { info, warning, error }

class GameDiagnostic {
  const GameDiagnostic(
    this.message, {
    this.level = GameDiagnosticLevel.info,
    this.fatal = false,
  });
  final String message;
  final GameDiagnosticLevel level;
  final bool fatal;
  String get logLine => '[${level.name.toUpperCase()}] [运行环境] $message\n';
}

/// Each OS supplies its diagnostic sources; the launcher only consumes events.
abstract class GameDiagnostics {
  const GameDiagnostics();
  Future<void> prepare();
  Stream<GameDiagnostic> watch();
}

class NoGameDiagnostics extends GameDiagnostics {
  const NoGameDiagnostics();
  @override
  Future<void> prepare() async {}
  @override
  Stream<GameDiagnostic> watch() => const Stream.empty();
}

class CombinedGameDiagnostics extends GameDiagnostics {
  const CombinedGameDiagnostics(this.files, this.events);
  final GameDiagnostics files;
  final Stream<GameDiagnostic> events;
  @override
  Future<void> prepare() => files.prepare();
  @override
  Stream<GameDiagnostic> watch() {
    final subscriptions = <StreamSubscription<GameDiagnostic>>[];
    late StreamController<GameDiagnostic> controller;
    controller = StreamController<GameDiagnostic>(
      onListen: () {
        for (final stream in [files.watch(), events]) {
          subscriptions.add(
            stream.listen(controller.add, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }
}

/// Emit known engine milestones/failures, never raw SDK text: native logs can
/// contain complete login payloads (also Base64 encoded) on adjacent lines.
GameDiagnostic? classifyNativeDiagnostic(String line) {
  if (line.contains('set skin file not found')) {
    return const GameDiagnostic(
      '游戏无法读取玩家皮肤，请检查皮肤路径。',
      level: GameDiagnosticLevel.error,
    );
  }
  if (line.contains('ImportError: No module named')) {
    return const GameDiagnostic(
      '游戏未能导入模组脚本，请查看模组日志和脚本目录。',
      level: GameDiagnosticLevel.error,
    );
  }
  if (line.contains('launchWorld starting step')) {
    return const GameDiagnostic('引擎正在加载测试世界。');
  }
  if (line.contains('App: Quit requested')) {
    return const GameDiagnostic('引擎请求退出游戏。');
  }
  if (line.contains('MCDEV_LAN_BRIDGE ready')) {
    return const GameDiagnostic('世界脚本已运行。');
  }
  if (line.contains('MCDEV_LAN_BRIDGE report unavailable')) {
    return const GameDiagnostic(
      '世界脚本无法写入状态报告。',
      level: GameDiagnosticLevel.error,
    );
  }
  return null;
}
