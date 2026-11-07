import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/services/login_captcha.dart';

class _Browser {
  final opened = Completer<Uri>();
  final client = HttpClient();
  var openCount = 0;

  Future<bool> open(Uri uri) async {
    openCount++;
    opened.complete(uri);
    return true;
  }

  Future<({int status, String body, HttpHeaders headers})> request(
    Uri uri, {
    String method = 'GET',
    String? origin,
    String? host,
    String? fetchSite,
    String? body,
    String contentType = 'application/json',
  }) async {
    final request = await client.openUrl(method, uri);
    if (origin != null) request.headers.set('Origin', origin);
    if (host != null) request.headers.set('Host', host);
    if (fetchSite != null) request.headers.set('Sec-Fetch-Site', fetchSite);
    if (body != null) {
      request.headers.set('Content-Type', contentType);
      request.write(body);
    }
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
      headers: response.headers,
    );
  }

  Future<void> expectClosed(Uri uri) async {
    final probe = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      await expectLater(probe.getUrl(uri), throwsA(isA<SocketException>()));
    } finally {
      probe.close(force: true);
    }
  }

  void close() => client.close(force: true);
}

Matcher captchaError(String message) => isA<LoginCaptchaException>().having(
  (error) => error.message,
  'message',
  contains(message),
);

void main() {
  late _Browser browser;
  late Completer<void> cancelled;

  setUp(() {
    browser = _Browser();
    cancelled = Completer<void>();
  });
  tearDown(() {
    if (!cancelled.isCompleted) cancelled.complete();
    browser.close();
  });

  Future<String> start({
    String captchaId = 'official-public-captcha-id',
    Duration timeout = const Duration(seconds: 10),
    Future<bool> Function(Uri)? openWindow,
  }) => LoginCaptcha.start(
    captchaId: captchaId,
    email: 'account@example.test',
    openWindow: openWindow ?? browser.open,
    timeout: timeout,
    cancelled: cancelled.future,
  );

  test(
    'official SDK page accepts a local result and closes its listener',
    () async {
      final pending = start();
      final page = await browser.opened.future;
      expect(page.host, '127.0.0.1');
      expect(page.port, isPositive);
      expect(page.query, isEmpty);
      expect(page.path, matches(r'^/[A-Za-z0-9_-]{43}/$'));
      expect(page.toString(), isNot(contains('account')));

      final document = await browser.request(page);
      expect(document.status, HttpStatus.ok);
      expect(document.headers.value('cache-control'), 'no-store');
      expect(document.headers.value('referrer-policy'), 'no-referrer');
      expect(document.headers.value('x-frame-options'), 'DENY');
      expect(document.body, contains('https://cstaticdun.126.net/load.min.js'));
      expect(document.body, contains("protocol: 'https'"));
      expect(document.body, contains("mode: 'bind'"));
      expect(document.body, contains('captcha.verify()'));
      expect(document.body, contains('data.validate'));
      expect(document.body, contains('official-public-captcha-id'));
      expect(document.body, isNot(contains('account@example.test')));
      expect(document.body, isNot(contains('extraData')));
      expect(document.body, isNot(contains('productNumber')));

      // Simulate the browser SDK's successful onVerify callback.
      final reply = await browser.request(
        page.resolve('verify'),
        method: 'POST',
        origin: page.origin,
        body: jsonEncode({'validate': 'sdk-validation-result'}),
      );
      expect(reply.status, HttpStatus.ok);
      expect(await pending, 'sdk-validation-result');
      expect(browser.openCount, 1);
      await browser.expectClosed(page);
    },
  );

  test(
    'callback rejects foreign origins, wrong tokens and invalid bodies',
    () async {
      final pending = start();
      final page = await browser.opened.future;
      final callback = page.resolve('verify');
      const body = '{"validate":"untrusted-result"}';
      for (final origin in <String?>[null, 'https://example.test', 'null']) {
        final response = await browser.request(
          callback,
          method: 'POST',
          origin: origin,
          body: body,
        );
        expect(response.status, HttpStatus.forbidden);
        expect(response.headers.value('access-control-allow-origin'), isNull);
      }
      expect(
        (await browser.request(
          callback,
          method: 'POST',
          origin: page.origin,
          host: 'attacker.test:${page.port}',
          body: body,
        )).status,
        HttpStatus.forbidden,
      );
      expect(
        (await browser.request(
          callback,
          method: 'POST',
          origin: page.origin,
          fetchSite: 'cross-site',
          body: body,
        )).status,
        HttpStatus.forbidden,
      );
      expect(
        (await browser.request(page, origin: 'https://example.test')).status,
        HttpStatus.forbidden,
      );
      expect(
        (await browser.request(
          page.replace(path: '/wrong-token/verify'),
          method: 'POST',
          origin: page.origin,
          body: body,
        )).status,
        HttpStatus.notFound,
      );
      expect(
        (await browser.request(callback, method: 'OPTIONS')).status,
        HttpStatus.methodNotAllowed,
      );
      expect(
        (await browser.request(
          callback,
          method: 'POST',
          origin: page.origin,
          body: body,
          contentType: 'text/plain',
        )).status,
        HttpStatus.unsupportedMediaType,
      );
      for (final invalid in ['not-json', '[]', '{}', '{"validate":""}']) {
        expect(
          (await browser.request(
            callback,
            method: 'POST',
            origin: page.origin,
            body: invalid,
          )).status,
          HttpStatus.badRequest,
        );
      }
      expect(
        (await browser.request(
          callback,
          method: 'POST',
          origin: page.origin,
          body: jsonEncode({'validate': 'x' * 9000}),
        )).status,
        HttpStatus.requestEntityTooLarge,
      );
      expect(
        (await browser.request(
          callback,
          method: 'POST',
          origin: page.origin,
          body: '{"validate":"trusted-result"}',
        )).status,
        HttpStatus.ok,
      );
      expect(await pending, 'trusted-result');
      await browser.expectClosed(page);
    },
  );

  test('SDK error is readable and closes the listener', () async {
    final pending = start();
    final failure = expectLater(pending, throwsA(captchaError('加载失败')));
    final page = await browser.opened.future;
    await browser.request(
      page.resolve('verify'),
      method: 'POST',
      origin: page.origin,
      body: '{"error":"load"}',
    );
    await failure;
    await browser.expectClosed(page);
  });

  test('client cancellation closes the listener', () async {
    final pending = start();
    final failure = expectLater(pending, throwsA(captchaError('已取消安全验证')));
    final page = await browser.opened.future;
    cancelled.complete();
    await failure;
    await browser.expectClosed(page);
  });

  test('page cancellation closes the listener', () async {
    final pending = start();
    final failure = expectLater(pending, throwsA(captchaError('已取消安全验证')));
    final page = await browser.opened.future;
    await browser.request(
      page.resolve('verify'),
      method: 'POST',
      origin: page.origin,
      body: '{"cancelled":true}',
    );
    await failure;
    await browser.expectClosed(page);
  });

  test(
    'timeout closes listener even if window launch never completes',
    () async {
      final pending = start(
        timeout: const Duration(milliseconds: 100),
        openWindow: (uri) {
          browser.opened.complete(uri);
          return Completer<bool>().future;
        },
      );
      final failure = expectLater(pending, throwsA(captchaError('超时')));
      final page = await browser.opened.future;
      await failure;
      await browser.expectClosed(page);
    },
  );

  test('window launch failure closes listener and omits raw errors', () async {
    for (final throwsError in [false, true]) {
      late Uri page;
      await expectLater(
        start(
          openWindow: (uri) async {
            page = uri;
            if (throwsError) throw StateError('private browser details');
            return false;
          },
        ),
        throwsA(captchaError('无法打开安全验证窗口')),
      );
      await browser.expectClosed(page);
    }
  });

  test('cancelled or invalid startup does not open browser', () async {
    cancelled.complete();
    await expectLater(start(), throwsA(captchaError('已取消安全验证')));
    expect(browser.openCount, 0);
    await expectLater(start(captchaId: ''), throwsA(captchaError('参数不完整')));
    expect(browser.openCount, 0);
  });

  test('captcha ID cannot escape the script element', () async {
    final pending = start(captchaId: '</script><script>injected()</script>');
    final failure = expectLater(pending, throwsA(captchaError('已取消安全验证')));
    final page = await browser.opened.future;
    final document = await browser.request(page);
    expect(document.body, isNot(contains('</script><script>injected()')));
    expect(document.body, contains(r'\u003c/script\u003e'));
    cancelled.complete();
    await failure;
  });
}
