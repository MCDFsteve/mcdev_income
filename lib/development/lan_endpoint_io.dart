import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _rakNetMagic = <int>[
  0x00,
  0xff,
  0xff,
  0x00,
  0xfe,
  0xfe,
  0xfe,
  0xfe,
  0xfd,
  0xfd,
  0xfd,
  0xfd,
  0x12,
  0x34,
  0x56,
  0x78,
];

/// A loopback game endpoint confirmed by a RakNet response, not by process
/// existence. The returned port is always the queried port, never a redirect
/// obtained from an untrusted server's advertised metadata.
class LanEndpoint {
  const LanEndpoint({
    required this.port,
    required this.motd,
    required this.worldName,
    required this.playerCount,
    required this.maxPlayers,
    required this.version,
    required this.gameMode,
    this.hasMetadata = true,
  });

  final int port;
  final String motd;
  final String worldName;
  final int playerCount;
  final int maxPlayers;
  final String version;
  final String gameMode;

  /// Developer builds can return a bare RakNet pong with no world metadata.
  /// In that case the other descriptive fields are unknown, not evidence of
  /// an empty world. The launcher obtains membership from its server script.
  final bool hasMetadata;
}

typedef LanSocketRunner =
    Future<ProcessResult> Function(List<String> arguments);
typedef LanPortProbe =
    Future<LanEndpoint?> Function(
      int port, {
      required Duration timeout,
      required bool allowBarePong,
    });

/// Extract IPv4 UDP sockets that can receive a probe to 127.0.0.1 from lsof's
/// machine-readable output. The caller must query with -i4UDP so a wildcard
/// cannot refer to an IPv6-only listener. Connected peers and other local
/// interfaces cannot establish ownership of the probed loopback endpoint.
List<int> parseLanProcessPorts(String listing, int pid) {
  if (pid <= 0 || listing.length > 256 * 1024) return const [];
  final ports = <int>{};
  var matchingProcess = false;
  for (final line in const LineSplitter().convert(listing)) {
    if (line.startsWith('p')) {
      matchingProcess = int.tryParse(line.substring(1)) == pid;
      continue;
    }
    if (!matchingProcess || !line.startsWith('n')) continue;
    final address = line.substring(1);
    if (address.contains('->') || RegExp(r'\s').hasMatch(address)) continue;
    final separator = address.lastIndexOf(':');
    if (separator < 1) continue;
    final host = address.substring(0, separator);
    final number = address.substring(separator + 1);
    if (!RegExp(r'^[0-9]{1,5}$').hasMatch(number)) continue;
    if (host != '*' && host != '0.0.0.0' && host != '127.0.0.1') continue;
    final port = int.parse(number);
    if (port >= 1 && port <= 65535) ports.add(port);
  }
  return ports.toList(growable: false);
}

/// Queries exactly one macOS game PID, then probes only its IPv4 UDP ports
/// bound to loopback or all interfaces. No process-name search, global port scan,
/// or network discovery is performed. This handles versions that ignore
/// room_info.port while hosting.
Future<LanEndpoint?> discoverLanEndpointForProcess(
  int pid, {
  Duration timeout = const Duration(seconds: 6),
  Duration commandTimeout = const Duration(seconds: 2),
  Duration probeTimeout = const Duration(milliseconds: 350),
  LanSocketRunner? socketRunner,
  LanPortProbe? portProbe,
}) async {
  if (pid <= 0 ||
      timeout <= Duration.zero ||
      commandTimeout <= Duration.zero ||
      probeTimeout <= Duration.zero ||
      (!Platform.isMacOS && socketRunner == null)) {
    return null;
  }
  final watch = Stopwatch()..start();
  Duration remaining(Duration maximum) {
    final left = timeout - watch.elapsed;
    return left < maximum ? left : maximum;
  }

  try {
    final limit = remaining(commandTimeout);
    if (limit <= Duration.zero) return null;
    final args = ['-nP', '-a', '-p', '$pid', '-i4UDP', '-Fn'];
    final result =
        await (socketRunner != null
                ? socketRunner(args)
                : _runLsof(args, limit))
            .timeout(limit);
    if (result.exitCode != 0 || result.stdout is! String) return null;
    final ports = parseLanProcessPorts(result.stdout as String, pid);
    for (final port in ports) {
      final limit = remaining(probeTimeout);
      if (limit <= Duration.zero) break;
      LanEndpoint? endpoint;
      try {
        endpoint = await (portProbe ?? probeLanEndpoint)(
          port,
          timeout: limit,
          // These candidates came from the exact game process, permitting the
          // developer build's metadata-free pong without trusting other apps.
          allowBarePong: true,
        ).timeout(limit);
      } on TimeoutException {
        continue;
      } on SocketException {
        continue;
      }
      if (endpoint != null && endpoint.port == port) return endpoint;
    }
  } on ProcessException {
    return null;
  } on TimeoutException {
    return null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  return null;
}

Future<ProcessResult> _runLsof(List<String> args, Duration timeout) async {
  final process = await Process.start('/usr/sbin/lsof', args);
  var done = false;
  Future<String> read(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 256 * 1024) {
        throw const FormatException('Process socket listing too large');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  try {
    final results = await Future.wait<Object>([
      process.exitCode,
      read(process.stdout),
      read(process.stderr),
    ]).timeout(timeout);
    done = true;
    return ProcessResult(
      process.pid,
      results[0] as int,
      results[1],
      results[2],
    );
  } finally {
    if (!done) process.kill(ProcessSignal.sigkill);
  }
}

/// Selects a currently unoccupied loopback UDP port. The game must subsequently
/// bind it and be probed; bind-and-close alone cannot reserve it across launch.
Future<int> chooseAvailableLanPort() async {
  final socket = await RawDatagramSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    reuseAddress: false,
    reusePort: false,
  );
  final port = socket.port;
  // close() only schedules the native descriptor close. Wait for stream
  // completion so the game's immediate bind cannot race our own socket.
  final closed = socket.drain<void>();
  socket.close();
  await closed;
  return port;
}

/// Probes only the supplied local game port. No scanning or LAN broadcast.
/// A timeout or unsupported/non-Minecraft response returns null.
Future<LanEndpoint?> probeLanEndpoint(
  int port, {
  Duration timeout = const Duration(milliseconds: 500),
  bool allowBarePong = false,
}) async {
  RangeError.checkValueInInterval(port, 1, 65535, 'port');
  if (timeout <= Duration.zero) return null;
  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? subscription;
  Timer? timer;
  try {
    socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      reuseAddress: false,
      reusePort: false,
    );
    final activeSocket = socket;
    final result = Completer<LanEndpoint?>();
    final ping = Uint8List(33);
    final random = Random.secure();
    ping[0] = 1; // ID_UNCONNECTED_PING
    // A fresh opaque 64-bit echo token also avoids accepting a stale pong from
    // a previous probe; servers copy these eight timestamp bytes unchanged.
    for (var index = 1; index < 9; index++) {
      ping[index] = random.nextInt(256);
    }
    ping.setRange(9, 25, _rakNetMagic);
    for (var index = 25; index < 33; index++) {
      ping[index] = random.nextInt(256);
    }
    void finish(LanEndpoint? endpoint) {
      if (!result.isCompleted) result.complete(endpoint);
    }

    subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = activeSocket.receive()) != null) {
          final received = datagram!;
          if (received.address.address !=
                  InternetAddress.loopbackIPv4.address ||
              received.port != port) {
            continue;
          }
          final endpoint = _parsePong(
            received.data,
            ping,
            port,
            allowBarePong: allowBarePong,
          );
          if (endpoint != null) finish(endpoint);
        }
      },
      onError: (_) => finish(null),
      onDone: () => finish(null),
    );
    timer = Timer(timeout, () => finish(null));
    if (socket.send(ping, InternetAddress.loopbackIPv4, port) != ping.length) {
      return null;
    }
    return await result.future;
  } on SocketException {
    return null;
  } finally {
    timer?.cancel();
    await subscription?.cancel();
    socket?.close();
  }
}

LanEndpoint? _parsePong(
  Uint8List bytes,
  Uint8List ping,
  int port, {
  required bool allowBarePong,
}) {
  // ID, echoed time (8), server GUID (8), magic (16), string byte length (2).
  if (bytes.length < 33 || bytes[0] != 0x1c) return null;
  for (var index = 1; index < 9; index++) {
    if (bytes[index] != ping[index]) return null;
  }
  for (var index = 0; index < _rakNetMagic.length; index++) {
    if (bytes[index + 17] != _rakNetMagic[index]) return null;
  }
  if (bytes.length == 33 && allowBarePong) {
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
  }
  if (bytes.length < 35) return null;
  final length = ByteData.sublistView(bytes).getUint16(33, Endian.big);
  if (length > 4096 || length + 35 != bytes.length) return null;
  final String text;
  try {
    text = utf8.decode(bytes.sublist(35));
  } on FormatException {
    return null;
  }
  final fields = text.split(';');
  if (fields.length < 6 || fields[0] != 'MCPE') return null;
  final protocol = int.tryParse(fields[2]);
  final playerCount = int.tryParse(fields[4]);
  final maxPlayers = int.tryParse(fields[5]);
  if (protocol == null ||
      protocol <= 0 ||
      playerCount == null ||
      playerCount < 0 ||
      maxPlayers == null ||
      maxPlayers < 0) {
    return null;
  }
  return LanEndpoint(
    port: port,
    motd: fields[1],
    version: fields[3],
    playerCount: playerCount,
    maxPlayers: maxPlayers,
    worldName: fields.length > 7 ? fields[7] : fields[1],
    gameMode: fields.length > 8 ? fields[8] : '',
  );
}
