import 'dart:io';
import 'dart:typed_data';

/// The game's local launcher-control channel. Its port is not the LAN port.
///
/// Framing and the optional key exchange follow MCStudio.Network.GameControl.RPC.
/// Current Bedrock builds also send these framed messages in plaintext.
/// The native ChaCha8 implementation uses the nonce `163 NetEase\n` and keeps
/// its stream position between messages (including non-block-aligned ones).
class LanGameRpc {
  LanGameRpc._(this._server, this._onEndpoint, this._onPacket, this._onError);

  final ServerSocket _server;
  final void Function(int)? _onEndpoint;
  final void Function(LanRpcPacket)? _onPacket;
  final void Function(String)? _onError;
  final Set<_LanRpcPeer> _peers = {};
  _LanRpcPeer? _active;
  bool _closed = false;
  int? _endpoint;

  int get port => _server.port;
  int? get endpoint => _endpoint;
  bool get connected => _active != null;

  static Future<LanGameRpc> start({
    void Function(int port)? onEndpoint,
    void Function(LanRpcPacket packet)? onPacket,
    void Function(String safeMessage)? onError,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final rpc = LanGameRpc._(server, onEndpoint, onPacket, onError);
    server.listen(
      rpc._accept,
      onError: (_) {
        if (!rpc._closed) rpc._onError?.call('游戏控制连接无法监听。');
      },
    );
    return rpc;
  }

  void _accept(Socket socket) {
    if (_closed || !socket.remoteAddress.isLoopback || _peers.length >= 4) {
      socket.destroy();
      return;
    }
    final peer = _LanRpcPeer(socket, this);
    _peers.add(peer);
    peer.start();
  }

  void _activate(_LanRpcPeer peer) {
    // Reconnection replaces the old stream and its cipher state.
    final old = _active;
    _active = peer;
    if (old != null && old != peer) old.close();
  }

  void _receive(_LanRpcPeer peer, LanRpcPacket packet) {
    if (_active != peer || _closed) return;
    // LaunchGame = short GameID, byte ErrCode, int Port, in little endian.
    // The success response is evidence of the bound game port; never use
    // launcher_port or a globally guessed 19132 port to connect a guest.
    if (packet.command == 518 && packet.payload.length == 7) {
      final bytes = ByteData.sublistView(packet.payload);
      final result = bytes.getUint8(2);
      final gamePort = bytes.getInt32(3, Endian.little);
      if (result == 0 && gamePort > 0 && gamePort <= 65535) {
        _endpoint = gamePort;
        _onEndpoint?.call(gamePort);
      }
    }
    _onPacket?.call(packet);
  }

  /// Sends a documented control command; callers must encode its payload.
  /// Returns false until the game has sent a valid control packet.
  bool send(int command, [List<int> payload = const []]) {
    if (_closed || command < 0 || command > 65535 || payload.length > 65533) {
      return false;
    }
    return _active?.send(command, payload) ?? false;
  }

  /// Legacy GetPlayersReq. Some Bedrock releases do not implement this command;
  /// callers must only show a roster confirmed by a response or a world bridge.
  bool refreshPlayers() => send(272);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final peer in _peers.toList()) {
      peer.close();
    }
    _active = null;
    await _server.close();
  }
}

class LanRpcPacket {
  const LanRpcPacket(this.command, this.payload);

  final int command;

  /// Contains local game data. Do not include this in diagnostic logs: some
  /// official messages contain access tokens or private account information.
  final Uint8List payload;
}

class _LanRpcPeer {
  _LanRpcPeer(this.socket, this.owner);

  final Socket socket;
  final LanGameRpc owner;
  final List<int> _buffer = [];
  LanRpcChaCha8? _receiveCipher;
  LanRpcChaCha8? _sendCipher;
  bool _closed = false;
  bool _active = false;

  void start() {
    // Native Bedrock may remain silent while loading or waiting in a menu.
    // Closing an idle launcher channel can terminate the game. The owning
    // launch session closes it; loopback peers and frame sizes are bounded.
    socket.listen(_receive, onError: (_) => close(), onDone: close);
  }

  void _receive(Uint8List chunk) {
    if (_closed) return;
    // Consume chunks incrementally so multiple valid 64 KiB frames in a single
    // TCP read are accepted, without buffering an unbounded malicious stream.
    var cursor = 0;
    try {
      while (cursor < chunk.length) {
        if (_buffer.length < 2) {
          _buffer.add(chunk[cursor++]);
          continue;
        }
        final length = _buffer[0] | (_buffer[1] << 8);
        if (length < 2) throw const FormatException();
        final needed = length + 2 - _buffer.length;
        final available = chunk.length - cursor;
        final take = needed < available ? needed : available;
        _buffer.addAll(chunk.sublist(cursor, cursor + take));
        cursor += take;
        if (_buffer.length == length + 2) {
          final body = Uint8List.fromList(_buffer.sublist(2));
          _buffer.clear();
          _receiveCipher?.process(body);
          final data = ByteData.sublistView(body);
          final command = data.getUint16(0, Endian.little);
          if (_receiveCipher == null && command == 0) {
            // Optional ConnectMsg: short game id, ushort key length, 32 bytes.
            if (body.length != 38 || data.getUint16(4, Endian.little) != 32) {
              throw FormatException(_safeFrameDiagnostic(command, body));
            }
            final key = body.sublist(6);
            _sendCipher = LanRpcChaCha8(key);
            _receiveCipher = LanRpcChaCha8([
              ...key.sublist(16),
              ...key.sublist(0, 16),
            ]);
            _activate();
          } else {
            // MCS accepts all ushort command IDs before the optional cipher
            // exchange. Newer games may add notifications unknown to us.
            if (!_active) _activate();
            owner._receive(this, LanRpcPacket(command, body.sublist(2)));
          }
        }
      }
    } on FormatException catch (error) {
      final detail = error.message.isEmpty ? '' : '（${error.message}）';
      owner._onError?.call('游戏控制连接返回了无效数据$detail。');
      close();
    }
  }

  static String _safeFrameDiagnostic(int command, Uint8List body) {
    final tokenLength = body.length >= 6
        ? ', tokenLength=${ByteData.sublistView(body).getUint16(4, Endian.little)}'
        : '';
    return 'command=$command, body.length=${body.length}$tokenLength';
  }

  void _activate() {
    _active = true;
    owner._activate(this);
  }

  bool send(int command, List<int> payload) {
    if (_closed || !_active) return false;
    final body = Uint8List(payload.length + 2);
    ByteData.sublistView(body).setUint16(0, command, Endian.little);
    body.setRange(2, body.length, payload);
    _sendCipher?.process(body);
    final frame = Uint8List(body.length + 2);
    ByteData.sublistView(frame).setUint16(0, body.length, Endian.little);
    frame.setRange(2, frame.length, body);
    socket.add(frame);
    return true;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    socket.destroy();
    _buffer.clear();
    owner._peers.remove(this);
    if (owner._active == this) owner._active = null;
  }
}

/// MCStudio's local RPC cipher, exposed for independent known-vector tests.
/// This cipher is protocol compatibility, not an authentication mechanism.
class LanRpcChaCha8 {
  LanRpcChaCha8(List<int> key) {
    if (key.length != 32 || key.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(key.length, 'key.length', 'Expected 32 bytes');
    }
    final bytes = ByteData.sublistView(Uint8List.fromList(key));
    _state.setRange(0, 4, [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]);
    for (var index = 0; index < 8; index++) {
      _state[index + 4] = bytes.getUint32(index * 4, Endian.little);
    }
    _state.setRange(12, 16, [0, 0x20333631, 0x4574654e, 0x0a657361]);
  }

  final Uint32List _state = Uint32List(16);
  final Uint8List _stream = Uint8List(64);
  int _offset = 64;

  void process(Uint8List bytes) {
    for (var index = 0; index < bytes.length; index++) {
      if (_offset == 64) _nextBlock();
      bytes[index] ^= _stream[_offset++];
    }
  }

  static int _rotate(int value, int shift) =>
      ((value << shift) | (value >> (32 - shift))) & 0xffffffff;

  static void _quarter(Uint32List x, int a, int b, int c, int d) {
    x[a] = x[a] + x[b];
    x[d] = _rotate(x[d] ^ x[a], 16);
    x[c] = x[c] + x[d];
    x[b] = _rotate(x[b] ^ x[c], 12);
    x[a] = x[a] + x[b];
    x[d] = _rotate(x[d] ^ x[a], 8);
    x[c] = x[c] + x[d];
    x[b] = _rotate(x[b] ^ x[c], 7);
  }

  void _nextBlock() {
    final x = Uint32List.fromList(_state);
    for (var round = 0; round < 4; round++) {
      _quarter(x, 0, 4, 8, 12);
      _quarter(x, 1, 5, 9, 13);
      _quarter(x, 2, 6, 10, 14);
      _quarter(x, 3, 7, 11, 15);
      _quarter(x, 0, 5, 10, 15);
      _quarter(x, 1, 6, 11, 12);
      _quarter(x, 2, 7, 8, 13);
      _quarter(x, 3, 4, 9, 14);
    }
    final bytes = ByteData.sublistView(_stream);
    for (var index = 0; index < 16; index++) {
      bytes.setUint32(index * 4, x[index] + _state[index], Endian.little);
    }
    _state[12]++;
    _offset = 0;
  }
}
