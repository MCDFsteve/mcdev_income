part of mcdev_income_app;

class LoginCookieHelper {
  static final _cookieUrls = [
    WebUri('https://mc-launcher.webapp.163.com/'),
    WebUri('https://mcdev.webapp.163.com/'),
  ];
  static const _cookieStorageKey = 'login_cookie_cache_v1';

  static Future<Map<String, String>> readCookies({
    bool allowCache = true,
  }) async {
    final manager = CookieManager.instance();
    final cookieMap = <String, String>{};

    for (final url in _cookieUrls) {
      final cookies = await manager.getCookies(url: url);
      for (final cookie in cookies) {
        final name = cookie.name;
        if (name.isEmpty) {
          continue;
        }
        cookieMap[name] = cookie.value;
      }
    }

    if (cookieMap.isNotEmpty) {
      await _persistCookies(cookieMap);
      return cookieMap;
    }

    if (!allowCache) {
      return {};
    }
    return _readCachedCookies();
  }

  static Future<String> buildCookieHeader({bool allowCache = true}) async {
    final cookies = await readCookies(allowCache: allowCache);
    if (cookies.isEmpty) {
      return '';
    }
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  static Future<void> _persistCookies(Map<String, String> cookies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cookieStorageKey, jsonEncode(cookies));
    } catch (_) {
      // 忽略持久化失败
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
}
