import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/lan_endpoint_io.dart';

Uint8List _pong(
  Uint8List ping, {
  String message =
      'MCPE;模组联机测试;800;1.21.80;2;64;1234;世界甲;Creative;1;19132;19133;',
}) {
  final text = utf8.encode(message);
  final bytes = Uint8List(35 + text.length);
  bytes[0] = 0x1c;
  bytes.setRange(1, 9, ping.sublist(1, 9));
  bytes.setRange(17, 33, ping.sublist(9, 25));
  ByteData.sublistView(bytes).setUint16(33, text.length, Endian.big);
  bytes.setRange(35, bytes.length, text);
  return bytes;
}

Future<RawDatagramSocket> _server(
  void Function(RawDatagramSocket, Datagram) respond,
) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(socket.close);
  socket.listen((event) {
    if (event == RawSocketEvent.read) {
      final request = socket.receive();
      if (request != null) respond(socket, request);
    }
  });
  return socket;
}

void main() {
  test('allocated port is available to the game', () async {
    // Repeat the immediate exclusive bind: one attempt can miss an async
    // native-close race depending on the I/O thread's scheduling.
    for (var attempt = 0; attempt < 64; attempt++) {
      final port = await chooseAvailableLanPort();
      final socket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        reuseAddress: false,
        reusePort: false,
      );
      final closed = socket.drain<void>();
      socket.close();
      await closed;
      expect(port, inInclusiveRange(1, 65535));
    }
  });

  test('valid pong confirms world metadata at queried port only', () async {
    final server = await _server((socket, request) {
      expect(request.data.length, 33);
      expect(request.data[0], 1);
      socket.send(_pong(request.data), request.address, request.port);
    });
    final endpoint = await probeLanEndpoint(server.port);
    expect(endpoint, isNotNull);
    expect(endpoint!.port, server.port);
    expect(endpoint.motd, '模组联机测试');
    expect(endpoint.worldName, '世界甲');
    expect(endpoint.playerCount, 2);
    expect(endpoint.maxPlayers, 64);
    expect(endpoint.version, '1.21.80');
    expect(endpoint.gameMode, 'Creative');
  });

  test(
    'ignores bad echo, magic, length, format and wrong sender port',
    () async {
      final unrelated = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(unrelated.close);
      final server = await _server((socket, request) {
        unrelated.send(_pong(request.data), request.address, request.port);
        final badEcho = _pong(request.data)..[1] ^= 1;
        final badMagic = _pong(request.data)..[17] ^= 1;
        final badLength = _pong(request.data)..[34] = 0;
        final badFormat = _pong(
          request.data,
          message: 'NOT_MINECRAFT;X;800;1.2;1;2;',
        );
        final badCount = _pong(request.data, message: 'MCPE;X;800;1.2;bad;2;');
        for (final invalid in [
          badEcho,
          badMagic,
          badLength,
          badFormat,
          badCount,
        ]) {
          socket.send(invalid, request.address, request.port);
        }
      });
      final endpoint = await probeLanEndpoint(
        server.port,
        timeout: const Duration(milliseconds: 100),
      );
      expect(endpoint, isNull);
    },
  );

  test('invalid packets do not prevent a subsequent matching pong', () async {
    final server = await _server((socket, request) {
      socket.send([0x1c], request.address, request.port);
      socket.send(_pong(request.data), request.address, request.port);
    });
    expect(await probeLanEndpoint(server.port), isNotNull);
  });

  test('silent game times out and no response is invented', () async {
    final server = await _server((_, _) {});
    expect(
      await probeLanEndpoint(
        server.port,
        timeout: const Duration(milliseconds: 30),
      ),
      isNull,
    );
    await expectLater(probeLanEndpoint(0), throwsRangeError);
  });

  test(
    'bare developer pong requires opt-in and still verifies echo and magic',
    () async {
      final server = await _server((socket, request) {
        final bare = Uint8List.sublistView(_pong(request.data), 0, 33);
        socket.send(bare, request.address, request.port);
      });
      expect(
        await probeLanEndpoint(
          server.port,
          timeout: const Duration(milliseconds: 30),
        ),
        isNull,
      );
      final result = await probeLanEndpoint(server.port, allowBarePong: true);
      expect(result?.port, server.port);
      expect(result?.hasMetadata, isFalse);

      final invalid = await _server((socket, request) {
        final bare = Uint8List.sublistView(_pong(request.data), 0, 33);
        final badEcho = Uint8List.fromList(bare)..[1] ^= 1;
        final badMagic = Uint8List.fromList(bare)..[17] ^= 1;
        socket.send(badEcho, request.address, request.port);
        socket.send(badMagic, request.address, request.port);
        socket.send([...bare, 0], request.address, request.port);
      });
      expect(
        await probeLanEndpoint(
          invalid.port,
          allowBarePong: true,
          timeout: const Duration(milliseconds: 30),
        ),
        isNull,
      );
    },
  );

  test('lsof parsing accepts only this PID IPv4 loopback bindings', () {
    expect(
      parseLanProcessPorts('''n*:19999
p123
f10
n*:19132
f11
n[::]:19132
n127.0.0.1:19133
n[::1]:19134
n192.168.1.2:19135
n0.0.0.0:19136
n127.0.0.2:19137
n[::ffff:127.0.0.1]:19138
n[127.0.0.1]:19139
n[::]:19140
n127.0.0.1:22222->127.0.0.1:19132
n*:0
n*:65536
n*:bad
n*:12 trailing
nbadhost:13
n*:123456789
p456
n*:12345
pbad
n*:23456
''', 123),
      [19132, 19133, 19136],
    );
    expect(parseLanProcessPorts('p0\nn*:1234\n', 0), isEmpty);
  });

  test(
    'process discovery queries exact PID IPv4 and probes its loopback ports only',
    () async {
      final found = <int>[];
      final result = await discoverLanEndpointForProcess(
        123,
        socketRunner: (args) async {
          expect(args, ['-nP', '-a', '-p', '123', '-i4UDP', '-Fn']);
          return ProcessResult(
            1,
            0,
            'p999\nn*:19999\np123\nn[::1]:19998\nn192.168.1.2:19997\n'
                'n127.0.0.2:19996\nn*:20000\nn0.0.0.0:20001\nn127.0.0.1:20001\n',
            '',
          );
        },
        portProbe: (port, {required timeout, required allowBarePong}) async {
          found.add(port);
          expect(timeout, lessThanOrEqualTo(const Duration(milliseconds: 350)));
          expect(allowBarePong, isTrue);
          if (port != 20001) return null;
          return LanEndpoint(
            port: port,
            motd: '',
            worldName: '',
            playerCount: 0,
            maxPlayers: 0,
            version: '',
            gameMode: '',
            hasMetadata: false,
          );
        },
      );
      expect(found, [20000, 20001]);
      expect(result?.port, 20001);
      expect(result?.hasMetadata, isFalse);
    },
  );

  test(
    'discovery connects a PID socket listing to a real bare-pong server',
    () async {
      final server = await _server((socket, request) {
        socket.send(
          Uint8List.sublistView(_pong(request.data), 0, 33),
          request.address,
          request.port,
        );
      });
      final result = await discoverLanEndpointForProcess(
        123,
        socketRunner: (_) async =>
            ProcessResult(1, 0, 'p123\nf20\nn*:${server.port}\n', ''),
      );
      expect(result?.port, server.port);
      expect(result?.hasMetadata, isFalse);
    },
  );

  test(
    'missing or timed-out socket listing never triggers a fallback scan',
    () async {
      var probed = false;
      Future<LanEndpoint?> probe(
        int _, {
        required Duration timeout,
        required bool allowBarePong,
      }) async {
        probed = true;
        return null;
      }

      for (final runner in <LanSocketRunner>[
        (_) async => ProcessResult(1, 1, 'p123\nn*:19132\n', ''),
        (_) async => ProcessResult(1, 0, 'p456\nn*:19132\n', ''),
        (_) => Completer<ProcessResult>().future,
      ]) {
        expect(
          await discoverLanEndpointForProcess(
            123,
            commandTimeout: const Duration(milliseconds: 20),
            socketRunner: runner,
            portProbe: probe,
          ),
          isNull,
        );
      }
      expect(probed, isFalse);
    },
  );

  test(
    'native macOS listing discovers the current process loopback responder',
    () async {
      final server = await _server((socket, request) {
        socket.send(
          Uint8List.sublistView(_pong(request.data), 0, 33),
          request.address,
          request.port,
        );
      });
      final endpoint = await discoverLanEndpointForProcess(pid);
      expect(endpoint?.port, server.port);
      expect(endpoint?.hasMetadata, isFalse);
    },
    skip: !Platform.isMacOS,
  );
}
