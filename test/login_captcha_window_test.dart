import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mcdev_income/services/login_captcha.dart';
import 'package:mcdev_income/services/login_captcha_window.dart';

class _Window implements LoginCaptchaWindow {
  _Window({required this.onClosed, required this.onError});

  final VoidCallback onClosed;
  final void Function(LoginCaptchaException) onError;
  final opened = Completer<Uri>();
  Completer<void>? createGate;
  Object? openError;
  Object? closeError;
  bool closeRequested = false;
  bool visible = false;
  int closeCount = 0;

  @override
  Future<void> open(Uri page) async {
    opened.complete(page);
    await createGate?.future;
    if (openError != null) throw openError!;
    visible = !closeRequested;
  }

  @override
  Future<void> close() async {
    closeCount++;
    closeRequested = true;
    visible = false;
    onClosed();
    if (closeError != null) throw closeError!;
  }
}

class _NativePlatform extends InAppWebViewPlatform {
  late _NativeBrowser browser;

  @override
  PlatformInAppBrowser createPlatformInAppBrowser(
    PlatformInAppBrowserCreationParams params,
  ) => browser = _NativeBrowser(params);
}

/// Models separate HWND and WebView2 creation. Closing before ready is a test
/// failure because the Windows plugin still retains its creation callback.
class _NativeBrowser extends PlatformInAppBrowser {
  _NativeBrowser(super.params) : super.implementation();

  final operations = <String>[];
  bool ready = false;
  bool visible = false;
  bool closed = false;
  InAppBrowserClassSettings? receivedSettings;
  Completer<void>? showGate;
  Object? showError;

  @override
  Future<void> openUrlRequest({
    required URLRequest urlRequest,
    // ignore: deprecated_member_use
    InAppBrowserClassOptions? options,
    InAppBrowserClassSettings? settings,
  }) async {
    operations.add('open');
    receivedSettings = settings;
    visible = !(settings?.browserSettings.hidden ?? false);
  }

  void finishCreating() {
    ready = true;
    eventHandler!.onBrowserCreated();
  }

  @override
  Future<void> show() async {
    operations.add('show');
    await showGate?.future;
    if (showError != null) throw showError!;
    visible = true;
  }

  @override
  Future<void> close() async {
    expect(
      ready,
      isTrue,
      reason: 'WebView2 callback still references the HWND',
    );
    operations.add('close');
    visible = false;
    closed = true;
    eventHandler!.onExit();
  }
}

Matcher _captchaError(String message) => isA<LoginCaptchaException>().having(
  (error) => error.message,
  'message',
  contains(message),
);

void main() {
  late _Window window;
  late HttpClient client;
  late Completer<void> cancellation;
  Completer<void>? createGate;
  Object? openError;

  setUp(() {
    client = HttpClient();
    cancellation = Completer<void>();
    createGate = null;
    openError = null;
  });
  tearDown(() {
    if (!cancellation.isCompleted) cancellation.complete();
    client.close(force: true);
  });

  Future<String> start({
    Duration timeout = const Duration(seconds: 5),
    String captchaId = 'public-captcha-id',
  }) => WebViewLoginCaptcha.start(
    captchaId: captchaId,
    email: 'account@example.test',
    cancelled: cancellation.future,
    timeout: timeout,
    windowFactory: ({required onClosed, required onError}) {
      window = _Window(onClosed: onClosed, onError: onError)
        ..createGate = createGate
        ..openError = openError;
      return window;
    },
  );

  Future<void> post(Uri page, Map<String, dynamic> payload) async {
    final request = await client.postUrl(page.resolve('verify'));
    request.headers
      ..contentType = ContentType.json
      ..set('Origin', page.origin);
    request.write(jsonEncode(payload));
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.ok);
  }

  Future<void> expectServerClosed(Uri page) async {
    final probe = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      await expectLater(probe.getUrl(page), throwsA(isA<SocketException>()));
    } finally {
      probe.close(force: true);
    }
  }

  test(
    'success closes its window without turning onExit into cancellation',
    () async {
      final pending = start();
      final page = await window.opened.future;
      expect(page.host, '127.0.0.1');
      expect(page.toString(), isNot(contains('account')));
      await post(page, {'validate': 'official-result'});
      expect(await pending, 'official-result');
      expect(window.closeCount, 1);
      expect(window.visible, isFalse);
      await expectServerClosed(page);
    },
  );

  test(
    'user closing the native window cancels verification and HTTP listener',
    () async {
      final pending = start();
      final expectation = expectLater(pending, throwsA(_captchaError('已取消')));
      final page = await window.opened.future;
      window.onClosed();
      await expectation;
      expect(window.closeRequested, isTrue);
      await expectServerClosed(page);
    },
  );

  test(
    'a native disposal error cannot replace a successful validation',
    () async {
      final pending = start();
      final page = await window.opened.future;
      window.closeError = StateError('already destroyed');
      await post(page, {'validate': 'official-result'});
      expect(await pending, 'official-result');
      expect(window.closeCount, 1);
    },
  );

  test('a native disposal error cannot replace cancellation', () async {
    final pending = start();
    final expectation = expectLater(pending, throwsA(_captchaError('已取消')));
    await window.opened.future;
    window.closeError = StateError('already destroyed');
    window.onClosed();
    await expectation;
  });

  test('external cancellation also disposes a still-opening window', () async {
    createGate = Completer<void>();
    final pending = start();
    final expectation = expectLater(pending, throwsA(_captchaError('已取消')));
    final page = await window.opened.future;
    cancellation.complete();
    await expectation;
    expect(window.closeRequested, isTrue);
    createGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(window.visible, isFalse);
    await expectServerClosed(page);
  });

  test('timeout closes the native window and local listener', () async {
    final pending = start(timeout: const Duration(milliseconds: 100));
    final expectation = expectLater(pending, throwsA(_captchaError('超时')));
    final page = await window.opened.future;
    await expectation;
    expect(window.closeCount, 1);
    expect(window.visible, isFalse);
    await expectServerClosed(page);
  });

  test(
    'native opening error preserves actionable runtime instructions',
    () async {
      openError = const LoginCaptchaException(
        '请安装 Microsoft Edge WebView2 运行时后重新登录',
      );
      final pending = start();
      final expectation = expectLater(
        pending,
        throwsA(_captchaError('WebView2')),
      );
      final page = await window.opened.future;
      await expectation;
      expect(window.closeCount, 1);
      await expectServerClosed(page);
    },
  );

  test('native load errors end the challenge and close the window', () async {
    final pending = start();
    final expectation = expectLater(pending, throwsA(_captchaError('页面加载失败')));
    await window.opened.future;
    window.onError(const LoginCaptchaException('安全验证页面加载失败，请重试'));
    await expectation;
    expect(window.closeCount, 1);
  });

  test('official SDK load errors close the native window', () async {
    final pending = start();
    final expectation = expectLater(pending, throwsA(_captchaError('加载失败')));
    final page = await window.opened.future;
    await post(page, {'error': 'load'});
    await expectation;
    expect(window.closeCount, 1);
  });

  test('invalid challenges are rejected without opening any window', () async {
    await expectLater(start(captchaId: ''), throwsA(_captchaError('参数不完整')));
    expect(window.opened.isCompleted, isFalse);
    expect(window.closeCount, 1);
  });

  test(
    'navigation keeps the challenge top-level page and HTTPS SDK frames',
    () {
      final initial = Uri.parse('http://127.0.0.1:34567/random-challenge/');
      expect(isAllowedCaptchaNavigation(initial, initial, true), isTrue);
      for (final value in [
        'https://dun.163.com/',
        'http://127.0.0.1:34568/random-challenge/',
        'http://127.0.0.1:34567/other/',
        'http://127.0.0.1:34567/random-challenge/?redirect=1',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'netease://launch',
      ]) {
        expect(
          isAllowedCaptchaNavigation(initial, Uri.parse(value), true),
          isFalse,
        );
      }
      expect(
        isAllowedCaptchaNavigation(
          initial,
          Uri.parse('https://c.dun.163.com/api'),
          false,
        ),
        isTrue,
      );
      expect(
        isAllowedCaptchaNavigation(initial, Uri.parse('about:blank'), false),
        isTrue,
      );
      expect(
        isAllowedCaptchaNavigation(
          initial,
          Uri.parse('file:///tmp/page'),
          false,
        ),
        isFalse,
      );
      expect(isAllowedCaptchaNavigation(initial, null, false), isFalse);
    },
  );

  group('Windows native creation lifecycle', () {
    late _NativePlatform native;
    InAppWebViewPlatform? previousPlatform;
    late LoginCaptchaBrowser browser;
    late List<LoginCaptchaException> errors;

    setUp(() {
      previousPlatform = InAppWebViewPlatform.instance;
      native = _NativePlatform();
      InAppWebViewPlatform.instance = native;
      errors = [];
      browser = LoginCaptchaBrowser(
        initialPage: Uri.parse('http://127.0.0.1:34567/challenge/'),
        initiallyHidden: true,
        onClosed: () {},
        onError: errors.add,
      );
    });

    tearDown(() {
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform!;
      }
    });

    test(
      'native window stays hidden until its WebView2 controller is ready',
      () async {
        await browser.openChallenge(InAppBrowserClassSettings());
        expect(native.browser.receivedSettings!.browserSettings.hidden, isTrue);
        expect(native.browser.visible, isFalse);
        expect(native.browser.operations, ['open']);
        native.browser.finishCreating();
        await Future<void>.delayed(Duration.zero);
        expect(native.browser.visible, isTrue);
        await browser.requestClose();
        expect(native.browser.operations, ['open', 'show', 'close']);
        expect(native.browser.visible, isFalse);
      },
    );

    test(
      'cancellation before creation closes the late window without showing it',
      () async {
        await browser.openChallenge(InAppBrowserClassSettings());
        await browser.requestClose();
        expect(native.browser.operations, ['open']);
        native.browser.finishCreating();
        await Future<void>.delayed(Duration.zero);
        expect(native.browser.operations, ['open', 'close']);
        expect(native.browser.visible, isFalse);
        expect(errors, isEmpty);
      },
    );

    test(
      'cancellation during show waits then closes to prevent a late visible window',
      () async {
        await browser.openChallenge(InAppBrowserClassSettings());
        native.browser.showGate = Completer<void>();
        native.browser.finishCreating();
        final closing = browser.requestClose();
        expect(native.browser.operations, ['open', 'show']);
        native.browser.showGate!.complete();
        await closing;
        expect(native.browser.operations, ['open', 'show', 'close']);
        expect(native.browser.visible, isFalse);
        expect(errors, isEmpty);
      },
    );

    test(
      'failed native show reports an error and disposes the hidden window',
      () async {
        await browser.openChallenge(InAppBrowserClassSettings());
        native.browser.showError = StateError('native show failed');
        native.browser.finishCreating();
        await Future<void>.delayed(Duration.zero);
        expect(errors, hasLength(1));
        expect(errors.single.message, contains('无法显示'));
        expect(native.browser.closed, isTrue);
        expect(native.browser.visible, isFalse);
      },
    );

    test(
      'a late ready callback after exit never shows the closed window',
      () async {
        await browser.openChallenge(InAppBrowserClassSettings());
        browser.onExit();
        native.browser.finishCreating();
        await Future<void>.delayed(Duration.zero);
        expect(native.browser.operations, ['open']);
        expect(native.browser.visible, isFalse);
        expect(errors, isEmpty);
      },
    );
  });
}
