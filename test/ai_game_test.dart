import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/ai_game_io.dart';

class Peer {
  Peer(this.socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            messages.add(jsonDecode(line) as Map<String, dynamic>);
          },
          onDone: _finish,
          onError: (Object _) => _finish(),
        );
  }
  final Socket socket;
  final messages = <Map<String, dynamic>>[];
  bool closed = false;
  final finished = Completer<void>();
  void _finish() {
    closed = true;
    if (!finished.isCompleted) finished.complete();
  }

  void send(Map<String, dynamic> data) => socket.write('${jsonEncode(data)}\n');
  Future<Map<String, dynamic>> wait(
    bool Function(Map<String, dynamic>) test,
  ) async {
    for (var i = 0; i < 100; i++) {
      final found = messages.where(test).lastOrNull;
      if (found != null) return found;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('No expected message: $messages');
  }
}

void main() {
  test(
    'fixed action schema excludes nonfinite values, unknown fields and unbounded holds',
    () {
      expect(
        validAiAction({
          'op': 'move',
          'left': 0,
          'forward': 1,
          'duration_ms': 300,
        }),
        true,
      );
      expect(
        validAiAction({
          'op': 'move',
          'left': 0,
          'forward': 1,
          'duration_ms': 9000,
        }),
        false,
      );
      expect(
        validAiAction({'op': 'look', 'pitch': double.nan, 'yaw': 90}),
        false,
      );
      expect(validAiAction({'op': 'jump', 'code': 'arbitrary()'}), false);
      expect(validAiAction({'op': 'eval', 'code': 'arbitrary()'}), false);
    },
  );

  test(
    'framing, authentication, readiness, dedup, epoch, lease and cleanup',
    () async {
      final directory = await Directory.systemTemp.createTemp('mcdev-ai-test-');
      final bridge = await AiGameBridge.start(directory.path);
      final sockets = <Socket>[];
      Future<Peer> connect(String role, String token) async {
        final socket = await Socket.connect('127.0.0.1', bridge.port);
        sockets.add(socket);
        final peer = Peer(socket);
        peer.send({
          'type': 'hello',
          'role': role,
          'protocol': 1,
          'token': token,
          'epoch': 'world-1',
        });
        return peer;
      }

      try {
        final bad = await connect('game', 'wrong');
        await bad.finished.future.timeout(const Duration(seconds: 3));
        expect(bad.closed, true);
        final game = await connect('game', bridge.gameToken);
        await game.wait((x) => x['type'] == 'control');
        final agent = await connect('agent', bridge.token);
        await agent.wait((x) => x['type'] == 'welcome');
        game.send({
          'type': 'observation',
          'epoch': 'world-1',
          'world_ready': false,
          'seq': 1,
        });
        await agent.wait((x) => x['type'] == 'observation');
        agent.send({'type': 'claim', 'epoch': 'world-1'});
        await agent.wait((x) => x['reason'] == 'game_not_ready_or_stale_epoch');
        game.send({
          'type': 'observation',
          'epoch': 'world-1',
          'world_ready': true,
          'seq': 2,
        });
        await agent.wait((x) => x['seq'] == 2);
        agent.send({'type': 'claim', 'epoch': 'world-1'});
        final claim = await agent.wait((x) => x['type'] == 'claimed');
        final action = {
          'type': 'action',
          'epoch': 'world-1',
          'generation': claim['generation'],
          'id': 'a1',
          'action': {'op': 'look', 'pitch': 0, 'yaw': 90},
        };
        final encoded = jsonEncode(action);
        agent.socket.write(encoded.substring(0, encoded.length - 2));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(game.messages.where((x) => x['type'] == 'action'), isEmpty);
        agent.socket.write('${encoded.substring(encoded.length - 2)}\n');
        final forwarded = await game.wait((x) => x['id'] == 'a1');
        expect(
          forwarded['not_after_ms'],
          greaterThan(DateTime.now().millisecondsSinceEpoch),
        );
        agent.send(action);
        await agent.wait((x) => x['id'] == 'a1' && x['status'] == 'forwarded');
        expect(game.messages.where((x) => x['type'] == 'action').length, 1);
        agent.send({
          ...action,
          'action': {'op': 'jump'},
        });
        await agent.wait((x) => x['reason'] == 'id_conflict');
        agent.send({...action, 'id': 'old', 'epoch': 'previous-world'});
        await agent.wait(
          (x) =>
              x['id'] == 'old' &&
              x['reason'] == 'stale_epoch_generation_or_lease',
        );
        game.send({
          'type': 'receipt',
          'epoch': 'world-1',
          'generation': claim['generation'],
          'id': 'a1',
          'status': 'completed',
        });
        await agent.wait((x) => x['id'] == 'a1' && x['status'] == 'completed');
        // Disconnect revokes the generation even if the game is still live.
        agent.socket.destroy();
        final stopped = await game.wait(
          (x) =>
              x['type'] == 'control' &&
              x['enabled'] == false &&
              x['generation'] > claim['generation'],
        );
        expect(stopped['valid_until_ms'], 0);
        final quiescing = bridge.suspend();
        final shutdown = await game.wait((x) => x['type'] == 'shutdown');
        game.send({'type': 'shutdown_ack', 'epoch': shutdown['epoch']});
        expect(await quiescing, true);
        expect(bridge.ready, false);
        await bridge.close();
        expect(await bridge.descriptor.exists(), false);
      } finally {
        for (final socket in sockets) {
          socket.destroy();
        }
        await bridge.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
