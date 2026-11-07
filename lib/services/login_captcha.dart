import 'login_captcha_stub.dart'
    if (dart.library.io) 'login_captcha_io.dart'
    as platform;

/// An official NetEase challenge hosted in a client-provided verification window.
abstract final class LoginCaptcha {
  static Future<String> start({
    required String captchaId,
    required String email,
    required Future<bool> Function(Uri) openWindow,
    Duration timeout = const Duration(minutes: 3),
    Future<void>? cancelled,
  }) => platform.startLoginCaptcha(
    captchaId: captchaId,
    email: email,
    openWindow: openWindow,
    timeout: timeout,
    cancelled: cancelled,
  );
}

class LoginCaptchaException implements Exception {
  const LoginCaptchaException(this.message);

  final String message;

  @override
  String toString() => message;
}
