part of mcdev_income_app;

class LoginCookieHelper {
  static const _cookieStorageKey = 'login_cookie_cache_v1';
  static const _emailKey = 'login_email_v1';
  static const _passwordKey = 'login_password_v1';
  static const _tokenKey = 'login_oversea_token_v1';
  static const _sessionKindKey = 'login_session_kind_v1';
  static const _tokenExpiresAtKey = 'login_oversea_expires_at_v1';
  static const _refreshWindow = Duration(hours: 12);
  static const _tokenLifetime = Duration(days: 7);

  static const _mcdevHost = 'mcdev.webapp.163.com';
  static const _launcherHost = 'mc-launcher.webapp.163.com';
  static const _ursHost = 'dl.reg.163.com';
  static const _ursProduct = 'x19_developer';
  static const _ursPromark = 'kBSLIYY';
  static const _ursSm4Key = 'BC60B8B9E4FFEFFA219E5AD77F11F9E2';
  static const _ursPublicModulus =
      'b982c1fe000e1758e341e530dc51dfb10b3ede8ce14764a95c643c7ea45d62ec'
      '6b2f8b5be3c89a10851b514a7f79d31e3df15524c7bad4c60d7f49c0557eb471'
      '40e67cc450727b7a630337dbdb6f910ae600a5256927738edcab04b8a1317edc'
      'fda0506fdde8f13e561ce72abb62204ef179539d037449ae11e2a84f3b723631';
  static const _ursPublicExponent = '010001';
  static final _random = Random.secure();

  static Future<Map<String, String>> readCookies({
    bool allowCache = true,
    bool refreshIfNeeded = true,
  }) async {
    app_logger.info('LoginCookieHelper.readCookies start');
    if (refreshIfNeeded) {
      await ensureFreshLogin();
    }

    final session = await readLoginSession();
    if (session != null) {
      if (!session.expiresAt.isAfter(DateTime.now())) {
        app_logger.info('LoginCookieHelper.readCookies expired session');
        return {};
      }

      final cookieMap = <String, String>{};
      if (session.kind == LoginSessionKind.oversea) {
        if (session.token.isNotEmpty) {
          cookieMap['oversea_authcode'] = session.token;
        }
      } else {
        cookieMap.addAll(session.cookies);
      }

      if (cookieMap.isNotEmpty) {
        app_logger.info(
          'LoginCookieHelper.readCookies fresh=${cookieMap.length}',
        );
        await _persistCookies(cookieMap);
        return cookieMap;
      }
    }

    if (!allowCache) {
      app_logger.info('LoginCookieHelper.readCookies empty no-cache');
      return {};
    }
    final cached = await _readCachedCookies();
    app_logger.info('LoginCookieHelper.readCookies cache=${cached.length}');
    return cached;
  }

  static Future<String> buildCookieHeader({
    bool allowCache = true,
    bool refreshIfNeeded = true,
  }) async {
    app_logger.info('LoginCookieHelper.buildCookieHeader start');
    final cookies = await readCookies(
      allowCache: allowCache,
      refreshIfNeeded: refreshIfNeeded,
    );
    if (cookies.isEmpty) {
      app_logger.info('LoginCookieHelper.buildCookieHeader empty');
      return '';
    }
    app_logger.info('LoginCookieHelper.buildCookieHeader ok');
    return _buildCookieHeader(cookies);
  }

  static Future<LoginSession?> readLoginSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_emailKey);
      final expiresAtMs = prefs.getInt(_tokenExpiresAtKey);
      if (email == null || email.isEmpty || expiresAtMs == null) {
        return null;
      }
      final kind = _parseSessionKind(prefs.getString(_sessionKindKey));
      final cookies = await _readCachedCookies();
      final token = prefs.getString(_tokenKey) ?? '';
      if (kind == LoginSessionKind.oversea && token.isEmpty) {
        return null;
      }
      if (kind == LoginSessionKind.domestic && cookies.isEmpty) {
        return null;
      }
      return LoginSession(
        email: email,
        kind: kind,
        token: token,
        cookies: cookies,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
        savedPassword: prefs.getString(_passwordKey),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<LoginSession?> ensureFreshLogin() async {
    final session = await readLoginSession();
    if (session == null || !session.canRefresh) {
      return session;
    }
    final now = DateTime.now();
    if (session.expiresAt.isAfter(now.add(_refreshWindow))) {
      return session;
    }
    try {
      return await loginWithEmail(
        email: session.email,
        password: session.savedPassword!,
        rememberPassword: true,
      );
    } catch (_) {
      app_logger.info('LoginCookieHelper.ensureFreshLogin refresh failed');
      return session;
    }
  }

  static Future<LoginSession> loginWithEmail({
    required String email,
    required String password,
    required bool rememberPassword,
  }) async {
    final normalizedEmail = email.trim();
    final preferOversea = _isOverseaEmail(normalizedEmail);
    McDevException? firstError;

    final attempts = preferOversea
        ? <Future<LoginSession> Function()>[
            () => _loginWithOverseaEmail(
              email: normalizedEmail,
              password: password,
              rememberPassword: rememberPassword,
            ),
            () => _loginWithDomesticUrs(
              email: normalizedEmail,
              password: password,
              rememberPassword: rememberPassword,
            ),
          ]
        : <Future<LoginSession> Function()>[
            () => _loginWithDomesticUrs(
              email: normalizedEmail,
              password: password,
              rememberPassword: rememberPassword,
            ),
            () => _loginWithOverseaEmail(
              email: normalizedEmail,
              password: password,
              rememberPassword: rememberPassword,
            ),
          ];

    for (final attempt in attempts) {
      try {
        return await attempt();
      } on McDevException catch (error) {
        firstError ??= error;
        if (!_shouldTryNextLoginChannel(error)) {
          rethrow;
        }
      }
    }
    throw firstError ?? McDevException('登录失败', _mcdevUri());
  }

  static String? overseaTokenFromCookieHeader(String cookieHeader) {
    for (final part in cookieHeader.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final name = part.substring(0, index).trim();
      if (name == 'oversea_authcode') {
        return part.substring(index + 1).trim();
      }
    }
    return null;
  }

  static Future<void> clearLogin({bool clearSavedPassword = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookieStorageKey);
    await prefs.remove(_sessionKindKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_tokenExpiresAtKey);
    if (clearSavedPassword) {
      await prefs.remove(_emailKey);
      await prefs.remove(_passwordKey);
    }
  }

  static Future<LoginSession> _loginWithDomesticUrs({
    required String email,
    required String password,
    required bool rememberPassword,
  }) async {
    final client = http.Client();
    final cookies = <String, String>{};
    try {
      await _postUrsJson(
        client: client,
        cookies: cookies,
        path: 'ini',
        data: {'pd': _ursProduct, 'pkid': _ursPromark, 'pkht': _mcdevHost},
      );

      final powerData = await _prepareUrsPowerData(
        client: client,
        cookies: cookies,
        email: email,
      );
      final ticket = await _postUrsJson(
        client: client,
        cookies: cookies,
        path: 'gt',
        data: {'un': email, 'pkid': _ursPromark, 'pd': _ursProduct},
      );
      final tk = ticket['tk']?.toString();
      if (tk == null || tk.isEmpty) {
        throw McDevException('登录票据获取失败', _ursUri('gt'));
      }

      final loginData = <String, dynamic>{
        'un': email,
        'pw': _rsaEncryptPassword(password),
        'pd': _ursProduct,
        'l': 0,
        'd': 10,
        't': DateTime.now().millisecondsSinceEpoch,
        'pkid': _ursPromark,
        'domains': '',
        'tk': tk,
        'pwdKeyUp': 0,
      };
      if (powerData != null) {
        loginData['pVParam'] = powerData;
      }
      final loginResponse = await _postUrsJson(
        client: client,
        cookies: cookies,
        path: 'l',
        data: loginData,
      );
      await _completeUrsCookieSet(
        client: client,
        cookies: cookies,
        loginResponse: loginResponse,
      );
      await _finishDeveloperLogin(
        client: client,
        cookies: cookies,
        email: email,
      );

      if ((cookies['S_INFO'] ?? '').isEmpty ||
          (cookies['P_INFO'] ?? '').isEmpty) {
        throw McDevException('登录成功但未拿到网易登录 Cookie', _mcdevUri());
      }

      final session = LoginSession(
        email: email,
        kind: LoginSessionKind.domestic,
        cookies: cookies,
        expiresAt: DateTime.now().add(_tokenLifetime),
        savedPassword: rememberPassword ? password : null,
      );
      await _persistLoginSession(session);
      return session;
    } finally {
      client.close();
    }
  }

  static Future<LoginSession> _loginWithOverseaEmail({
    required String email,
    required String password,
    required bool rememberPassword,
  }) async {
    final client = http.Client();
    final uri = Uri.https(_launcherHost, '/users/oversea/login_check');
    try {
      final response = await client.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json;charset=UTF-8',
          'Origin': 'https://mcdev.webapp.163.com',
          'Referer': 'https://mcdev.webapp.163.com/',
        },
        body: jsonEncode({
          'urs': email,
          'password': password,
          'remember': rememberPassword,
        }),
      );
      if (response.statusCode != 200) {
        throw McDevException('登录请求失败: ${response.statusCode}', uri);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw McDevException('登录响应不是 JSON 对象', uri);
      }
      final status = decoded['status']?.toString().toLowerCase();
      if (status != null && status != 'ok' && status != '200') {
        throw McDevException(_messageFromResponse(decoded) ?? '登录失败', uri);
      }
      final data = decoded['data'];
      final token = data is Map
          ? data['token']?.toString()
          : decoded['token']?.toString();
      if (token == null || token.isEmpty) {
        throw McDevException('海外登录响应未返回 token', uri);
      }
      final session = LoginSession(
        email: email,
        kind: LoginSessionKind.oversea,
        token: token,
        cookies: {'oversea_authcode': token},
        expiresAt: DateTime.now().add(_tokenLifetime),
        savedPassword: rememberPassword ? password : null,
      );
      await _persistLoginSession(session);
      return session;
    } on FormatException {
      throw McDevException('登录响应不是 JSON', uri);
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> _postUrsJson({
    required http.Client client,
    required Map<String, String> cookies,
    required String path,
    required Map<String, dynamic> data,
  }) async {
    final uri = _ursUri(path);
    final payload = <String, dynamic>{...data};
    payload.putIfAbsent('channel', () => 0);
    payload['topURL'] = 'https://$_mcdevHost/';
    payload['rtid'] = _randomString(32);
    final encrypted = _sm4EncryptHex(jsonEncode(payload), _ursSm4Key);
    final response = await client.post(
      uri,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Origin': 'https://$_ursHost',
        'Referer': 'https://$_ursHost/webzj/v1.0.1/pub/index_dl2.html',
        if (cookies.isNotEmpty) 'Cookie': _buildCookieHeader(cookies),
      },
      body: jsonEncode({'encParams': encrypted}),
    );
    _mergeSetCookies(cookies, response);
    if (response.statusCode != 200) {
      throw McDevException('网易登录请求失败: ${response.statusCode}', uri);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw McDevException('网易登录响应不是 JSON 对象', uri);
    }
    final ret = decoded['ret']?.toString();
    if (ret != '201' &&
        ret != '200' &&
        ret != '202' &&
        ret != '102' &&
        ret != '104') {
      throw McDevException(_ursErrorMessage(decoded), uri);
    }
    return decoded;
  }

  static Future<Map<String, dynamic>?> _prepareUrsPowerData({
    required http.Client client,
    required Map<String, String> cookies,
    required String email,
  }) async {
    final response = await _postUrsJson(
      client: client,
      cookies: cookies,
      path: 'powGetP',
      data: {'pd': _ursProduct, 'pkid': _ursPromark, 'un': email},
    );
    final pVInfo = response['pVInfo'];
    if (pVInfo is! Map) {
      return null;
    }
    final info = Map<String, dynamic>.from(pVInfo);
    if (!_isTruthy(info['needCheck'])) {
      return null;
    }
    return _solveUrsVdfPower(info);
  }

  static Map<String, dynamic> _solveUrsVdfPower(Map<String, dynamic> info) {
    final hashFunc = info['hashFunc']?.toString();
    if (hashFunc != 'VDF_FUNCTION') {
      throw McDevException(
        '网易登录要求暂未支持的安全验证: ${hashFunc ?? 'unknown'}',
        _ursUri('powGetP'),
      );
    }

    final argsRaw = info['args'];
    if (argsRaw is! Map) {
      throw McDevException('网易登录安全验证参数缺失', _ursUri('powGetP'));
    }
    final args = Map<String, dynamic>.from(argsRaw);
    final puzzle = args['puzzle']?.toString() ?? '';
    final modulusHex = args['mod']?.toString() ?? '';
    final xHex = args['x']?.toString() ?? '';
    final iterations = _intFromDynamic(args['t']) ?? 0;
    final maxTimeMs = _intFromDynamic(info['maxTime']) ?? 1050;
    final minTimeMs = _intFromDynamic(info['minTime']) ?? 1000;
    final sid = info['sid']?.toString() ?? '';
    if (puzzle.isEmpty ||
        modulusHex.isEmpty ||
        xHex.isEmpty ||
        iterations <= 0 ||
        sid.isEmpty) {
      throw McDevException('网易登录安全验证参数不完整', _ursUri('powGetP'));
    }

    final modulus = BigInt.parse(modulusHex, radix: 16);
    var x = BigInt.parse(xHex, radix: 16);
    final stopwatch = Stopwatch()..start();
    var count = 0;
    while (count < iterations || stopwatch.elapsedMilliseconds < minTimeMs) {
      x = (x * x) % modulus;
      count++;
      if (stopwatch.elapsedMilliseconds > maxTimeMs) {
        break;
      }
    }
    stopwatch.stop();

    final spendTime = stopwatch.elapsedMilliseconds;
    final resultHex = x.toRadixString(16);
    final signParams = _encodePowerSignParams({
      'runTimes': count,
      'spendTime': spendTime,
      't': count,
      'x': resultHex,
    });
    final sign = _powSign(signParams, count);
    return {
      'puzzle': puzzle,
      'spendTime': spendTime,
      'runTimes': count,
      'sid': sid,
      'args': jsonEncode({'x': resultHex, 't': count, 'sign': sign}),
    };
  }

  static Future<void> _completeUrsCookieSet({
    required http.Client client,
    required Map<String, String> cookies,
    required Map<String, dynamic> loginResponse,
  }) async {
    final nextUrls = loginResponse['nextUrls'];
    if (nextUrls is! Iterable) {
      return;
    }
    for (final value in nextUrls) {
      final raw = value?.toString();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final url = raw.replaceFirst('http://', 'https://');
      final uri = Uri.parse(url);
      if (uri.path == '/dl/zj/mail/go') {
        await _postUrsJson(
          client: client,
          cookies: cookies,
          path: 'go',
          data: _rawQueryParameters(uri),
        );
      } else {
        final response = await client.get(
          uri,
          headers: {
            'Accept': '*/*',
            'Referer': 'https://$_ursHost/webzj/v1.0.1/pub/index_dl2.html',
            if (cookies.isNotEmpty) 'Cookie': _buildCookieHeader(cookies),
          },
        );
        _mergeSetCookies(cookies, response);
      }
    }
  }

  static Future<void> _finishDeveloperLogin({
    required http.Client client,
    required Map<String, String> cookies,
    required String email,
  }) async {
    final uri = Uri.https(_launcherHost, '/users/login');
    final response = await client.post(
      uri,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json;charset=UTF-8',
        'Origin': 'https://$_mcdevHost',
        'Referer': 'https://$_mcdevHost/',
        if (cookies.isNotEmpty) 'Cookie': _buildCookieHeader(cookies),
      },
      body: jsonEncode({
        'monitor_system': _monitorSystem(),
        'browser': 'Chrome',
        'source': '',
        'urs': email,
      }),
    );
    _mergeSetCookies(cookies, response);
    if (response.statusCode != 200) {
      throw McDevException('开发者平台登录确认失败: ${response.statusCode}', uri);
    }
    if (response.body.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final status = decoded['status']?.toString().toLowerCase();
        if (status != null && status != 'ok' && status != '200') {
          final message = _messageFromResponse(decoded) ?? '开发者平台登录失败';
          throw McDevException(message, uri);
        }
      }
    } on FormatException {
      throw McDevException('开发者平台登录响应不是 JSON', uri);
    }
  }

  static Future<void> _persistLoginSession(LoginSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, session.email);
    await prefs.setString(_sessionKindKey, session.kind.name);
    await prefs.setInt(
      _tokenExpiresAtKey,
      session.expiresAt.millisecondsSinceEpoch,
    );
    if (session.token.isEmpty) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, session.token);
    }
    if (session.savedPassword == null || session.savedPassword!.isEmpty) {
      await prefs.remove(_passwordKey);
    } else {
      await prefs.setString(_passwordKey, session.savedPassword!);
    }
    await _persistCookies(session.cookies);
  }

  static Future<void> _persistCookies(Map<String, String> cookies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cookieStorageKey, jsonEncode(cookies));
    } catch (_) {
      // Ignore persistence failures; callers can still use in-memory cookies.
    }
  }

  static Future<Map<String, String>> _readCachedCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cookieStorageKey);
      if (raw == null || raw.isEmpty) {
        return {};
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }
      final result = <String, String>{};
      decoded.forEach((key, value) {
        if (key == null || value == null) {
          return;
        }
        final name = key.toString().trim();
        if (name.isEmpty) {
          return;
        }
        result[name] = value.toString();
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static LoginSessionKind _parseSessionKind(String? raw) {
    if (raw == LoginSessionKind.domestic.name) {
      return LoginSessionKind.domestic;
    }
    if (raw == LoginSessionKind.oversea.name) {
      return LoginSessionKind.oversea;
    }
    return LoginSessionKind.oversea;
  }

  static bool _isOverseaEmail(String email) {
    final lower = email.toLowerCase();
    return lower.endsWith('@gmail.com') || lower.endsWith('@outlook.com');
  }

  static bool _shouldTryNextLoginChannel(McDevException error) {
    final message = error.message;
    return message.contains('账号不存在') ||
        message.contains('海外登录响应') ||
        message.contains('密码不正确或账号不存在');
  }

  static Uri _ursUri(String path) => Uri.https(_ursHost, '/dl/zj/mail/$path');

  static Uri _mcdevUri() => Uri.https(_mcdevHost, '/');

  static String _buildCookieHeader(Map<String, String> cookies) {
    return cookies.entries
        .where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static void _mergeSetCookies(
    Map<String, String> cookies,
    http.Response response,
  ) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) {
      return;
    }
    for (final cookie in _splitSetCookieHeader(raw)) {
      final pair = cookie.split(';').first;
      final index = pair.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isEmpty) {
        continue;
      }
      if (value.isEmpty) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
  }

  static List<String> _splitSetCookieHeader(String raw) {
    final result = <String>[];
    var start = 0;
    var inExpires = false;
    for (var i = 0; i < raw.length; i++) {
      final lowerTail = raw.substring(i).toLowerCase();
      if (lowerTail.startsWith('expires=')) {
        inExpires = true;
      }
      final char = raw.codeUnitAt(i);
      if (inExpires && char == ';'.codeUnitAt(0)) {
        inExpires = false;
      }
      if (char == ','.codeUnitAt(0) && !inExpires) {
        final next = raw.substring(i + 1);
        if (RegExp(r'^\s*[^;,=\s]+=').hasMatch(next)) {
          result.add(raw.substring(start, i).trim());
          start = i + 1;
        }
      }
    }
    result.add(raw.substring(start).trim());
    return result.where((value) => value.isNotEmpty).toList(growable: false);
  }

  static Map<String, dynamic> _rawQueryParameters(Uri uri) {
    final result = <String, dynamic>{};
    final query = uri.query;
    if (query.isEmpty) {
      return result;
    }
    for (final part in query.split('&')) {
      if (part.isEmpty) {
        continue;
      }
      final index = part.indexOf('=');
      if (index < 0) {
        result[part] = '';
      } else {
        result[part.substring(0, index)] = part.substring(index + 1);
      }
    }
    return result;
  }

  static String? _messageFromResponse(Map<String, dynamic> decoded) {
    return decoded['msg']?.toString() ??
        decoded['message']?.toString() ??
        decoded['status']?.toString();
  }

  static String _ursErrorMessage(Map<String, dynamic> decoded) {
    final ret = decoded['ret']?.toString() ?? '';
    final dt = decoded['dt']?.toString() ?? '';
    final combined = dt.isEmpty ? ret : '$ret-$dt';
    final mapped = _ursErrorMessages[combined] ?? _ursErrorMessages[ret];
    final message =
        decoded['msg']?.toString() ?? decoded['message']?.toString();
    final suffix = ret.isEmpty
        ? ''
        : ' (ret=$ret${dt.isEmpty ? '' : ', dt=$dt'})';
    return '${mapped ?? message ?? '网易登录失败'}$suffix';
  }

  static bool _isTruthy(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  static int? _intFromDynamic(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static String _encodePowerSignParams(Map<String, Object> values) {
    const sortedKeys = ['runTimes', 'spendTime', 't', 'x'];
    return sortedKeys
        .map(
          (key) =>
              '${Uri.encodeComponent(key)}='
              '${Uri.encodeComponent(values[key].toString())}',
        )
        .join('&');
  }

  static int _powSign(String key, int seed) {
    final bytes = key.codeUnits;
    final remainder = bytes.length & 3;
    final blockBytes = bytes.length - remainder;
    var h1 = _u32(seed);
    const c1 = 0xcc9e2d51;
    const c2 = 0x1b873593;
    var i = 0;

    while (i < blockBytes) {
      var k1 =
          (bytes[i] & 0xff) |
          ((bytes[++i] & 0xff) << 8) |
          ((bytes[++i] & 0xff) << 16) |
          ((bytes[++i] & 0xff) << 24);
      i++;
      k1 = _mul32(k1, c1);
      k1 = _u32((k1 << 15) | (k1 >> 17));
      k1 = _mul32(k1, c2);
      h1 = _u32(h1 ^ k1);
      h1 = _u32((h1 << 13) | (h1 >> 19));
      final h1b = _mul32(h1, 5);
      h1 = _u32(
        (h1b & 0xffff) +
            0x6b64 +
            (((((h1b >> 16) & 0xffff) + 0xe654) & 0xffff) << 16),
      );
    }

    var k1 = 0;
    if (remainder == 3) {
      k1 ^= (bytes[i + 2] & 0xff) << 16;
    }
    if (remainder >= 2) {
      k1 ^= (bytes[i + 1] & 0xff) << 8;
    }
    if (remainder >= 1) {
      k1 ^= bytes[i] & 0xff;
      k1 = _mul32(k1, c1);
      k1 = _u32((k1 << 15) | (k1 >> 17));
      k1 = _mul32(k1, c2);
      h1 = _u32(h1 ^ k1);
    }

    h1 = _u32(h1 ^ key.length);
    h1 = _u32(h1 ^ (h1 >> 16));
    h1 = _mul32(h1, 0x85ebca6b);
    h1 = _u32(h1 ^ (h1 >> 13));
    h1 = _mul32(h1, 0xc2b2ae35);
    h1 = _u32(h1 ^ (h1 >> 16));
    return h1;
  }

  static String _monitorSystem() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.iOS => 'Iphone',
      TargetPlatform.android => 'Android',
      _ => 'Unknown',
    };
  }

  static String _randomString(int length) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    return List.generate(
      length,
      (_) => chars[_random.nextInt(chars.length)],
      growable: false,
    ).join();
  }

  static String _rsaEncryptPassword(String password) {
    final bytes = utf8.encode(password);
    const keyLength = 128;
    if (bytes.length > keyLength - 11) {
      throw McDevException('密码过长，无法完成网易登录加密', _mcdevUri());
    }
    final block = <int>[0, 2];
    final paddingLength = keyLength - bytes.length - 3;
    for (var i = 0; i < paddingLength; i++) {
      var value = 0;
      while (value == 0) {
        value = _random.nextInt(255) + 1;
      }
      block.add(value);
    }
    block
      ..add(0)
      ..addAll(bytes);
    final message = _bigIntFromBytes(block);
    final exponent = BigInt.parse(_ursPublicExponent, radix: 16);
    final modulus = BigInt.parse(_ursPublicModulus, radix: 16);
    final encrypted = message.modPow(exponent, modulus);
    return base64Encode(_bytesFromBigInt(encrypted, keyLength));
  }

  static BigInt _bigIntFromBytes(List<int> bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte & 0xff);
    }
    return result;
  }

  static List<int> _bytesFromBigInt(BigInt value, int length) {
    final result = List<int>.filled(length, 0);
    var current = value;
    for (var i = length - 1; i >= 0; i--) {
      result[i] = (current & BigInt.from(0xff)).toInt();
      current >>= 8;
    }
    return result;
  }

  static String _sm4EncryptHex(String text, String keyHex) {
    final data = <int>[...utf8.encode(text)];
    final padding = 16 - data.length % 16;
    for (var i = 0; i < padding; i++) {
      data.add(padding);
    }
    final keys = _sm4KeySchedule(_hexToBytes(keyHex));
    final output = <int>[];
    for (var offset = 0; offset < data.length; offset += 16) {
      output.addAll(_sm4CryptBlock(data.sublist(offset, offset + 16), keys));
    }
    return output.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static List<int> _sm4KeySchedule(List<int> key) {
    if (key.length != 16) {
      throw StateError('SM4 key must be 16 bytes');
    }
    final words = List<int>.filled(36, 0);
    for (var i = 0; i < 4; i++) {
      words[i] = _u32(
        (key[4 * i] << 24) |
            (key[4 * i + 1] << 16) |
            (key[4 * i + 2] << 8) |
            key[4 * i + 3],
      );
    }
    words[0] = _u32(words[0] ^ 0xa3b1bac6);
    words[1] = _u32(words[1] ^ 0x56aa3350);
    words[2] = _u32(words[2] ^ 0x677d9197);
    words[3] = _u32(words[3] ^ 0xb27022dc);

    final roundKeys = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      final value = _u32(
        words[i + 1] ^ words[i + 2] ^ words[i + 3] ^ _sm4Ck[i],
      );
      words[i + 4] = _u32(words[i] ^ _sm4KeyTransform(_sm4Tau(value)));
      roundKeys[i] = words[i + 4];
    }
    return roundKeys;
  }

  static List<int> _sm4CryptBlock(List<int> block, List<int> roundKeys) {
    final words = List<int>.filled(36, 0);
    for (var i = 0; i < 4; i++) {
      words[i] = _u32(
        (block[4 * i] << 24) |
            (block[4 * i + 1] << 16) |
            (block[4 * i + 2] << 8) |
            block[4 * i + 3],
      );
    }
    for (var i = 0; i < 32; i++) {
      final value = _u32(
        words[i + 1] ^ words[i + 2] ^ words[i + 3] ^ roundKeys[i],
      );
      words[i + 4] = _u32(words[i] ^ _sm4RoundTransform(_sm4Tau(value)));
    }
    final output = <int>[];
    for (var i = 0; i < 4; i++) {
      final value = words[35 - i];
      output
        ..add((value >> 24) & 0xff)
        ..add((value >> 16) & 0xff)
        ..add((value >> 8) & 0xff)
        ..add(value & 0xff);
    }
    return output;
  }

  static int _sm4Tau(int value) {
    return _u32(
      (_sm4Sbox[(value >> 24) & 0xff] << 24) |
          (_sm4Sbox[(value >> 16) & 0xff] << 16) |
          (_sm4Sbox[(value >> 8) & 0xff] << 8) |
          _sm4Sbox[value & 0xff],
    );
  }

  static int _sm4RoundTransform(int value) {
    return _u32(
      value ^
          _rotl32(value, 2) ^
          _rotl32(value, 10) ^
          _rotl32(value, 18) ^
          _rotl32(value, 24),
    );
  }

  static int _sm4KeyTransform(int value) {
    return _u32(value ^ _rotl32(value, 13) ^ _rotl32(value, 23));
  }

  static int _rotl32(int value, int bits) {
    final normalized = _u32(value);
    return _u32((normalized << bits) | (normalized >> (32 - bits)));
  }

  static int _mul32(int value, int multiplier) {
    final normalized = _u32(value);
    return _u32(
      ((normalized & 0xffff) * multiplier) +
          (((((normalized >> 16) & 0xffff) * multiplier) & 0xffff) << 16),
    );
  }

  static int _u32(int value) => value & 0xffffffff;

  static const _ursErrorMessages = <String, String>{
    '401': '登录参数错误或会话已过期，请重试',
    '401-10': '账号格式错误',
    '402': '当前登录指纹异常，请稍后重试',
    '408': '已开启登录保护，请打开网易账号管家完成验证',
    '409': '您登录过于频繁，请稍后再试',
    '412-01': '您登录错误次数过多，请稍后再试',
    '412-02': '您登录错误次数过多，请明天再试',
    '413-01': '您登录密码错误次数过多，请稍后再试',
    '413-02': '您登录密码错误次数过多，请明天再试',
    '413-03': '您的 IP 登录密码错误次数过多，请稍后再试',
    '414-01': '您的 IP 登录错误次数过多，请稍后再试',
    '414-02': '您的 IP 登录错误次数过多，请明天再试',
    '416': '您的 IP 登录过于频繁，请稍后再试',
    '417-01': '您的 IP 登录成功次数过多，请稍后再试',
    '417-02': '您的 IP 登录成功次数过多，请明天再试',
    '418-01': '您登录成功次数过多，请稍后再试',
    '418-02': '您登录成功次数过多，请明天再试',
    '419-01': '您登录过于频繁，请稍后再试',
    '419-02': '您的 IP 登录过于频繁，请稍后再试',
    '420': '账号不存在',
    '423': '当前登录存在风险，请进行安全验证',
    '427': '当前登录存在风险，请进行安全验证',
    '428': '当前登录存在风险，请稍后再试',
    '442': '请输入正确的验证码',
    '443': '请输入正确的短信验证码',
    '500': '系统繁忙，请稍后再试',
    '503': '服务器繁忙，请稍后再试',
    '505': '次数超限，请稍后再试',
  };

  static const _sm4Sbox = <int>[
    214,
    144,
    233,
    254,
    204,
    225,
    61,
    183,
    22,
    182,
    20,
    194,
    40,
    251,
    44,
    5,
    43,
    103,
    154,
    118,
    42,
    190,
    4,
    195,
    170,
    68,
    19,
    38,
    73,
    134,
    6,
    153,
    156,
    66,
    80,
    244,
    145,
    239,
    152,
    122,
    51,
    84,
    11,
    67,
    237,
    207,
    172,
    98,
    228,
    179,
    28,
    169,
    201,
    8,
    232,
    149,
    128,
    223,
    148,
    250,
    117,
    143,
    63,
    166,
    71,
    7,
    167,
    252,
    243,
    115,
    23,
    186,
    131,
    89,
    60,
    25,
    230,
    133,
    79,
    168,
    104,
    107,
    129,
    178,
    113,
    100,
    218,
    139,
    248,
    235,
    15,
    75,
    112,
    86,
    157,
    53,
    30,
    36,
    14,
    94,
    99,
    88,
    209,
    162,
    37,
    34,
    124,
    59,
    1,
    33,
    120,
    135,
    212,
    0,
    70,
    87,
    159,
    211,
    39,
    82,
    76,
    54,
    2,
    231,
    160,
    196,
    200,
    158,
    234,
    191,
    138,
    210,
    64,
    199,
    56,
    181,
    163,
    247,
    242,
    206,
    249,
    97,
    21,
    161,
    224,
    174,
    93,
    164,
    155,
    52,
    26,
    85,
    173,
    147,
    50,
    48,
    245,
    140,
    177,
    227,
    29,
    246,
    226,
    46,
    130,
    102,
    202,
    96,
    192,
    41,
    35,
    171,
    13,
    83,
    78,
    111,
    213,
    219,
    55,
    69,
    222,
    253,
    142,
    47,
    3,
    255,
    106,
    114,
    109,
    108,
    91,
    81,
    141,
    27,
    175,
    146,
    187,
    221,
    188,
    127,
    17,
    217,
    92,
    65,
    31,
    16,
    90,
    216,
    10,
    193,
    49,
    136,
    165,
    205,
    123,
    189,
    45,
    116,
    208,
    18,
    184,
    229,
    180,
    176,
    137,
    105,
    151,
    74,
    12,
    150,
    119,
    126,
    101,
    185,
    241,
    9,
    197,
    110,
    198,
    132,
    24,
    240,
    125,
    236,
    58,
    220,
    77,
    32,
    121,
    238,
    95,
    62,
    215,
    203,
    57,
    72,
  ];

  static const _sm4Ck = <int>[
    462357,
    472066609,
    943670861,
    1415275113,
    1886879365,
    2358483617,
    2830087869,
    3301692121,
    3773296373,
    4228057617,
    404694573,
    876298825,
    1347903077,
    1819507329,
    2291111581,
    2762715833,
    3234320085,
    3705924337,
    4177462797,
    337322537,
    808926789,
    1280531041,
    1752135293,
    2223739545,
    2695343797,
    3166948049,
    3638552301,
    4110090761,
    269950501,
    741554753,
    1213159005,
    1684763257,
  ];
}
