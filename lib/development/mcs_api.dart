import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'development_storage.dart';
import 'game_graphics.dart';

// Product protocol constants recovered from MCS 1.1.50.33254, never account secrets.
const _keys = [
  'MK6mipwmOUedplb6',
  'OtEylfId6dyhrfdn',
  'VNbhn5mvUaQaeOo9',
  'bIEoQGQYjKd02U0J',
  'fuaJrPwaH2cfXXLP',
  'LEkdyiroouKQ4XN1',
  'jM1h27H4UROu427W',
  'DhReQada7gZybTDk',
  'ZGXfpSTYUvcdKqdY',
  'AZwKf7MWZrJpGR5W',
  'amuvbcHw38TcSyPU',
  'SI4QotspbjhyFdT0',
  'VP4dhjKnDGlSJtbB',
  'UXDZx4KhZywQ2tcn',
  'NIK73ZNvNqzva4kd',
  'WeiW7qU766Q1YQZI',
];

String mcsDynamicToken(String resource, String body, {String token = ''}) {
  final session = md5.convert(utf8.encode(token)).toString();
  final digest = utf8.encode(
    md5.convert(utf8.encode('$session${body}0eGsBkhl$resource')).toString(),
  );
  final mixed = List<int>.generate(
    32,
    (i) => digest[i] ^ (((digest[i] << 6) | (digest[(i + 1) % 32] >> 2)) & 255),
  );
  return '${base64Encode(mixed).substring(0, 16)}1'
      .replaceAll('+', 'm')
      .replaceAll('/', 'o')
      .replaceAll('=', '');
}

class McsEnvelope {
  const McsEnvelope(this.bytes, this.key);
  final Uint8List bytes;
  final Uint8List key;
}

Uint8List _nonce() {
  const alphabet =
      'abdcefghijklmnprqstuvwzyx0123456789ABCDEFGHIJKLMNQPRTSVUWXYZ';
  final random = Random.secure();
  return Uint8List.fromList(
    List.generate(
      16,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ),
  );
}

McsEnvelope encryptMcsEnvelope(
  String body, {
  int? index,
  Uint8List? iv,
  Uint8List? key,
}) {
  index ??= Random.secure().nextInt(16);
  iv ??= _nonce();
  key ??= _nonce();
  if (index < 0 ||
      index >= 16 ||
      iv.length != 16 ||
      key.length != 16 ||
      body.contains('\u0000')) {
    throw const FormatException('Invalid MCS envelope');
  }
  final input = [...utf8.encode(body), ...key];
  final padded = Uint8List((input.length + 15) ~/ 16 * 16)..setAll(0, input);
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      true,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(utf8.encode(_keys[index]))),
        iv,
      ),
    );
  final output = Uint8List(padded.length);
  for (var i = 0; i < padded.length; i += 16) {
    cipher.processBlock(padded, i, output, i);
  }
  return McsEnvelope(
    Uint8List.fromList([...iv, ...output, (index << 4) | 2]),
    key,
  );
}

McsEnvelope decryptMcsEnvelope(Uint8List bytes) {
  if (bytes.length < 33 ||
      (bytes.length - 17) % 16 != 0 ||
      bytes.last & 15 != 2) {
    throw const FormatException('Invalid MCS response envelope');
  }
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      false,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(utf8.encode(_keys[bytes.last >> 4]))),
        bytes.sublist(0, 16),
      ),
    );
  final output = Uint8List(bytes.length - 17);
  for (var i = 0; i < output.length; i += 16) {
    cipher.processBlock(bytes, i + 16, output, i);
  }
  var end = output.length;
  while (end > 0 && output[end - 1] == 0) {
    end--;
  }
  if (end < 16) throw const FormatException('MCS correlation key missing');
  return McsEnvelope(
    output.sublist(0, end - 16),
    output.sublist(end - 16, end),
  );
}

class McsSession {
  const McsSession(
    this.id,
    this.token, {
    this.directToken = false,
    this.expiresAt = 0,
  });
  final String id;
  final String token;
  final bool directToken;
  final int expiresAt;
}

enum GameArchitecture {
  x64('x64'),
  x86('x86'),
  unknown('未标明架构');

  const GameArchitecture(this.label);
  final String label;
}

enum GameChannel {
  stable('稳定'),
  preview('预览'),
  beta('Beta'),
  test('测试');

  const GameChannel(this.label);
  final String label;
}

int compareGameVersions(String a, String b) {
  final av = a.split('.').map(int.parse).toList();
  final bv = b.split('.').map(int.parse).toList();
  for (var i = 0; i < max(av.length, bv.length); i++) {
    final compared = (i < av.length ? av[i] : 0).compareTo(
      i < bv.length ? bv[i] : 0,
    );
    if (compared != 0) return compared;
  }
  return 0;
}

class GamePackage {
  const GamePackage({
    required this.version,
    required this.patchUrl,
    required this.patchMd5,
    this.architecture = GameArchitecture.unknown,
    this.channels = const [],
    this.clientType = GameClientType.openGL,
    this.size = 0,
  });
  final String version;
  final Uri patchUrl;
  final String patchMd5;
  final GameArchitecture architecture;
  final List<GameChannel> channels;
  final GameClientType clientType;

  /// Official catalog size, not assumed to be the archive Content-Length.
  final int size;
  String get channelLabel => channels.isEmpty
      ? '其他版本'
      : channels.map((channel) => channel.label).join(' / ');
  Uri get zipUrl => patchUrl.replace(
    path:
        '${patchUrl.path.substring(0, patchUrl.path.length - '/patch.json'.length)}.zip',
  );
  static GamePackage fromCatalog(Map<String, dynamic> catalog) {
    final result = GameCatalog.fromJson(catalog).stable;
    if (result == null) {
      throw const DevelopmentStorageException('稳定版下载描述缺失或无效。');
    }
    return result;
  }
}

class GameCatalog {
  const GameCatalog({
    required this.packages,
    this.stableVersion,
    this.skippedEntries = 0,
  });
  final List<GamePackage> packages;
  final String? stableVersion;
  final int skippedEntries;
  GamePackage? get stable =>
      packages.where((package) => package.version == stableVersion).firstOrNull;

  static GameCatalog fromJson(Map<String, dynamic> catalog) {
    final entries = catalog['entities'];
    if (entries is! Map) throw const DevelopmentStorageException('游戏版本清单格式无效。');
    final packages = <GamePackage>[];
    var skipped = 0;
    const channels = {
      'stable': GameChannel.stable,
      'stable_new': GameChannel.preview,
      'beta': GameChannel.beta,
      'test': GameChannel.test,
    };
    for (final entry in entries.entries) {
      final version = entry.key.toString();
      // PCLauncher aliases describe launcher builds rather than game versions.
      if (!RegExp(r'^\d+(\.\d+){1,5}$').hasMatch(version)) continue;
      final data = entry.value;
      final uri = data is Map && data['url'] is String
          ? Uri.tryParse(data['url'])
          : null;
      if (data is! Map ||
          uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !uri.path.endsWith('/patch.json') ||
          data['md5'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(data['md5'])) {
        skipped++;
        continue;
      }
      final is64 =
          uri.path.contains('Win64') ||
          channels.keys.any(
            (key) =>
                catalog['${key}_x64'] == version ||
                catalog['${key}_haldra_x64'] == version,
          );
      final is32 =
          uri.path.contains('Win32') ||
          channels.keys.any((key) => catalog[key] == version);
      final architecture = uri.path.contains('Win64')
          ? GameArchitecture.x64
          : uri.path.contains('Win32')
          ? GameArchitecture.x86
          : is64
          ? GameArchitecture.x64
          : is32
          ? GameArchitecture.x86
          : GameArchitecture.unknown;
      packages.add(
        GamePackage(
          version: version,
          patchUrl: uri,
          patchMd5: data['md5'].toLowerCase(),
          architecture: architecture,
          clientType:
              channels.keys.any(
                    (key) => catalog['${key}_haldra_x64'] == version,
                  ) ||
                  RegExp(
                    r'haldra|renderdragon',
                    caseSensitive: false,
                  ).hasMatch(uri.path)
              ? GameClientType.haldra
              : GameClientType.openGL,
          channels: List.unmodifiable([
            for (final channel in channels.entries)
              if (catalog[architecture == GameArchitecture.x64
                          ? '${channel.key}_x64'
                          : channel.key] ==
                      version ||
                  (architecture == GameArchitecture.x64 &&
                      catalog['${channel.key}_haldra_x64'] == version))
                channel.value,
          ]),
          size: data['size'] is int && data['size'] > 0 ? data['size'] : 0,
        ),
      );
    }
    if (packages.isEmpty) {
      throw const DevelopmentStorageException('清单中没有有效的游戏下载版本。');
    }
    packages.sort((a, b) => compareGameVersions(b.version, a.version));
    return GameCatalog(
      packages: List.unmodifiable(packages),
      stableVersion: catalog['stable_x64'] is String
          ? catalog['stable_x64']
          : null,
      skippedEntries: skipped,
    );
  }
}

Uri signMcsDownload(Uri uri, {DateTime? now}) {
  const keys = {
    'g79.gdl.netease.com': 'mEE7Cot48r9j2AvEL2N6jpXEc',
    'x19.gdl.netease.com': 'l6FL78MtyLSyvkBRjo3b8kBHM',
  };
  final key = keys[uri.host];
  if (key == null) return uri;
  final expires =
      ((now ?? DateTime.now())
                  .add(const Duration(hours: 12))
                  .millisecondsSinceEpoch ~/
              1000)
          .toRadixString(16);
  final path = uri.toString().split('?').first.substring(uri.origin.length);
  final hash = md5.convert(utf8.encode('$key$path$expires')).toString();
  return uri.replace(
    query: 'key1=$hash&key2=$expires${uri.hasQuery ? '&${uri.query}' : ''}',
  );
}

class McsApi {
  McsApi({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  Uri? web;
  McsSession? session;

  Future<void> discover() async {
    final response = await client
        .get(
          Uri.parse(
            'https://x19.update.netease.com/serverlist/experience.0.4.json',
          ),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const DevelopmentStorageException('获取游戏服务地址失败。');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final uri = Uri.parse(data['WebServerUrl']);
    if (uri.scheme != 'https' || !uri.host.endsWith('.nie.netease.com')) {
      throw const DevelopmentStorageException('游戏服务地址无效。');
    }
    web = uri;
  }

  Future<Map<String, dynamic>> request(
    String resource,
    Map<String, dynamic> data, {
    bool encrypted = false,
    String method = 'POST',
  }) async {
    if (web == null) await discover();
    final body = jsonEncode(data);
    final envelope = encrypted ? encryptMcsEnvelope(body) : null;
    final outgoing = http.Request(method, web!.resolve(resource))
      ..headers.addAll({
        'content-type': encrypted
            ? 'application/octet-stream'
            : 'application/json',
        'user-id': session?.id ?? '',
        'user-token': session?.directToken == true
            ? session!.token
            : mcsDynamicToken(resource, body, token: session?.token ?? ''),
      })
      ..bodyBytes = envelope?.bytes ?? utf8.encode(body);
    final response = await http.Response.fromStream(
      await client.send(outgoing).timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw DevelopmentStorageException(
        '游戏服务请求失败（HTTP ${response.statusCode}）。',
      );
    }
    var bytes = response.bodyBytes;
    if (envelope != null) {
      final result = decryptMcsEnvelope(bytes);
      if (!listEqualsBytes(envelope.key.sublist(8), result.key.sublist(0, 8))) {
        throw const DevelopmentStorageException('登录响应关联校验失败。');
      }
      bytes = result.bytes;
    }
    final result = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (result['code'] == 10 || result['code'] == 22) session = null;
    if (result['code'] != 0) {
      throw DevelopmentStorageException(
        (result['code'] == 10 || result['code'] == 22)
            ? '游戏登录已失效，请重新登录。'
            : '游戏服务未完成请求（${result['code']}）：${result['message'] ?? '未知错误'}',
      );
    }
    return Map<String, dynamic>.from(result['entity'] as Map);
  }

  /// The original MCS G79Http.QueryToken uses this same developer login bridge.
  /// Its token is sent directly; it is not a CoreNative dynamic request token.
  Future<McsSession> authenticateDeveloper(String cookie) async {
    session = null;
    if (cookie.isEmpty) {
      throw const DevelopmentStorageException('请先使用软件现有登录入口登录开发者账号。');
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json;charset=UTF-8',
      'Origin': 'https://mcdev.webapp.163.com',
      'Referer': 'https://mcdev.webapp.163.com/',
      'Cookie': cookie,
    };
    for (final part in cookie.split(';')) {
      final index = part.indexOf('=');
      if (index > 0 && part.substring(0, index).trim() == 'oversea_authcode') {
        headers['ACCOUNT-TOKEN'] = part.substring(index + 1).trim();
      }
    }
    final response = await client
        .post(
          Uri.https(
            'mc-launcher.webapp.163.com',
            '/users/refresh_mcs_user_token',
          ),
          headers: headers,
          body: '{}',
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const DevelopmentStorageException('开发者登录验证失败，请在设置中重新登录。');
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    final data = payload is Map ? payload['data'] : null;
    final id = data is Map ? int.tryParse(data['user_id'].toString()) : null;
    final token = data is Map ? data['token'] : null;
    final expiry = data is Map ? data['expired_at'] : null;
    if (payload is! Map ||
        payload['status'] != 'ok' ||
        id == null ||
        id <= 0 ||
        token is! String ||
        token.isEmpty ||
        expiry is! int ||
        expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const DevelopmentStorageException('开发者登录无法取得游戏访问权限，请在设置中重新登录。');
    }
    return session = McsSession(
      id.toString(),
      token,
      directToken: true,
      expiresAt: expiry,
    );
  }

  Future<GameCatalog> catalog() async {
    final entity = await request(
      '/interconn/web/pack-setting/get-for-mcstudio',
      {'setting_name': 'sdkclient_full_patchlist'},
    );
    return GameCatalog.fromJson(
      jsonDecode(entity['setting_value']) as Map<String, dynamic>,
    );
  }

  Future<GamePackage> latest() async {
    final result = (await catalog()).stable;
    if (result == null) {
      throw const DevelopmentStorageException('稳定版下载描述缺失或无效。');
    }
    return result;
  }

  void close() => client.close();
}

bool listEqualsBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
