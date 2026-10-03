import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/lan_rpc_io.dart';

final _key = List<int>.generate(32, (index) => index);

Uint8List _body(int command, List<int> payload) {
  final data = Uint8List(payload.length + 2);
  ByteData.sublistView(data).setUint16(0, command, Endian.little);
  data.setRange(2, data.length, payload);
  return data;
}

Uint8List _frame(Uint8List body) {
  final data = Uint8List(body.length + 2);
  ByteData.sublistView(data).setUint16(0, body.length, Endian.little);
  data.setRange(2, data.length, body);
  return data;
}

Uint8List _handshake() => _frame(_body(0, [0, 0, 32, 0, ..._key]));

Uint8List _encrypted(LanRpcChaCha8 cipher, int code, List<int> payload) {
  final data = _body(code, payload);
  cipher.process(data);
  return _frame(data);
}

LanRpcChaCha8 _gameCipher() =>
    LanRpcChaCha8([..._key.sublist(16), ..._key.sublist(0, 16)]);

Future<T> _bounded<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 5));

void main() {
  test('ChaCha8 matches native MCStudio DLL across partial blocks', () {
    // Produced by _51258412... / _b79c502... in the original 32-bit utility DLL,
    // calling Process for 3, 66, then 75 zero bytes with key bytes 0..31.
    const expected =
        '3ea028a6a0abac3174ca47d1c923a877e11e9eaf1c900a1555704e4707f68fab'
        '93ac6f9d9a0a74bf5a9bd2d2bf0ec5c109f02e3be9d408ea7cdddc0ef04dca49'
        '318d770b596cba7ac0367a14a5194c1bb8f878bdd30e02681df7c80539fe00629'
        '140a4c9210f71db0054329b323da34edfe62a77a6292c61c0cdb24ef33874583c'
        '8a05743b20b070353bf2c475b63ddf';
    final cipher = LanRpcChaCha8(_key);
    final pieces = [Uint8List(3), Uint8List(66), Uint8List(75)];
    for (final piece in pieces) {
      cipher.process(piece);
    }
    expect(
      pieces
          .expand((piece) => piece)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
      expected,
    );
  });

  test(
    'fragmented and coalesced frames expose the actual bound port',
    () async {
      final endpoint = Completer<int>();
      final ready = Completer<LanRpcPacket>();
      final errors = <String>[];
      final rpc = await LanGameRpc.start(
        onEndpoint: endpoint.complete,
        onPacket: (packet) {
          if (packet.command == 261) ready.complete(packet);
        },
        onError: errors.add,
      );
      addTearDown(rpc.close);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        rpc.port,
      );
      addTearDown(socket.destroy);
      final cipher = _gameCipher();
      final bytes = [
        ..._handshake(),
        ..._encrypted(cipher, 261, [7, 0]),
        ..._encrypted(cipher, 518, [7, 0, 0, 0x39, 0x4a, 0, 0]),
      ];
      socket.add(bytes.sublist(0, 1));
      await socket.flush();
      socket.add(bytes.sublist(1, 17));
      await socket.flush();
      socket.add(bytes.sublist(17));
      expect(await _bounded(endpoint.future), 19001);
      expect((await _bounded(ready.future)).payload, [7, 0]);
      expect(rpc.connected, isTrue);
      expect(rpc.endpoint, 19001);
      expect(errors, isEmpty);
    },
  );

  test(
    'encrypted replies use the original key and continuous stream',
    () async {
      final ready = Completer<void>();
      final rpc = await LanGameRpc.start(onPacket: (_) => ready.complete());
      addTearDown(rpc.close);
      expect(rpc.refreshPlayers(), isFalse);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        rpc.port,
      );
      addTearDown(socket.destroy);
      final received = <int>[];
      final done = Completer<void>();
      socket.listen((data) {
        received.addAll(data);
        if (received.length == 11 && !done.isCompleted) done.complete();
      });
      socket.add([
        ..._handshake(),
        ..._encrypted(_gameCipher(), 261, [0, 0]),
      ]);
      await _bounded(ready.future);
      expect(rpc.refreshPlayers(), isTrue);
      expect(rpc.send(0x120, [1, 2, 3]), isTrue);
      await _bounded(done.future);
      final cipher = LanRpcChaCha8(_key);
      final first = Uint8List.fromList(received.sublist(2, 4));
      final second = Uint8List.fromList(received.sublist(6));
      cipher.process(first);
      cipher.process(second);
      expect(first, _body(272, []));
      expect(second, _body(0x120, [1, 2, 3]));
      expect(rpc.send(70000), isFalse);
      expect(rpc.send(1, Uint8List(65534)), isFalse);
    },
  );

  test('native plaintext notifications work without a key exchange', () async {
    final endpoint = Completer<int>();
    final packets = <LanRpcPacket>[];
    final errors = <String>[];
    final rpc = await LanGameRpc.start(
      onEndpoint: endpoint.complete,
      onPacket: packets.add,
      onError: errors.add,
    );
    addTearDown(rpc.close);
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, rpc.port);
    addTearDown(socket.destroy);
    final reply = socket.first;
    socket.add([
      ..._frame(_body(273, [42, 0, 0, 0])),
      ..._frame(_body(4612, [0, 0])),
      ..._frame(_body(518, [0, 0, 0, 0x39, 0x4a, 0, 0])),
    ]);
    expect(await _bounded(endpoint.future), 19001);
    expect(packets.map((packet) => packet.command), [273, 4612, 518]);
    expect(rpc.connected, isTrue);
    expect(rpc.refreshPlayers(), isTrue);
    expect(await _bounded(reply), _frame(_body(272, [])));
    expect(errors, isEmpty);
  });

  test('unknown framed notifications keep the game connection open', () async {
    final unknown = Completer<LanRpcPacket>();
    final endpoint = Completer<int>();
    final errors = <String>[];
    final rpc = await LanGameRpc.start(
      onEndpoint: endpoint.complete,
      onPacket: (packet) {
        if (packet.command == 65530) unknown.complete(packet);
      },
      onError: errors.add,
    );
    addTearDown(rpc.close);
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, rpc.port);
    addTearDown(socket.destroy);
    socket.add(_frame(_body(65530, [9, 7])));
    expect((await _bounded(unknown.future)).payload, [9, 7]);
    expect(rpc.connected, isTrue);
    socket.add(_frame(_body(518, [0, 0, 0, 0x39, 0x4a, 0, 0])));
    expect(await _bounded(endpoint.future), 19001);
    expect(errors, isEmpty);
  });

  test('plaintext ready can precede an optional cipher handshake', () async {
    final endpoint = Completer<int>();
    final ready = Completer<void>();
    final rpc = await LanGameRpc.start(
      onEndpoint: endpoint.complete,
      onPacket: (packet) {
        if (packet.command == 261) ready.complete();
      },
    );
    addTearDown(rpc.close);
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, rpc.port);
    addTearDown(socket.destroy);
    socket.add(_frame(_body(261, [0, 0])));
    await _bounded(ready.future);
    expect(rpc.connected, isTrue);
    socket.add([
      ..._handshake(),
      ..._encrypted(_gameCipher(), 518, [0, 0, 0, 0x39, 0x4a, 0, 0]),
    ]);
    expect(await _bounded(endpoint.future), 19001);
  });

  test('invalid handshake is rejected without printing key data', () async {
    final error = Completer<String>();
    final rpc = await LanGameRpc.start(onError: error.complete);
    addTearDown(rpc.close);
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, rpc.port);
    addTearDown(socket.destroy);
    socket.add(_frame(_body(0, [0, 0, 2, 0, 0x12, 0x34])));
    expect(
      await _bounded(error.future),
      '游戏控制连接返回了无效数据（command=0, body.length=8, tokenLength=2）。',
    );
    expect(rpc.connected, isFalse);
    expect(rpc.endpoint, isNull);
  });

  test(
    'failed or invalid launch responses never publish an endpoint',
    () async {
      final responses = Completer<void>();
      var packets = 0;
      final endpoints = <int>[];
      final rpc = await LanGameRpc.start(
        onEndpoint: endpoints.add,
        onPacket: (_) {
          if (++packets == 4) responses.complete();
        },
      );
      addTearDown(rpc.close);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        rpc.port,
      );
      addTearDown(socket.destroy);
      final cipher = _gameCipher();
      socket.add([
        ..._handshake(),
        ..._encrypted(cipher, 518, [0, 0, 1, 0x39, 0x4a, 0, 0]),
        ..._encrypted(cipher, 518, [0, 0, 0, 0, 0, 0, 0]),
        ..._encrypted(cipher, 518, [0, 0, 0, 0, 0, 1, 0]),
        ..._encrypted(cipher, 518, [0, 0, 0]),
      ]);
      await _bounded(responses.future);
      expect(endpoints, isEmpty);
      expect(rpc.endpoint, isNull);
    },
  );

  test('two games have independent listeners and cipher positions', () async {
    final ports = [Completer<int>(), Completer<int>()];
    final servers = <LanGameRpc>[];
    for (var index = 0; index < 2; index++) {
      final rpc = await LanGameRpc.start(onEndpoint: ports[index].complete);
      servers.add(rpc);
      addTearDown(rpc.close);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        rpc.port,
      );
      addTearDown(socket.destroy);
      final cipher = _gameCipher();
      socket.add([
        ..._handshake(),
        if (index == 1) ..._encrypted(cipher, 123, List.filled(72, 0)),
        ..._encrypted(cipher, 518, [0, 0, 0, 0x39 + index, 0x4a, 0, 0]),
      ]);
    }
    expect(await _bounded(ports[0].future), 19001);
    expect(await _bounded(ports[1].future), 19002);
    await servers[0].close();
    expect(servers[0].connected, isFalse);
    expect(servers[1].connected, isTrue);
  });
}
