import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/download_io.dart';
import 'package:mcdev_income/development/lan_endpoint_io.dart';
import 'package:mcdev_income/development/lan_join_io.dart';

LanEndpoint endpoint([int port = 19135]) => LanEndpoint(
  port: port,
  motd: '',
  worldName: '',
  playerCount: 0,
  maxPlayers: 0,
  version: '',
  gameMode: '',
  hasMetadata: false,
);

void main() {
  late bool current;
  late bool fresh;
  late DownloadControl control;
  late int probes;
  late int refreshes;

  setUp(() {
    current = true;
    fresh = false;
    control = DownloadControl();
    probes = 0;
    refreshes = 0;
  });

  Future<void> verify({
    required Future<LanEndpoint?> Function() probe,
    Future<void> Function()? refresh,
    Duration timeout = const Duration(seconds: 1),
  }) => verifyLanJoinHost(
    hostPid: 1234,
    port: 19135,
    requireHost: () {
      if (!current) {
        throw const DevelopmentStorageException('房主世界已退出或已切换');
      }
    },
    hasFreshWorld: () => fresh,
    refreshWorld: () async {
      refreshes++;
      await refresh?.call();
    },
    checkCancelled: control.check,
    discoverEndpoint: (pid, timeout) {
      expect(pid, 1234);
      expect(timeout, greaterThan(Duration.zero));
      probes++;
      return probe();
    },
    timeout: timeout,
    retryDelay: const Duration(milliseconds: 2),
  );

  test('late roster and one lost pong recover for the same host', () async {
    await verify(
      refresh: () async => fresh = refreshes >= 2,
      probe: () async => probes == 1 ? null : endpoint(),
    );
    expect(refreshes, 3);
    expect(probes, 2);
  });

  test('host replacement during endpoint lookup is rejected', () async {
    fresh = true;
    await expectLater(
      verify(
        probe: () async {
          current = false;
          return endpoint();
        },
      ),
      throwsA(
        isA<DevelopmentStorageException>().having(
          (e) => e.toString(),
          'reason',
          contains('已退出或已切换'),
        ),
      ),
    );
    expect(probes, 1);
  });

  test(
    'a confirmed different port does not silently retarget a guest',
    () async {
      fresh = true;
      await expectLater(
        verify(probe: () async => endpoint(19136)),
        throwsA(
          isA<DevelopmentStorageException>().having(
            (e) => e.toString(),
            'reason',
            contains('连接已变化'),
          ),
        ),
      );
      expect(probes, 1);
    },
  );

  test('stale roster times out without treating the host as exited', () async {
    await expectLater(
      verify(
        probe: () async => endpoint(),
        timeout: const Duration(milliseconds: 25),
      ),
      throwsA(
        isA<DevelopmentStorageException>().having(
          (e) => e.toString(),
          'reason',
          contains('暂未就绪'),
        ),
      ),
    );
    expect(probes, 0);
  });

  test(
    'cancel during lookup prevents spawning even with a valid pong',
    () async {
      fresh = true;
      await expectLater(
        verify(
          probe: () async {
            control.cancelled = true;
            return endpoint();
          },
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(probes, 1);
    },
  );

  test('roster expiry during lookup requires a new report and probe', () async {
    await verify(
      refresh: () async => fresh = true,
      probe: () async {
        if (probes == 1) fresh = false;
        return endpoint();
      },
    );
    expect(probes, 2);
    expect(refreshes, 2);
  });

  test('an unfinished lookup remains bounded by the total deadline', () async {
    fresh = true;
    final result = Completer<LanEndpoint?>();
    await expectLater(
      verify(
        probe: () => result.future,
        timeout: const Duration(milliseconds: 25),
      ),
      throwsA(
        isA<DevelopmentStorageException>().having(
          (e) => e.toString(),
          'reason',
          contains('暂未就绪'),
        ),
      ),
    );
    result.complete(endpoint());
    expect(probes, 1);
  });
}
