import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'login_captcha.dart';

const _maxBodyBytes = 8192;

Future<String> startLoginCaptcha({
  required String captchaId,
  required String email,
  required Future<bool> Function(Uri) openWindow,
  required Duration timeout,
  Future<void>? cancelled,
}) async {
  if (captchaId.trim().isEmpty || email.trim().isEmpty) {
    throw const LoginCaptchaException('安全验证参数不完整，请重新登录');
  }
  if (timeout <= Duration.zero) {
    throw const LoginCaptchaException('安全验证已超时，请重新登录');
  }

  // Keep completion non-throwing until the server is closed. In particular,
  // cancellation can arrive while bind/openWindow is still pending.
  final result = Completer<_CaptchaResult>();
  void finish(_CaptchaResult value) {
    if (!result.isCompleted) result.complete(value);
  }

  if (cancelled != null) {
    unawaited(
      cancelled.then<void>(
        (_) => finish(const _CaptchaResult.error('已取消安全验证')),
        onError: (Object _, StackTrace _) {
          finish(const _CaptchaResult.error('已取消安全验证'));
        },
      ),
    );
  }
  final timer = Timer(
    timeout,
    () => finish(const _CaptchaResult.error('安全验证已超时，请重新登录')),
  );
  HttpServer? server;
  try {
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException {
      throw const LoginCaptchaException('无法启动本机安全验证，请重试');
    }
    final random = Random.secure();
    final token = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final page = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/$token/',
    );
    final verify = page.resolve('verify');
    // The current official URS SDK does not pass the account as extraData.
    // Only the public captcha ID is included in this page, never credentials.
    final html = _captchaPage(captchaId: captchaId, callback: verify.path);
    server.listen(
      (request) {
        unawaited(
          _handleRequest(request, page, verify, html, finish).catchError((
            Object _,
            StackTrace _,
          ) {
            request.response.close().ignore();
          }),
        );
      },
      onError: (Object _, StackTrace _) {
        finish(const _CaptchaResult.error('本机安全验证连接失败，请重试'));
      },
    );
    if (!result.isCompleted) {
      unawaited(
        Future<bool>.sync(() => openWindow(page)).then<void>(
          (opened) {
            if (!opened) {
              finish(const _CaptchaResult.error('无法打开安全验证窗口，请重试'));
            }
          },
          onError: (Object _, StackTrace _) {
            finish(const _CaptchaResult.error('无法打开安全验证窗口，请重试'));
          },
        ),
      );
    }
    final completed = await result.future;
    if (completed.error != null) {
      throw LoginCaptchaException(completed.error!);
    }
    return completed.validate!;
  } finally {
    timer.cancel();
    await server?.close(force: true);
  }
}

Future<void> _handleRequest(
  HttpRequest request,
  Uri page,
  Uri verify,
  String html,
  void Function(_CaptchaResult) finish,
) async {
  final response = request.response;
  response.headers
    ..set(HttpHeaders.cacheControlHeader, 'no-store')
    ..set('Pragma', 'no-cache')
    ..set('Referrer-Policy', 'no-referrer')
    ..set('X-Content-Type-Options', 'nosniff')
    ..set('X-Frame-Options', 'DENY')
    ..set(
      'Content-Security-Policy',
      "frame-ancestors 'none'; base-uri 'none'; object-src 'none'; form-action 'none'",
    );
  final origin = request.headers.value('Origin');
  if (request.headers.value(HttpHeaders.hostHeader) != page.authority ||
      (origin != null && origin != page.origin) ||
      request.headers.value('Sec-Fetch-Site') == 'cross-site' ||
      request.uri.hasQuery) {
    await _respond(response, HttpStatus.forbidden);
    return;
  }
  if (request.uri.path == page.path && request.method == 'GET') {
    response.headers.contentType = ContentType.html;
    response.write(html);
    await response.close();
    return;
  }
  if (request.uri.path != verify.path) {
    await _respond(response, HttpStatus.notFound);
    return;
  }
  if (request.method != 'POST') {
    await _respond(response, HttpStatus.methodNotAllowed);
    return;
  }
  if (origin != page.origin) {
    await _respond(response, HttpStatus.forbidden);
    return;
  }
  if (request.headers.contentType?.mimeType != 'application/json') {
    await _respond(response, HttpStatus.unsupportedMediaType);
    return;
  }
  if (request.contentLength > _maxBodyBytes) {
    await _respond(response, HttpStatus.requestEntityTooLarge);
    return;
  }
  final body = <int>[];
  try {
    await for (final chunk in request.timeout(const Duration(seconds: 10))) {
      if (body.length + chunk.length > _maxBodyBytes) {
        await _respond(response, HttpStatus.requestEntityTooLarge);
        return;
      }
      body.addAll(chunk);
    }
    final payload = jsonDecode(utf8.decode(body));
    if (payload is! Map<String, dynamic>) {
      await _respond(response, HttpStatus.badRequest);
      return;
    }
    _CaptchaResult completed;
    final validate = payload['validate'];
    if (validate is String &&
        validate.trim().isNotEmpty &&
        validate.length <= 4096) {
      completed = _CaptchaResult.validate(validate);
    } else if (payload['cancelled'] == true) {
      completed = const _CaptchaResult.error('已取消安全验证');
    } else if (payload['error'] == 'load' || payload['error'] == 'init') {
      completed = const _CaptchaResult.error('网易安全验证加载失败，请检查网络后重试');
    } else {
      await _respond(response, HttpStatus.badRequest);
      return;
    }
    await _respond(response, HttpStatus.ok);
    finish(completed);
  } on FormatException {
    await _respond(response, HttpStatus.badRequest);
  } on TimeoutException {
    await _respond(response, HttpStatus.requestTimeout);
  }
}

Future<void> _respond(HttpResponse response, int status) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode({'ok': status == HttpStatus.ok}));
  await response.close();
}

class _CaptchaResult {
  const _CaptchaResult.validate(this.validate) : error = null;
  const _CaptchaResult.error(this.error) : validate = null;

  final String? validate;
  final String? error;
}

String _scriptJson(Object value) => jsonEncode(value)
    .replaceAll('<', r'\u003c')
    .replaceAll('>', r'\u003e')
    .replaceAll('&', r'\u0026')
    .replaceAll('\u2028', r'\u2028')
    .replaceAll('\u2029', r'\u2029');

String _captchaPage({required String captchaId, required String callback}) =>
    '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <title>网易账号安全验证</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f4f5f7; color: #25292e; }
    main { box-sizing: border-box; width: min(100%, 520px); padding: 28px 24px; }
    h1 { font-size: 26px; margin: 0 0 18px; }
    p { line-height: 1.8; margin: 12px 0; }
    #status { min-height: 58px; color: #545c66; }
    .actions { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 24px; }
    button { font: inherit; border: 1px solid #69737e; border-radius: 6px; padding: 11px 20px; cursor: pointer; background: transparent; color: inherit; }
    #verify { background: #216c37; border-color: #216c37; color: white; }
    button:disabled { opacity: .55; cursor: default; }
    button:focus-visible { outline: 3px solid #83adf1; outline-offset: 3px; }
    @media (prefers-color-scheme: dark) {
      body { background: #181b20; color: #f1f3f5; }
      #status { color: #bfc6ce; }
    }
  </style>
</head>
<body>
<main>
  <h1>完成网易账号安全验证</h1>
  <p>请按照验证码提示完成操作，验证完成后会自动关闭窗口并继续登录。</p>
  <p id="status" role="status" aria-live="polite">正在加载网易安全验证…</p>
  <div id="captcha"></div>
  <div class="actions">
    <button id="verify" type="button" disabled>开始验证</button>
    <button id="cancel" type="button">取消验证</button>
  </div>
</main>
<script>
(() => {
  'use strict';
  const callback = ${_scriptJson(callback)};
  const captchaId = ${_scriptJson(captchaId)};
  const status = document.getElementById('status');
  const verify = document.getElementById('verify');
  const cancel = document.getElementById('cancel');
  let captcha, submitting = false, finished = false;
  function message(text) { status.textContent = text; }
  async function report(payload, successMessage) {
    if (submitting || finished) return;
    submitting = true;
    verify.disabled = true;
    cancel.disabled = true;
    try {
      const response = await fetch(callback, {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        credentials: 'omit', cache: 'no-store', body: JSON.stringify(payload)
      });
      if (!response.ok) throw new Error('callback');
      finished = true;
      message(successMessage);
      if (captcha && captcha.destroy) captcha.destroy();
    } catch (_) {
      message('验证连接已结束，请关闭窗口并重新登录。');
      finished = true;
    } finally { submitting = false; }
  }
  function failed(kind) {
    report({error: kind}, '网易安全验证加载失败，请检查网络后重试。');
  }
  verify.addEventListener('click', () => {
    if (!captcha || finished || submitting) return;
    try {
      captcha.verify();
      message('请完成网易验证码提示。');
    } catch (_) { failed('init'); }
  });
  cancel.addEventListener('click', () => {
    report({cancelled: true}, '已取消安全验证。');
  });
  function initialize() {
    if (finished) return;
    if (typeof window.initNECaptcha !== 'function') { failed('load'); return; }
    try {
      window.initNECaptcha({
        captchaId, element: document.getElementById('captcha'), mode: 'bind',
        protocol: 'https', ipv6: false,
        wmServerConfig: {
          configServer: 'webzjac.reg.163.com', apiServer: 'webzjac.reg.163.com',
          staticServer: 'acstatic-dun.126.net'
        },
        apiServer: ['webzjcaptcha.reg.163.com', 'c.dun.163yun.com'],
        staticServer: ['cstaticdun.126.net'], timeout: 20000, feedbackEnable: false,
        popupStyles: {capBarHeight: 40, capPadding: 10,
          width: Math.min(350, document.body.clientWidth * 0.8), top: 'auto'},
        onVerify(error, data) {
          if (error) { message('验证未通过，请重试。'); return; }
          if (!data || typeof data.validate !== 'string' || !data.validate) {
            message('未收到验证结果，请重试。'); return;
          }
          report({validate: data.validate}, '安全验证已完成，正在继续登录…');
        }
      }, instance => {
        captcha = instance;
        if (!finished) {
          verify.disabled = false;
          message('安全验证已就绪，请点击“开始验证”。');
        } else if (instance.destroy) { instance.destroy(); }
      }, () => failed('init'));
    } catch (_) { failed('init'); }
  }
  function load(fallback) {
    const script = document.createElement('script');
    script.src = fallback ? 'https://cstaticdun1.126.net/load.min.js'
      : 'https://cstaticdun.126.net/load.min.js';
    script.async = true;
    script.onload = initialize;
    script.onerror = () => fallback ? failed('load') : load(true);
    document.head.appendChild(script);
  }
  load(false);
})();
</script>
</body>
</html>''';
