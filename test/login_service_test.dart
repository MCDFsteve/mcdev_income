import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/core.dart';

const _email = 'regression@qq.com';
const _password = 'test-only-password';
const _captchaId = 'test-captcha-id';

void main() {
  late _Preferences preferences;
  late http.Client Function() previousClientFactory;
  late Future<PreferenceStore> Function() previousPreferences;

  setUp(() {
    previousClientFactory = LoginService.clientFactory;
    previousPreferences = CoreRuntime.preferences;
    preferences = _Preferences();
    CoreRuntime.preferences = () async => preferences;
  });

  tearDown(() {
    LoginService.clientFactory = previousClientFactory;
    CoreRuntime.preferences = previousPreferences;
  });

  Future<LoginSession> login({
    String email = _email,
    LoginCaptchaHandler? onCaptcha,
  }) => LoginService.loginWithEmail(
    email: email,
    password: _password,
    rememberPassword: false,
    onCaptcha: onCaptcha,
  );

  test('independent SM4 decoder matches the standard single-block vector', () {
    // GB/T 32907-2016 example: key and plaintext both 012345...3210.
    expect(
      _sm4Decrypt(
        _unhex('681edf34d206965e86b3e94f536e4246'),
        _unhex('0123456789abcdeffedcba9876543210'),
      ),
      _unhex('0123456789abcdeffedcba9876543210'),
    );
  });

  test(
    'domestic login completes cookies before persisting, without password',
    () async {
      preferences.values['login_password_v1'] = 'previous-saved-password';
      final protocol = _Protocol([
        _initialization(),
        _power(),
        _ticket('first-ticket'),
        _loginSuccess(ticket: 'first-ticket'),
        ..._completeLogin(),
      ]);
      final session = await login(email: ' $_email ');

      protocol.expectComplete();
      expect(session.kind, LoginSessionKind.domestic);
      expect(session.email, _email);
      expect(session.cookies, containsPair('S_INFO', 'test-s-info'));
      expect(session.cookies, containsPair('P_INFO', 'test-p-info'));
      expect(session.savedPassword, isNull);
      expect(preferences.values['login_password_v1'], isNull);
      expect(preferences.applies, 1);
      expect((await LoginService.readLoginSession())?.cookies, session.cookies);
      expect(
        await LoginService.buildCookieHeader(refreshIfNeeded: false),
        contains('P_INFO=test-p-info'),
      );
    },
  );

  test('ini capFlag 6 verifies before requesting proof and ticket', () async {
    var challenges = 0;
    final protocol = _Protocol([
      _initialization(capFlag: '6'),
      _verification(
        'official-validate',
        check: (request, payload) {
          expect(request.headers['cookie'], contains('URS_SESSION=initial'));
        },
      ),
      _power(),
      _ticket('verified-ticket'),
      _loginSuccess(ticket: 'verified-ticket'),
      ..._completeLogin(),
    ]);

    await login(
      onCaptcha: (challenge) async {
        challenges++;
        expect(challenge.captchaId, _captchaId);
        expect(challenge.email, _email);
        expect(challenge.ret, '447');
        expect(preferences.applies, 0);
        return 'official-validate';
      },
    );

    expect(challenges, 1);
    protocol.expectComplete();
    expect(preferences.applies, 1);
  });

  for (final challengedPath in ['gt', 'l']) {
    test(
      '$challengedPath 447 keeps URS cookies and obtains a fresh proof and ticket',
      () async {
        var challenges = 0;
        final protocol = _Protocol([
          _initialization(),
          _power(),
          if (challengedPath == 'l') _ticket('expired-ticket'),
          _Step(
            challengedPath,
            {'ret': 447},
            headers: {
              'set-cookie': 'URS_RISK=challenge-cookie; Path=/; Secure',
            },
          ),
          _verification(
            'official-validate',
            check: (request, payload) {
              expect(
                request.headers['cookie'],
                contains('URS_SESSION=initial'),
              );
              expect(
                request.headers['cookie'],
                contains('URS_RISK=challenge-cookie'),
              );
            },
          ),
          _power(),
          _ticket('fresh-ticket'),
          _loginSuccess(
            ticket: 'fresh-ticket',
            check: (request, payload) {
              expect(request.headers['cookie'], contains('URS_VERIFIED=yes'));
            },
          ),
          ..._completeLogin(),
        ]);

        final session = await login(
          onCaptcha: (challenge) async {
            challenges++;
            expect(challenge.captchaId, _captchaId);
            expect(challenge.ret, '447');
            expect(preferences.applies, 0);
            return 'official-validate';
          },
        );

        protocol.expectComplete();
        expect(challenges, 1);
        expect(session.kind, LoginSessionKind.domestic);
        expect(session.cookies, containsPair('URS_RISK', 'challenge-cookie'));
      },
    );
  }

  test('new captcha id from 447 replaces initialization id', () async {
    final protocol = _Protocol([
      _initialization(),
      _power(),
      _Step('gt', {'ret': '447', 'capId': 'replacement-captcha'}),
      _verification('replacement-validate'),
      _power(),
      _ticket('fresh-ticket'),
      _loginSuccess(ticket: 'fresh-ticket'),
      ..._completeLogin(),
    ]);

    await login(
      onCaptcha: (challenge) async {
        expect(challenge.captchaId, 'replacement-captcha');
        return 'replacement-validate';
      },
    );
    protocol.expectComplete();
  });

  for (final ret in [200, 442, 447, 499]) {
    test(
      'vfscp ret=$ret does not continue or persist an unverified login',
      () async {
        preferences.values['unrelated-setting'] = 'preserved';
        final protocol = _Protocol([
          _initialization(capFlag: 6),
          _Step('vfscp', {'ret': ret}),
        ]);
        var challenges = 0;
        await expectLater(
          login(
            onCaptcha: (_) async {
              challenges++;
              return 'invalid-or-expired-validate';
            },
          ),
          throwsA(isA<McDevException>()),
        );

        protocol.expectComplete();
        expect(challenges, 1);
        expect(preferences.applies, 0);
        expect(preferences.values, {'unrelated-setting': 'preserved'});
        expect(await LoginService.readLoginSession(), isNull);
      },
    );
  }

  for (final cancelledValue in <String?>[null, '', '   ']) {
    test(
      'cancelled verification ($cancelledValue) sends no token and saves nothing',
      () async {
        final protocol = _Protocol([_initialization(capFlag: 6)]);
        await expectLater(
          login(onCaptcha: (_) async => cancelledValue),
          throwsA(
            isA<McDevException>().having(
              (e) => e.message,
              'message',
              contains('取消'),
            ),
          ),
        );
        protocol.expectComplete();
        expect(preferences.applies, 0);
        expect(preferences.values, isEmpty);
      },
    );
  }

  test(
    'two challenges are the limit, including initialization challenge',
    () async {
      var challenges = 0;
      final protocol = _Protocol([
        _initialization(capFlag: 6),
        _verification('validate-1'),
        _power(),
        _Step('gt', {'ret': 447}),
        _verification('validate-2'),
        _power(),
        _Step('gt', {'ret': 447}),
      ]);
      await expectLater(
        login(onCaptcha: (_) async => 'validate-${++challenges}'),
        throwsA(
          isA<LoginChallengeException>().having((e) => e.ret, 'ret', '447'),
        ),
      );
      protocol.expectComplete();
      expect(challenges, 2);
      expect(preferences.applies, 0);
    },
  );

  for (final challengedPath in ['ini', 'gt', 'l']) {
    test(
      '$challengedPath challenge without callback is explicit and does not fall back',
      () async {
        final protocol = _Protocol([
          _initialization(capFlag: challengedPath == 'ini' ? 6 : 0),
          if (challengedPath != 'ini') ...[
            _power(),
            if (challengedPath == 'l') _ticket('unused-ticket'),
            _Step(challengedPath, {'ret': 447}),
          ],
        ]);
        await expectLater(
          login(),
          throwsA(
            isA<LoginChallengeException>()
                .having((e) => e.ret, 'ret', '447')
                .having((e) => e.captchaId, 'captchaId', _captchaId)
                .having((e) => e.message, 'message', contains('登录界面')),
          ),
        );
        protocol.expectComplete();
        expect(preferences.applies, 0);
      },
    );
  }

  test('unknown URS errors are not retried or persisted', () async {
    final protocol = _Protocol([
      _initialization(),
      _power(),
      _ticket('first-ticket'),
      _Step('l', {'ret': 499, 'msg': 'unexpected-service-error'}),
    ]);
    await expectLater(
      login(
        onCaptcha: (_) async => fail('Unknown errors must not open captcha'),
      ),
      throwsA(
        isA<McDevException>().having(
          (e) => e.message,
          'message',
          contains('ret=499'),
        ),
      ),
    );
    protocol.expectComplete();
    expect(preferences.applies, 0);
  });

  test(
    'developer confirmation failure cannot persist partial URS cookies',
    () async {
      final protocol = _Protocol([
        _initialization(),
        _power(),
        _ticket('first-ticket'),
        _loginSuccess(ticket: 'first-ticket'),
        _cookieCompletion(),
        _Step('/users/login', {
          'status': 'error',
          'msg': 'confirmation-failed',
        }),
      ]);
      await expectLater(login(), throwsA(isA<McDevException>()));
      protocol.expectComplete();
      expect(preferences.applies, 0);
      expect(await LoginService.readLoginSession(), isNull);
    },
  );

  test(
    'overseas login still accepts its token and does not store the password',
    () async {
      final protocol = _Protocol([_overseaSuccess('regression@gmail.com')]);
      final session = await login(
        email: 'regression@gmail.com',
        onCaptcha: (_) async => fail('Overseas success needs no captcha'),
      );
      protocol.expectComplete();
      expect(session.kind, LoginSessionKind.oversea);
      expect(session.token, 'test-oversea-token');
      expect(session.savedPassword, isNull);
      expect(preferences.values['login_password_v1'], isNull);
      expect(preferences.applies, 1);
    },
  );

  test(
    'domestic account-not-found 420 can still fall back to overseas login',
    () async {
      final protocol = _Protocol([
        _initialization(),
        _power(),
        _Step('gt', {'ret': 420}),
        _overseaSuccess(_email),
      ]);
      final session = await login();
      protocol.expectComplete();
      expect(session.kind, LoginSessionKind.oversea);
      expect(preferences.applies, 1);
    },
  );
}

typedef _Check = void Function(http.Request, Map<String, dynamic>);

class _Step {
  const _Step(this.path, this.response, {this.headers = const {}, this.check});
  final String path;
  final Map<String, dynamic> response;
  final Map<String, String> headers;
  final _Check? check;
}

class _Protocol {
  _Protocol(this.steps) {
    LoginService.clientFactory = () => MockClient((request) async {
      expect(
        index,
        lessThan(steps.length),
        reason: 'Unexpected extra request: ${request.url}',
      );
      final step = steps[index++];
      expect(request.method, 'POST');
      final isUrs = !step.path.startsWith('/');
      expect(
        request.url.host,
        isUrs ? 'dl.reg.163.com' : 'mc-launcher.webapp.163.com',
      );
      expect(request.url.path, isUrs ? '/dl/zj/mail/${step.path}' : step.path);
      final payload = isUrs
          ? _decodeUrsRequest(request)
          : jsonDecode(request.body) as Map<String, dynamic>;
      if (isUrs) {
        expect(payload['channel'], 0);
        expect(payload['topURL'], 'https://mcdev.webapp.163.com/');
        expect(payload['rtid'], matches(RegExp(r'^[a-zA-Z0-9]{32}$')));
      }
      step.check?.call(request, payload);
      return http.Response(
        jsonEncode(step.response),
        200,
        headers: step.headers,
      );
    });
  }
  final List<_Step> steps;
  var index = 0;
  void expectComplete() => expect(index, steps.length);
}

_Step _initialization({Object capFlag = 0}) => _Step(
  'ini',
  {'ret': 201, 'capFlag': capFlag, 'capId': _captchaId},
  headers: {'set-cookie': 'URS_SESSION=initial; Path=/; Secure'},
  check: (_, payload) {
    expect(payload['pd'], 'x19_developer');
    expect(payload['pkid'], 'kBSLIYY');
    expect(payload['pkht'], 'mcdev.webapp.163.com');
  },
);

_Step _power() => const _Step('powGetP', {
  'ret': 200,
  'pVInfo': {'needCheck': false},
});
_Step _ticket(String value) => _Step('gt', {'ret': 200, 'tk': value});

_Step _verification(String validate, {_Check? check}) => _Step(
  'vfscp',
  {'ret': 201},
  headers: {'set-cookie': 'URS_VERIFIED=yes; Path=/; Secure'},
  check: (request, payload) {
    expect(payload['un'], _email);
    expect(payload['pd'], 'x19_developer');
    expect(payload['pkid'], 'kBSLIYY');
    expect(payload['cap'], validate);
    expect(payload, isNot(contains('pw')));
    check?.call(request, payload);
  },
);

_Step _loginSuccess({required String ticket, _Check? check}) => _Step(
  'l',
  {
    'ret': 200,
    'nextUrls': ['https://dl.reg.163.com/dl/zj/mail/go?ticket=opaque%2Bvalue'],
  },
  check: (request, payload) {
    expect(payload['un'], _email);
    expect(payload['tk'], ticket);
    expect(payload['pw'], isNot(_password));
    expect(base64Decode(payload['pw'] as String), hasLength(128));
    check?.call(request, payload);
  },
);

_Step _cookieCompletion() => _Step(
  'go',
  {'ret': 200},
  headers: {
    'set-cookie':
        'S_INFO=test-s-info; Path=/; Secure, P_INFO=test-p-info; Path=/; Secure',
  },
  check: (_, payload) => expect(payload['ticket'], 'opaque%2Bvalue'),
);

List<_Step> _completeLogin() => [
  _cookieCompletion(),
  _Step(
    '/users/login',
    {'status': 'ok'},
    check: (request, payload) {
      expect(request.headers['cookie'], contains('S_INFO=test-s-info'));
      expect(request.headers['cookie'], contains('P_INFO=test-p-info'));
      expect(payload['urs'], _email);
    },
  ),
];

_Step _overseaSuccess(String email) => _Step(
  '/users/oversea/login_check',
  {
    'status': 'ok',
    'data': {'token': 'test-oversea-token'},
  },
  check: (_, payload) {
    expect(payload['urs'], email);
    expect(payload['password'], _password);
    expect(payload['remember'], false);
  },
);

class _Preferences implements PreferenceStore {
  final values = <String, Object>{};
  var applies = 0;
  @override
  String? getString(String key) => values[key] as String?;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<void> apply(Map<String, Object?> changes) async {
    applies++;
    for (final entry in changes.entries) {
      if (entry.value == null) {
        values.remove(entry.key);
      } else {
        values[entry.key] = entry.value!;
      }
    }
  }
}

Map<String, dynamic> _decodeUrsRequest(http.Request request) {
  final wrapper = jsonDecode(request.body) as Map<String, dynamic>;
  expect(wrapper.keys, ['encParams']);
  final bytes = _sm4Decrypt(
    _unhex(wrapper['encParams'] as String),
    _unhex('BC60B8B9E4FFEFFA219E5AD77F11F9E2'),
  );
  final padding = bytes.last;
  expect(padding, inInclusiveRange(1, 16));
  expect(bytes.sublist(bytes.length - padding), everyElement(padding));
  return jsonDecode(utf8.decode(bytes.sublist(0, bytes.length - padding)))
      as Map<String, dynamic>;
}

Uint8List _unhex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

// Independent SM4 oracle: the current PointyCastle dependency has no SM4
// engine. Decode with the standard recurrence and validate it against the
// published example above, without using production encryption helpers.
Uint8List _sm4Decrypt(Uint8List ciphertext, Uint8List key) {
  final sbox = _unhex(
    'd690e9fecce13db716b614c228fb2c05'
    '2b679a762abe04c3aa44132649860699'
    '9c4250f491ef987a33540b43edcfac62'
    'e4b31ca9c908e89580df94fa758f3fa6'
    '4707a7fcf37317ba83593c19e6854fa8'
    '686b81b27164da8bf8eb0f4b70569d35'
    '1e240e5e6358d1a225227c3b01217887'
    'd40046579fd327524c3602e7a0c4c89e'
    'eabf8ad240c738b5a3f7f2cef96115a1'
    'e0ae5da49b341a55ad933230f58cb1e3'
    '1df6e22e8266ca60c02923ab0d534e6f'
    'd5db3745defd8e2f03ff6a726d6c5b51'
    '8d1baf92bbddbc7f11d95c411f105ad8'
    '0ac13188a5cd7bbd2d74d012b8e5b4b0'
    '8969974a0c96777e65b9f109c56ec684'
    '18f07dec3adc4d2079ee5f3ed7cb3948',
  );
  int rotate(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xffffffff;
  int substitute(int x) =>
      (sbox[(x >> 24) & 255] << 24) |
      (sbox[(x >> 16) & 255] << 16) |
      (sbox[(x >> 8) & 255] << 8) |
      sbox[x & 255];
  final keyView = ByteData.sublistView(key);
  const fk = [0xa3b1bac6, 0x56aa3350, 0x677d9197, 0xb27022dc];
  final words = [for (var i = 0; i < 4; i++) keyView.getUint32(i * 4) ^ fk[i]];
  for (var i = 0; i < 32; i++) {
    var ck = 0;
    for (var j = 0; j < 4; j++) {
      ck = (ck << 8) | (((4 * i + j) * 7) & 255);
    }
    final b = substitute(words[i + 1] ^ words[i + 2] ^ words[i + 3] ^ ck);
    words.add(words[i] ^ b ^ rotate(b, 13) ^ rotate(b, 23));
  }
  final input = ByteData.sublistView(ciphertext);
  final output = Uint8List(ciphertext.length);
  final outputView = ByteData.sublistView(output);
  for (var offset = 0; offset < ciphertext.length; offset += 16) {
    final x = [for (var i = 0; i < 4; i++) input.getUint32(offset + i * 4)];
    for (var i = 0; i < 32; i++) {
      final b = substitute(x[i + 1] ^ x[i + 2] ^ x[i + 3] ^ words[35 - i]);
      x.add(
        x[i] ^ b ^ rotate(b, 2) ^ rotate(b, 10) ^ rotate(b, 18) ^ rotate(b, 24),
      );
    }
    for (var i = 0; i < 4; i++) {
      outputView.setUint32(offset + i * 4, x[35 - i]);
    }
  }
  return output;
}
