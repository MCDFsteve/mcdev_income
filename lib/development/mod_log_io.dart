import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mod_log_filter.dart';

/// MCS's separate UTF-8 developer log channel (`loggingIP` / `loggingPort`).
/// The launcher-control RPC and the game's native stdout are not mod logs.
class ModLogServer {
  ModLogServer._(
    this._server,
    this._onText,
    this._marker,
    this._sources,
    this._onNativeLine,
  );

  final ServerSocket _server;
  final void Function(String) _onText;
  final String _marker;
  final ModLogSources _sources;
  final void Function(String)? _onNativeLine;
  final Set<Socket> _peers = {};
  final Map<Socket, ModLogDecoder> _decoders = {};
  final Map<Socket, ModLogFilter> _filters = {};
  final Map<Socket, Completer<void>> _finished = {};
  Future<void>? _closing;
  bool _closed = false;

  int get port => _server.port;

  static Future<ModLogServer> start({
    required void Function(String) onText,
    required String marker,
    required ModLogSources sources,
    void Function(String)? onNativeLine,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final logs = ModLogServer._(server, onText, marker, sources, onNativeLine);
    server.listen(logs._accept, onError: (Object _) {});
    return logs;
  }

  void _accept(Socket peer) {
    if (_closed ||
        _closing != null ||
        !peer.remoteAddress.isLoopback ||
        _peers.length >= 4) {
      peer.destroy();
      return;
    }
    _peers.add(peer);
    _finished[peer] = Completer<void>();
    final filter = ModLogFilter(
      marker: _marker,
      sources: _sources,
      onText: (text) {
        if (!_closed) _onText(text);
      },
    );
    var nativeTail = '';
    final decoder = ModLogDecoder((text) {
      filter.add(text);
      if (_onNativeLine == null) return;
      final lines = '$nativeTail$text'.split('\n');
      nativeTail = lines.removeLast();
      if (nativeTail.length > 65536) nativeTail = '';
      for (final line in lines) {
        _onNativeLine(line);
      }
    });
    _filters[peer] = filter;
    _decoders[peer] = decoder;
    void finish() {
      _decoders.remove(peer)?.close();
      _filters.remove(peer)?.close();
      _peers.remove(peer);
      _finished.remove(peer)?.complete();
      peer.destroy();
    }

    peer.listen(decoder.add, onDone: finish, onError: (Object _) => finish());
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await _server.close();
    // Process.exitCode can complete before TCP's final bytes / FIN reach the
    // Dart listener. Give existing peers a bounded drain before flushing them.
    if (_finished.isNotEmpty) {
      try {
        await Future.wait(
          _finished.values.map((done) => done.future).toList(),
        ).timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        // A peer that stays connected must not prevent stopping a game.
      }
    }
    // Flush incomplete UTF-8 before disabling callbacks / closing the writer.
    for (final decoder in _decoders.values) {
      decoder.close();
    }
    _decoders.clear();
    for (final filter in _filters.values) {
      filter.close();
    }
    _filters.clear();
    _closed = true;
    for (final peer in _peers.toList()) {
      peer.destroy();
    }
    _peers.clear();
  }
}

/// Commands enclosed in 0xff are profiler/control data, never log text.
/// Parsing bytes first preserves UTF-8 and markers split across TCP reads.
class ModLogDecoder {
  ModLogDecoder(void Function(String) onText)
    : _text = const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(StringConversionSink.from(_LogTextSink(onText)));

  final ByteConversionSink _text;
  bool _command = false;
  bool _closed = false;

  void add(List<int> bytes) {
    if (_closed) return;
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 255) continue;
      if (!_command && i > start) _text.add(bytes.sublist(start, i));
      _command = !_command;
      start = i + 1;
    }
    if (!_command && start < bytes.length) _text.add(bytes.sublist(start));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _text.close();
  }
}

class _LogTextSink implements Sink<String> {
  _LogTextSink(this.onText);
  final void Function(String) onText;
  @override
  void add(String data) => onText(data);
  @override
  void close() {}
}
