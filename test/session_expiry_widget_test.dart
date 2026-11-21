import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/main.dart';
import 'package:mcdev_income/storage/app_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MemorySecretStore secrets;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secrets = MemorySecretStore();
    AppSecretStore.testOverride = secrets;
  });

  tearDown(() {
    AppSecretStore.testOverride = null;
  });

  testWidgets('does not show expired prompt when never logged in', (
    tester,
  ) async {
    await tester.pumpWidget(const McDevIncomeApp());
    await tester.pumpAndSettle();

    expect(find.text('登录已过期'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'prompts to re-login on launch when saved session is expired and opens login page',
    (tester) async {
      secrets.values['login_session_v1'] = jsonEncode({
        'version': 1,
        'email': 'expired@163.com',
        'kind': 'domestic',
        'expires_at': DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        'cookies': {'S_INFO': 'stale-cookie'},
      });

      await tester.pumpWidget(const McDevIncomeApp());
      await tester.pumpAndSettle();

      expect(find.text('登录已过期'), findsOneWidget);
      expect(find.textContaining('expired@163.com'), findsOneWidget);

      await tester.tap(find.text('去登录'));
      await tester.pumpAndSettle();

      expect(find.text('邮箱账号登录'), findsOneWidget);
      expect(find.text('expired@163.com'), findsOneWidget);
      expect(find.text('保存密码用于自动刷新凭证'), findsNothing);
      expect(secrets.values['login_session_v1'], isNot(contains('stale-cookie')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'migrates legacy plaintext expired session on launch, scrubs password, and prompts',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'login_email_v1': 'legacy@163.com',
        'login_password_v1': 'plaintext-secret',
        'login_session_kind_v1': 'domestic',
        'login_cookie_cache_v1': jsonEncode({'S_INFO': 'old-s', 'P_INFO': 'old-p'}),
        'login_oversea_expires_at_v1': DateTime.now()
            .subtract(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
      });

      await tester.pumpWidget(const McDevIncomeApp());
      await tester.pumpAndSettle();

      expect(find.text('登录已过期'), findsOneWidget);
      expect(find.textContaining('legacy@163.com'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      for (final key in LoginService.legacySecretKeys) {
        expect(prefs.get(key), isNull);
      }
      expect(
        secrets.values['login_session_v1'],
        isNot(contains('plaintext-secret')),
      );
      expect(secrets.values['login_session_v1'], isNot(contains('old-s')));
    },
  );

  testWidgets('dismissing expired prompt with 稍后 does not reopen immediately', (
    tester,
  ) async {
    secrets.values['login_session_v1'] = jsonEncode({
      'version': 1,
      'email': 'expired@163.com',
      'kind': 'domestic',
      'expires_at': DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });

    await tester.pumpWidget(const McDevIncomeApp());
    await tester.pumpAndSettle();

    expect(find.text('登录已过期'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(find.text('登录已过期'), findsNothing);
  });

  testWidgets('runtime 401 expiry notification opens re-login dialog once', (
    tester,
  ) async {
    secrets.values['login_session_v1'] = jsonEncode({
      'version': 1,
      'email': 'active@163.com',
      'kind': 'domestic',
      'expires_at': DateTime.now()
          .add(const Duration(days: 5))
          .millisecondsSinceEpoch,
      'cookies': {'S_INFO': 'live-s', 'P_INFO': 'live-p'},
    });

    await tester.pumpWidget(const McDevIncomeApp());
    await tester.pumpAndSettle();

    expect(find.text('登录已过期'), findsNothing);

    await LoginCookieHelper.notifySessionExpired();
    await LoginCookieHelper.notifySessionExpired();
    await tester.pumpAndSettle();

    expect(find.text('登录已过期'), findsOneWidget);
    expect(find.textContaining('active@163.com'), findsOneWidget);
    expect(secrets.values['login_session_v1'], isNot(contains('live-s')));
    expect(await LoginCookieHelper.readCookies(), isEmpty);
  });
}
