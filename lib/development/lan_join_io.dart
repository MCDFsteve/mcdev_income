import 'dart:async';

import 'development_storage.dart';
import 'lan_endpoint_io.dart';

/// A missed UDP reply or a late roster report can occur while another guest is
/// loading. Keep the captured host identity, but require fresh world membership
/// and a response from its exact process before starting the new guest.
Future<void> verifyLanJoinHost({
  required int hostPid,
  required int port,
  required void Function() requireHost,
  required bool Function() hasFreshWorld,
  required Future<void> Function() refreshWorld,
  required void Function() checkCancelled,
  Future<LanEndpoint?> Function(int pid, Duration timeout)? discoverEndpoint,
  Duration timeout = const Duration(seconds: 12),
  Duration retryDelay = const Duration(milliseconds: 250),
}) async {
  final watch = Stopwatch()..start();
  Duration remaining(Duration maximum) {
    final left = timeout - watch.elapsed;
    return left < maximum ? left : maximum;
  }

  void check() {
    checkCancelled();
    requireHost();
  }

  check();
  while (watch.elapsed < timeout) {
    try {
      await refreshWorld().timeout(remaining(const Duration(seconds: 3)));
    } on TimeoutException {
      // The host's periodic probe may still be in flight. Its own identity
      // guards remain active; retry without accepting an old roster as fresh.
    }
    check();
    if (hasFreshWorld() && watch.elapsed < timeout) {
      final limit = remaining(const Duration(seconds: 3));
      LanEndpoint? endpoint;
      try {
        endpoint =
            await (discoverEndpoint != null
                    ? discoverEndpoint(hostPid, limit)
                    : discoverLanEndpointForProcess(hostPid, timeout: limit))
                .timeout(limit);
      } on TimeoutException {
        // A lost response is temporary, not evidence that the world exited.
      }
      check();
      if (endpoint != null && endpoint.port != port) {
        throw const DevelopmentStorageException('房主的局域网连接已变化，请重新添加测试玩家。');
      }
      if (endpoint?.port == port && hasFreshWorld()) return;
    }
    final delay = remaining(retryDelay);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    check();
  }
  throw const DevelopmentStorageException('房主世界或局域网端口暂未就绪，请稍后重试。');
}
