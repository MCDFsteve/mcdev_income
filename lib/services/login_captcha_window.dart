import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'login_captcha.dart';

/// Owns the native window, including an open operation that finishes after close.
@visibleForTesting
abstract interface class LoginCaptchaWindow {
  Future<void> open(Uri page);
  Future<void> close();
}

@visibleForTesting
typedef LoginCaptchaWindowFactory =
    LoginCaptchaWindow Function({
      required VoidCallback onClosed,
      required void Function(LoginCaptchaException) onError,
    });

/// Shows only the official public challenge page. Account credentials and URS
/// cookies stay in the login service and are never sent to this WebView.
abstract final class WebViewLoginCaptcha {
  static Future<String> start({
    required String captchaId,
    required String email,
    Future<void>? cancelled,
    Duration timeout = const Duration(minutes: 3),
    @visibleForTesting LoginCaptchaWindowFactory? windowFactory,
  }) async {
    final cancellation = Completer<void>();
    var finished = false;
    LoginCaptchaException? windowError;
    void cancel() {
      if (!finished && !cancellation.isCompleted) cancellation.complete();
    }

    if (cancelled != null) {
      unawaited(
        cancelled.then<void>(
          (_) => cancel(),
          onError: (Object _) {
            cancel();
          },
        ),
      );
    }
    final window = (windowFactory ?? _NativeCaptchaWindow.new)(
      onClosed: cancel,
      onError: (error) {
        if (finished) return;
        windowError ??= error;
        cancel();
      },
    );
    try {
      return await LoginCaptcha.start(
        captchaId: captchaId,
        email: email,
        timeout: timeout,
        cancelled: cancellation.future,
        openWindow: (page) async {
          try {
            await window.open(page);
            return true;
          } catch (error) {
            if (!finished) {
              windowError = error is LoginCaptchaException
                  ? error
                  : const LoginCaptchaException('无法打开安全验证窗口，请重试');
              cancel();
            }
            return false;
          }
        },
      );
    } on LoginCaptchaException catch (error) {
      throw windowError ?? error;
    } finally {
      // Suppress onExit before closing: success must not become cancellation.
      finished = true;
      try {
        await window.close().timeout(const Duration(seconds: 2));
      } catch (error) {
        // Native shutdown can race an OS/user close. Preserve the original
        // result and report only the error type, never challenge URLs/tokens.
        debugPrint('安全验证窗口清理失败：${error.runtimeType}');
      }
    }
  }
}

/// Restricts top-level browsing without blocking the official SDK's frames and
/// resources. The opaque path and loopback origin are checked by the server too.
@visibleForTesting
bool isAllowedCaptchaNavigation(
  Uri initialPage,
  Uri? target,
  bool isMainFrame,
) {
  if (target == null) return false;
  if (!isMainFrame) {
    return target.scheme == 'https' || target.toString() == 'about:blank';
  }
  return target == initialPage;
}

class _NativeCaptchaWindow implements LoginCaptchaWindow {
  _NativeCaptchaWindow({required this.onClosed, required this.onError});

  final VoidCallback onClosed;
  final void Function(LoginCaptchaException) onError;
  LoginCaptchaBrowser? _browser;
  WebViewEnvironment? _environment;
  Directory? _profile;
  bool _disposed = false;
  bool _preparing = false;

  @override
  Future<void> open(Uri page) async {
    if (_disposed) return;
    if (kIsWeb ||
        !(Platform.isMacOS ||
            Platform.isWindows ||
            Platform.isAndroid ||
            Platform.isIOS)) {
      throw const LoginCaptchaException(
        '当前平台暂不支持内置安全验证窗口，请在 Windows 或 macOS 上登录',
      );
    }
    _preparing = true;
    try {
      if (Platform.isWindows) {
        final version = await WebViewEnvironment.getAvailableVersion();
        if (_disposed) return;
        if (version == null) {
          throw const LoginCaptchaException(
            '请安装 Microsoft Edge WebView2 运行时后重新登录',
          );
        }
        // A writable, private profile also supports installations in Program
        // Files. InPrivate prevents challenge cookies persisting in this folder.
        _profile = await Directory.systemTemp.createTemp('mcdev-captcha-');
        if (_disposed) return;
        _environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: _profile!.path),
        );
        if (_disposed) return;
      }
      final frame = await _windowFrame();
      if (_disposed) return;
      final browser = LoginCaptchaBrowser(
        initialPage: page,
        initiallyHidden: Platform.isWindows,
        webViewEnvironment: _environment,
        onClosed: () {
          if (!_disposed) onClosed();
          unawaited(_releaseEnvironment());
        },
        onError: (error) {
          if (!_disposed) onError(error);
        },
      );
      _browser = browser;
      await browser.openChallenge(
        InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            toolbarTopFixedTitle: '网易安全验证',
            hideToolbarTop: true,
            hideToolbarBottom: true,
            hideUrlBar: true,
            hideDefaultMenuItems: true,
            windowFrame: frame,
            windowType: Platform.isMacOS ? WindowType.CHILD : WindowType.WINDOW,
            windowStyleMask: Platform.isMacOS
                ? WindowStyleMask.TITLED |
                      WindowStyleMask.CLOSABLE |
                      WindowStyleMask.RESIZABLE
                : null,
          ),
          webViewSettings: InAppWebViewSettings(
            incognito: true,
            cacheEnabled: false,
            sharedCookiesEnabled: false,
            useShouldOverrideUrlLoading: true,
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: false,
            isInspectable: false,
            disableContextMenu: true,
          ),
        ),
      );
      if (_disposed) await browser.requestClose();
    } finally {
      _preparing = false;
      if (_disposed && _browser == null) await _releaseEnvironment();
    }
  }

  Future<InAppWebViewRect?> _windowFrame() async {
    if (!(Platform.isMacOS || Platform.isWindows)) return null;
    const width = 480.0;
    const height = 560.0;
    final bounds = await windowManager.getBounds();
    var x = bounds.center.dx - width / 2;
    var y = bounds.center.dy - height / 2;
    var scale = 1.0;
    if (Platform.isMacOS) {
      final primary = await screenRetriever.getPrimaryDisplay();
      // AppKit uses a bottom-left origin, while window_manager uses top-left.
      y = primary.size.height - y - height;
    } else {
      scale = windowManager.getDevicePixelRatio();
    }
    // The plugin constructor asserts nonnegative coordinates; its mutable
    // fields nevertheless support monitors left of or below the primary one.
    return InAppWebViewRect(
        x: 0,
        y: 0,
        width: width * scale,
        height: height * scale,
      )
      ..x = x * scale
      ..y = y * scale;
  }

  @override
  Future<void> close() async {
    _disposed = true;
    final browser = _browser;
    if (browser != null) {
      await browser.requestClose();
    } else if (!_preparing) {
      await _releaseEnvironment();
    }
  }

  Future<void> _releaseEnvironment() async {
    final environment = _environment;
    _environment = null;
    try {
      await environment?.dispose();
    } catch (_) {
      // Cleanup cannot replace an already obtained challenge result.
    }
    final profile = _profile;
    _profile = null;
    try {
      await profile?.delete(recursive: true);
    } on FileSystemException {
      // WebView2 may hold its temporary files briefly after the window exits.
      // The profile is in the OS temp directory; InPrivate stores no cookies.
    }
  }
}

@visibleForTesting
class LoginCaptchaBrowser extends InAppBrowser {
  LoginCaptchaBrowser({
    required this.initialPage,
    required this.initiallyHidden,
    required this.onClosed,
    required this.onError,
    super.webViewEnvironment,
  });

  final Uri initialPage;
  final bool initiallyHidden;
  final VoidCallback onClosed;
  final void Function(LoginCaptchaException) onError;
  bool _created = false;
  bool _exited = false;
  bool _closeRequested = false;
  Future<void>? _showing;
  Future<void>? _closing;

  Future<void> openChallenge(InAppBrowserClassSettings settings) {
    // Windows creates the HWND before its asynchronous WebView2 controller.
    // A visible close button during that interval can destroy the object still
    // captured by the plugin's creation callback. Reveal it only when ready.
    settings.browserSettings.hidden = initiallyHidden;
    return openUrlRequest(
      urlRequest: URLRequest(url: WebUri(initialPage.toString())),
      settings: settings,
    );
  }

  Future<void> requestClose() async {
    _closeRequested = true;
    if (!_created || _exited) return;
    final showing = _showing;
    if (showing != null) {
      // A queued show must finish before close; otherwise it could reveal a
      // window after verification has already ended.
      try {
        await showing;
      } catch (_) {
        // _showWhenReady handles the actionable error.
      }
    }
    if (_exited) return;
    // A cancelled native creation may still deliver onBrowserCreated later.
    // Keep the handler until then so the late window is closed immediately.
    await (_closing ??= _closeNative());
  }

  Future<void> _closeNative() async {
    try {
      await super.close().timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('安全验证原生窗口关闭失败：${error.runtimeType}');
    }
  }

  @override
  void onBrowserCreated() {
    if (_created || _exited) return;
    _created = true;
    if (_closeRequested) {
      unawaited(requestClose());
    } else if (initiallyHidden) {
      unawaited(_showWhenReady());
    }
  }

  Future<void> _showWhenReady() async {
    if (_closeRequested || _exited) return;
    var failed = false;
    try {
      final showing = super.show().timeout(const Duration(seconds: 2));
      _showing = showing;
      await showing;
    } catch (_) {
      failed = true;
    } finally {
      _showing = null;
    }
    if (failed && !_closeRequested && !_exited) {
      onError(const LoginCaptchaException('无法显示安全验证窗口，请重试'));
      await requestClose();
    } else if (_closeRequested && !_exited) {
      await requestClose();
    }
  }

  @override
  void onExit() {
    if (_exited) return;
    _exited = true;
    onClosed();
  }

  @override
  void onMainWindowWillClose() {
    onClosed();
    unawaited(requestClose());
  }

  @override
  Future<NavigationActionPolicy?> shouldOverrideUrlLoading(
    NavigationAction navigationAction,
  ) async =>
      isAllowedCaptchaNavigation(
        initialPage,
        navigationAction.request.url?.uriValue,
        navigationAction.isForMainFrame,
      )
      ? NavigationActionPolicy.ALLOW
      : NavigationActionPolicy.CANCEL;

  @override
  Future<bool?> onCreateWindow(CreateWindowAction createWindowAction) async =>
      false;

  @override
  Future<PermissionResponse?> onPermissionRequest(
    PermissionRequest permissionRequest,
  ) async => PermissionResponse(
    resources: permissionRequest.resources,
    action: PermissionResponseAction.DENY,
  );

  @override
  Future<GeolocationPermissionShowPromptResponse?>
  onGeolocationPermissionsShowPrompt(String origin) async =>
      GeolocationPermissionShowPromptResponse(
        origin: origin,
        allow: false,
        retain: false,
      );

  // No server-trust callback is overridden: WKWebView/WebView2 keep their normal
  // certificate validation, including rejection of invalid certificates.
  @override
  void onReceivedError(WebResourceRequest request, WebResourceError error) {
    if (error.type == WebResourceErrorType.CANCELLED) return;
    if (request.isForMainFrame == true && !_closeRequested) {
      onError(const LoginCaptchaException('安全验证页面加载失败，请检查网络后重试'));
    }
  }

  @override
  void onReceivedHttpError(
    WebResourceRequest request,
    WebResourceResponse errorResponse,
  ) {
    if (request.isForMainFrame == true && !_closeRequested) {
      onError(const LoginCaptchaException('安全验证页面加载失败，请重新登录'));
    }
  }
}
