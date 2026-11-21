part of '../main.dart';

/// Flutter adapter for the shared headless login implementation.
class LoginCookieHelper {
  static final ValueNotifier<int> sessionRevision = ValueNotifier<int>(0);
  static final StreamController<String?> _expiredController =
      StreamController<String?>.broadcast();

  static Stream<String?> get onSessionExpired => _expiredController.stream;

  static void _configure() {
    CoreRuntime.preferences = AppPreferences.getInstance;
    CoreRuntime.secrets = AppSecretStore.getInstance;
    CoreRuntime.onAuthExpired = notifySessionExpired;
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

  static Future<void> notifySessionExpired([String? email]) async {
    _configure();
    var targetEmail = email;
    if (targetEmail == null || targetEmail.isEmpty) {
      final session = await LoginService.readLoginSession();
      targetEmail = session?.email;
    }
    await LoginService.markSessionExpired();
    if (!_expiredController.isClosed) {
      _expiredController.add(targetEmail);
    }
  }

  static Future<Map<String, String>> readCookies() {
    _configure();
    return LoginService.readCookies();
  }

  static Future<String> buildCookieHeader() {
    _configure();
    return LoginService.buildCookieHeader();
  }

  static Future<LoginSession?> readLoginSession() {
    _configure();
    return LoginService.readLoginSession();
  }

  static Future<LoginSession> loginWithEmail({
    required String email,
    required String password,
    LoginCaptchaHandler? onCaptcha,
  }) async {
    _configure();
    final session = await LoginService.loginWithEmail(
      email: email,
      password: password,
      onCaptcha: onCaptcha,
    );
    sessionRevision.value++;
    return session;
  }

  static Future<void> clearLogin() async {
    _configure();
    await LoginService.clearLogin();
    sessionRevision.value++;
  }

  static String? overseaTokenFromCookieHeader(String header) =>
      LoginService.overseaTokenFromCookieHeader(header);
}
