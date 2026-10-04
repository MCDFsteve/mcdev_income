import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'game_window_backend.dart';
import 'game_diagnostics.dart';

/// A separate Flutter process owns the game frame. Its window_manager backend
/// controls that frame; the native host only embeds the exact owned game HWND.
class WindowsGameWindow extends GameWindowBackend {
  WindowsGameWindow({String? hostExecutable})
    : hostExecutable = hostExecutable ?? Platform.resolvedExecutable;
  final String hostExecutable;
  Process? _host;
  final _diagnostics = StreamController<GameDiagnostic>.broadcast();
  @override
  Stream<GameDiagnostic> get diagnostics => _diagnostics.stream;
  @override
  Future<GameWindowLaunch> prepare(GameWindowRequest request) async {
    if (!await File(hostExecutable).exists()) {
      throw const FileSystemException('游戏窗口宿主不存在，请重新安装软件');
    }
    return const GameWindowLaunch();
  }

  @override
  Future<void> attach(Process game, GameWindowRequest request) async {
    final host = await Process.start(hostExecutable, [
      '--game-chrome',
      '${game.pid}',
      p.absolute(request.executable),
      request.version,
      request.renderer,
      request.displayName,
    ], workingDirectory: p.dirname(hostExecutable));
    _host = host;
    final attached = Completer<void>();
    host.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (line == 'MCDEV_WINDOW_READY' && !attached.isCompleted) {
            attached.complete();
          }
        });
    unawaited(host.stderr.drain<void>());
    unawaited(
      host.exitCode.then((code) async {
        if (!attached.isCompleted) {
          attached.completeError(FileSystemException('游戏窗口宿主退出：$code'));
        } else if (identical(_host, host)) {
          try {
            await game.exitCode.timeout(const Duration(milliseconds: 500));
          } on TimeoutException {
            if (identical(_host, host)) {
              _diagnostics.add(
                GameDiagnostic(
                  '游戏窗口宿主意外退出：$code',
                  level: GameDiagnosticLevel.error,
                  fatal: true,
                ),
              );
            }
          }
        }
      }),
    );
    unawaited(
      game.exitCode.then((_) async {
        // The native host also observes this process handle. Allow its normal
        // teardown before releasing a stuck renderer host.
        try {
          await host.exitCode.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          host.kill();
        }
        if (identical(_host, host)) _host = null;
      }),
    );
    // Return the game Process immediately so its stdout/stderr can be drained.
    // Waiting here fills the native SDK pipe during startup and deadlocks it.
    unawaited(
      attached.future
          .timeout(const Duration(seconds: 120))
          .then(
            (_) {
              if (identical(_host, host)) {
                _diagnostics.add(const GameDiagnostic('游戏窗口已就绪。'));
              }
            },
            onError: (Object error) {
              if (identical(_host, host)) {
                final reason = error is TimeoutException
                    ? '等待窗口响应超时'
                    : error is FileSystemException
                    ? error.message
                    : '宿主通信失败';
                _diagnostics.add(
                  GameDiagnostic(
                    '游戏窗口初始化失败：$reason',
                    level: GameDiagnosticLevel.error,
                    fatal: true,
                  ),
                );
              }
            },
          ),
    );
  }

  @override
  Future<bool> requestClose() async {
    final host = _host;
    if (host == null) return false;
    try {
      await host.exitCode.timeout(Duration.zero);
      if (identical(_host, host)) _host = null;
      return false;
    } on TimeoutException {
      /* Still the live host owned by this session. */
    }
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$target = Get-Process -Id ${host.pid} -ErrorAction SilentlyContinue; '
            r'if ($target -and $target.Path -eq $env:MCDEV_GAME_HOST_IMAGE) { $target.CloseMainWindow() }',
      ],
      environment: {'MCDEV_GAME_HOST_IMAGE': hostExecutable},
    ).timeout(const Duration(seconds: 5));
    return result.exitCode == 0 && result.stdout.toString().trim() == 'True';
  }

  @override
  Future<void> close() async {
    _host?.kill();
    _host = null;
  }
}
