part of '../main.dart';

/// Flutter adapter for the shared headless login implementation.
class LoginCookieHelper {
  static void _configure() {
    CoreRuntime.preferences = AppPreferences.getInstance;
    CoreRuntime.log = app_logger.info;
    CoreRuntime.system = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.iOS => 'Iphone',
      TargetPlatform.android => 'Android',
      _ => 'Unknown',
    };
  }

  static Future<Map<String, String>> readCookies({
    bool allowCache = true,
    bool refreshIfNeeded = true,
  }) {
    _configure();
    return LoginService.readCookies(
      allowCache: allowCache,
      refreshIfNeeded: refreshIfNeeded,
    );
  }

  static Future<String> buildCookieHeader({
    bool allowCache = true,
    bool refreshIfNeeded = true,
  }) {
    _configure();
    return LoginService.buildCookieHeader(
      allowCache: allowCache,
      refreshIfNeeded: refreshIfNeeded,
    );
  }

  static Future<LoginSession?> readLoginSession() {
    _configure();
    return LoginService.readLoginSession();
  }

  static Future<LoginSession?> ensureFreshLogin() {
    _configure();
    return LoginService.ensureFreshLogin();
  }

  static Future<LoginSession> loginWithEmail({
    required String email,
    required String password,
    required bool rememberPassword,
  }) {
    _configure();
    return LoginService.loginWithEmail(
      email: email,
      password: password,
      rememberPassword: rememberPassword,
    );
  }

  static Future<void> clearLogin({bool clearSavedPassword = true}) {
    _configure();
    return LoginService.clearLogin(clearSavedPassword: clearSavedPassword);
  }

  static String? overseaTokenFromCookieHeader(String header) =>
      LoginService.overseaTokenFromCookieHeader(header);
}
