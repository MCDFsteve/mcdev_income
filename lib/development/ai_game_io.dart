import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;

/// Local, explicitly enabled bridge for the current embedded player.
/// Separate game/agent credentials; a single controller owns a two-second lease.
class AiGameBridge {
  AiGameBridge._(this._server, this.descriptor, this.token, this.gameToken) {
    _server.listen(_accept);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  final ServerSocket _server;
  final File descriptor;
  final String token;
  final String gameToken;
  late final Timer _timer;
  final Set<_Peer> _peers = {};
  _Peer? _game;
  _Peer? _controller;
  String? epoch;
  int generation = 0;
  Map<String, dynamic>? observation;
  DateTime? _observedAt;
  DateTime? _lease;
  DateTime? _controlSent;
  int _hz = 5;
  bool _closed = false;
  bool _suspended = false;
  Completer<void>? _shutdownAck;
  int _eventSequence = 0;
  final Map<String, String> _actions = {};
  final Map<String, Map<String, dynamic>> _receipts = {};
  final _actionBudget = _Budget(16, 16);
  final _byteBudget = _Budget(7 * 1024, 8 * 1024);
  bool get ready =>
      !_closed &&
      !_suspended &&
      _game != null &&
      observation != null &&
      observation!['world_ready'] == true &&
      DateTime.now().difference(_observedAt!) < const Duration(seconds: 2);
  int get port => _server.port;
  Map<String, String> get environment => {
    'MCDEV_AI_PORT': '$port',
    'MCDEV_AI_GAME_TOKEN': gameToken,
  };

  static Future<AiGameBridge> start(String directory) async {
    String secret() => List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final file = File(p.join(directory, 'ai-game.json'));
    final bridge = AiGameBridge._(server, file, secret(), secret());
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'protocol': 1,
          'host': '127.0.0.1',
          'port': server.port,
          'token': bridge.token,
          'transport': 'ndjson',
          'max_frame_bytes': 16384,
        }),
        flush: true,
      );
      if (!Platform.isWindows) {
        final mode = await Process.run('/bin/chmod', ['600', file.path]);
        if (mode.exitCode != 0) {
          throw FileSystemException('Cannot protect AI descriptor', file.path);
        }
      }
      return bridge;
    } catch (_) {
      await bridge.close();
      rethrow;
    }
  }

  void _accept(Socket socket) {
    if (_closed || _peers.length >= 4) {
      socket.destroy();
      return;
    }
    final peer = _Peer(socket);
    _peers.add(peer);
    peer.onMessage = (data) => _message(peer, data);
    peer.onClose = () {
      _peers.remove(peer);
      if (identical(peer, _controller)) {
        _controller = null;
        stop();
      }
      if (identical(peer, _game)) {
        _game = null;
        observation = null;
        stop();
        _controller?.send({
          'type': 'status',
          'ready': false,
          'reason': 'game_disconnected',
        });
      }
    };
    peer.listen();
  }

  void _message(_Peer peer, Map<String, dynamic> data) {
    if (peer.role == null) {
      if (data['type'] != 'hello' || data['protocol'] != 1) {
        peer.close();
        return;
      }
      if (data['role'] == 'game' &&
          data['token'] == gameToken &&
          _game == null &&
          data['epoch'] is String) {
        _game = peer;
        peer.role = 'game';
        epoch = data['epoch'] as String;
        generation++;
        _actions.clear();
        _receipts.clear();
        observation = null;
        _lease = null;
        _sendControl();
      } else if (data['role'] == 'agent' &&
          data['token'] == token &&
          _controller == null) {
        _controller = peer;
        peer.role = 'agent';
        peer.send({
          'type': 'welcome',
          'protocol': 1,
          'epoch': epoch,
          'generation': generation,
          'ready': ready,
          'lease_ms': 2000,
          'max_pending': 8,
          'max_frame_bytes': 16384,
        });
        if (observation != null) peer.send(observation!);
      } else {
        peer.close();
      }
      return;
    }
    if (peer.role == 'game') {
      if (data['epoch'] != epoch) {
        peer.close();
        return;
      }
      switch (data['type']) {
        case 'shutdown_ack':
          if (!(_shutdownAck?.isCompleted ?? true)) _shutdownAck!.complete();
        case 'observation':
          observation = data;
          _observedAt = DateTime.now();
          _controller?.send(data, state: true);
        case 'events':
          final events = data['events'];
          if (events is List) {
            _controller?.send({
              ...data,
              'events': [
                for (final event in events.take(64))
                  if (event is Map<String, dynamic>)
                    {
                      ...event,
                      'game_event_seq': event['event_seq'],
                      'event_seq': ++_eventSequence,
                    },
              ],
            });
          }
        case 'receipt':
          final id = data['id'];
          if (data['generation'] == generation &&
              id is String &&
              _actions.containsKey(id)) {
            _receipts[id] = data;
            _controller?.send(data);
          }
      }
      return;
    }
    void reject(String reason) =>
        peer.send({'type': 'error', 'id': data['id'], 'reason': reason});
    switch (data['type']) {
      case 'observe':
        if (observation != null) peer.send(observation!);
      case 'claim':
        if (!ready || data['epoch'] != epoch) {
          reject('game_not_ready_or_stale_epoch');
          return;
        }
        stop();
        _lease = DateTime.now().add(const Duration(seconds: 2));
        _hz = [2, 5, 10].contains(data['hz']) ? data['hz'] as int : 5;
        _sendControl();
        peer.send({
          'type': 'claimed',
          'epoch': epoch,
          'generation': generation,
        });
      case 'heartbeat':
        if (data['epoch'] == epoch &&
            data['generation'] == generation &&
            _lease != null &&
            DateTime.now().isBefore(_lease!)) {
          _lease = DateTime.now().add(const Duration(seconds: 2));
        } else {
          reject('lease_expired_or_stale_generation');
        }
      case 'stop':
        // Stop is always allowed for the authenticated controller.
        stop();
      case 'action':
        if (!ready ||
            _lease == null ||
            !DateTime.now().isBefore(_lease!) ||
            data['epoch'] != epoch ||
            data['generation'] != generation) {
          reject('stale_epoch_generation_or_lease');
          return;
        }
        final id = data['id'];
        final action = data['action'];
        final ttl = data['ttl_ms'] ?? 1000;
        if (id is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ||
            action is! Map<String, dynamic> ||
            !validAiAction(action) ||
            ttl is! int ||
            ttl < 1 ||
            ttl > 2000) {
          reject('invalid_action');
          return;
        }
        final canonical = jsonEncode(action);
        if (_actions.containsKey(id)) {
          if (_actions[id] != canonical) {
            reject('id_conflict');
            return;
          }
          peer.send(
            _receipts[id] ??
                {
                  'type': 'receipt',
                  'id': id,
                  'epoch': epoch,
                  'generation': generation,
                  'status': 'forwarded',
                },
          );
          return;
        }
        final pending = _actions.keys
            .where(
              (id) => !const {
                'completed',
                'failed',
                'rejected',
                'expired',
                'cancelled',
                'lease_expired',
                'disconnected',
              }.contains(_receipts[id]?['status']),
            )
            .length;
        final request = {
          'type': 'action',
          'epoch': epoch,
          'generation': generation,
          'id': id,
          'ttl_ms': ttl,
          'not_after_ms': DateTime.now().millisecondsSinceEpoch + ttl,
          'action': action,
        };
        final size = utf8.encode(jsonEncode(request)).length + 1;
        if (pending >= 8 ||
            _actions.length >= 4096 ||
            size > 1024 ||
            !_actionBudget.take(1) ||
            !_byteBudget.take(size.toDouble())) {
          reject('action_budget_exceeded');
          return;
        }
        _actions[id] = canonical;
        _game!.send(request);
      default:
        reject('unknown_message');
    }
  }

  void _sendControl() {
    _game?.send({
      'type': 'control',
      'epoch': epoch,
      'generation': generation,
      'enabled': _lease != null,
      'valid_until_ms': _lease?.millisecondsSinceEpoch ?? 0,
      'hz': _hz,
    });
    _controlSent = DateTime.now();
  }

  void _tick() {
    final now = DateTime.now();
    for (final peer in _peers.toList()) {
      if (peer.role == null && now.difference(peer.created).inSeconds >= 3) {
        peer.close();
      }
    }
    if (_lease != null && (!now.isBefore(_lease!) || !ready)) {
      stop(reason: !ready ? 'observation_stale_or_loading' : 'lease_expired');
    }
    if (_lease != null &&
        (_controlSent == null ||
            now.difference(_controlSent!).inMilliseconds >= 750)) {
      _sendControl();
    }
  }

  void stop({String reason = 'cancelled'}) {
    _lease = null;
    generation++;
    for (final id in _actions.keys) {
      if (!{
        'completed',
        'failed',
        'rejected',
        'expired',
      }.contains(_receipts[id]?['status'])) {
        _controller?.send({
          'type': 'receipt',
          'id': id,
          'epoch': epoch,
          'generation': generation - 1,
          'status': 'cancelled',
          'detail': reason,
        });
      }
    }
    _actions.clear();
    _receipts.clear();
    _sendControl();
    _controller?.send({
      'type': 'stopped',
      'epoch': epoch,
      'generation': generation,
    });
  }

  /// Quiesce all SDK reads on the game thread before destroying its world.
  Future<bool> suspend() async {
    if (_suspended) return _shutdownAck?.isCompleted ?? false;
    _suspended = true;
    stop(reason: 'game_stopping');
    if (_game == null) return false;
    _shutdownAck = Completer<void>();
    _game!.send({'type': 'shutdown', 'epoch': epoch, 'generation': generation});
    try {
      await _shutdownAck!.future.timeout(const Duration(seconds: 2));
      return true;
    } on TimeoutException {
      // A paused/exited game cannot acknowledge; its existing lease still expires.
      return false;
    }
  }

  /// Already-filtered developer output; never forward launcher credentials.
  void addModLog(String value) {
    if (_controller == null || epoch == null) return;
    final truncated = value.length > 1500;
    _controller?.send({
      'type': 'events',
      'epoch': epoch,
      'events': [
        {
          'kind': 'mod_log',
          'event_seq': ++_eventSequence,
          'data': {
            'text': truncated ? value.substring(0, 1500) : value,
            'truncated': truncated,
          },
        },
      ],
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    stop();
    _timer.cancel();
    for (final peer in _peers.toList()) {
      peer.close();
    }
    await _server.close();
    try {
      await descriptor.delete();
    } on FileSystemException {
      /* already removed */
    }
  }
}

bool validAiAction(Map<String, dynamic> action) {
  final fields = switch (action['op']) {
    'move' => {'op', 'left', 'forward', 'duration_ms'},
    'look' => {'op', 'pitch', 'yaw'},
    'jump' => {'op'},
    'wait' => {'op', 'duration_ms'},
    'select_slot' => {'op', 'slot'},
    'use' => {'op', 'duration_ms'},
    'dig' => {'op', 'x', 'y', 'z', 'face', 'duration_ms'},
    'place' => {'op', 'x', 'y', 'z', 'face'},
    'attack' => {'op', 'entity_id'},
    'craft' => {'op', 'recipe'},
    _ => <String>{},
  };
  if (fields.isEmpty ||
      action.keys.toSet().difference(fields).isNotEmpty ||
      fields.difference(action.keys.toSet()).isNotEmpty) {
    return false;
  }
  for (final name in fields.where((f) => f != 'op')) {
    if (name == 'entity_id') {
      final id = action[name];
      if (id is! String || !RegExp(r'^-?[0-9]{1,20}$').hasMatch(id)) {
        return false;
      }
      continue;
    }
    if (name == 'recipe') {
      if (!const {'oak_planks', 'crafting_table'}.contains(action[name])) {
        return false;
      }
      continue;
    }
    final range = switch (name) {
      'left' || 'forward' => (-1, 1),
      'duration_ms' => (1, action['op'] == 'dig' ? 5000 : 1500),
      'pitch' => (-90, 90),
      'slot' => (0, 8),
      'face' => (0, 5),
      'x' || 'z' => (-30000000, 30000000),
      'y' => (-512, 4096),
      _ => (-180, 180),
    };
    final value = action[name];
    if ({'slot', 'face', 'x', 'y', 'z'}.contains(name) && value is! int) {
      return false;
    }
    if (value is! num ||
        !value.isFinite ||
        value < range.$1 ||
        value > range.$2) {
      return false;
    }
  }
  return true;
}

class _Budget {
  _Budget(this.rate, this.capacity) : tokens = capacity;
  final double rate, capacity;
  double tokens;
  DateTime updated = DateTime.now();
  bool take(double amount) {
    final now = DateTime.now();
    tokens = min(
      capacity,
      tokens + now.difference(updated).inMicroseconds / 1e6 * rate,
    );
    updated = now;
    if (tokens < amount) return false;
    tokens -= amount;
    return true;
  }
}

class _Peer {
  _Peer(this.socket);
  final Socket socket;
  final DateTime created = DateTime.now();
  String? role;
  late void Function(Map<String, dynamic>) onMessage;
  late void Function() onClose;
  final List<int> _input = [];
  final List<List<int>> _queue = [];
  List<int>? _state;
  bool _writing = false, _closed = false;
  final _Budget _incoming = _Budget(128 * 1024, 256 * 1024);
  void listen() {
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.listen(
      (chunk) {
        if (!_incoming.take(chunk.length.toDouble())) {
          close();
          return;
        }
        for (final byte in chunk) {
          if (byte == 10) {
            try {
              final data = jsonDecode(utf8.decode(_input));
              _input.clear();
              if (data is! Map<String, dynamic>) {
                close();
                return;
              }
              onMessage(data);
              if (_closed) return;
            } catch (_) {
              close();
              return;
            }
          } else {
            _input.add(byte);
            if (_input.length > 16384) {
              close();
              return;
            }
          }
        }
      },
      onDone: close,
      onError: (Object _) => close(),
      cancelOnError: true,
    );
  }

  void send(Map<String, dynamic> data, {bool state = false}) {
    if (_closed) return;
    final bytes = utf8.encode('${jsonEncode(data)}\n');
    if (bytes.length > 16384) {
      close();
      return;
    }
    if (state) {
      _state = bytes;
    } else {
      _queue.add(bytes);
    }
    if (_queue.fold<int>(0, (sum, x) => sum + x.length) > 32768) {
      close();
      return;
    }
    if (!_writing) unawaited(_drain());
  }

  Future<void> _drain() async {
    _writing = true;
    try {
      while (!_closed && (_queue.isNotEmpty || _state != null)) {
        final bytes = _queue.isNotEmpty ? _queue.removeAt(0) : _state!;
        if (identical(bytes, _state)) _state = null;
        socket.add(bytes);
        await socket.flush().timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      close();
    } finally {
      _writing = false;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    socket.destroy();
    _queue.clear();
    _state = null;
    onClose();
  }
}
