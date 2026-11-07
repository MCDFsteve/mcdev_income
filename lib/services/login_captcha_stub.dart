import 'login_captcha.dart';

Future<String> startLoginCaptcha({
  required String captchaId,
  required String email,
  required Future<bool> Function(Uri) openWindow,
  required Duration timeout,
  Future<void>? cancelled,
}) async => throw const LoginCaptchaException('当前平台暂不支持安全验证窗口，请使用桌面客户端');
