import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/main.dart';

final testOptions = {
  'pri_type': {
    'pe': [
      {'id': 2, 'title': '附加包'},
      {'id': 4, 'title': '皮肤'},
    ],
    'comp': [
      {'id': 3, 'title': '功能组件'},
    ],
  },
  'sub_type': {
    'pe': {
      '2': [
        {
          'id': 6,
          'title': '玩法拓展',
          'fp_type': 'zip_package',
          'file_type': 'zip',
        },
      ],
      '4': [
        {
          'id': 13,
          'title': '原版皮肤',
          'fp_type': 'png',
          'file_type': 'png',
          'body_type': [
            {'id': 'normal', 'title': '标准'},
          ],
        },
      ],
    },
    'pc': {
      '3': [
        {'id': 1, 'title': '功能', 'fp_type': 'jar', 'file_type': 'jar'},
      ],
    },
  },
  'channel': {
    'pe': [
      {
        'id': 3,
        'title': '封面',
        'width': 992,
        'height': 558,
        'required': 1,
        'version': 2,
      },
      {'id': 5, 'title': '皮肤图', 'width': 1000, 'height': 1000, 'required': 1},
    ],
    'comp': [],
  },
  'special_channel': {
    'pe': {
      '13': [5],
    },
  },
  'price_type': [
    {'id': 'free', 'title': '免费', 'min': 0, 'max': 0},
    {'id': 'diamond', 'title': '钻石', 'min': 10, 'step': 10},
  ],
  'mc_version': ['1.20.1'],
  'mod_version': ['3.9'],
};

Map<String, dynamic> testResource({
  String status = 'init',
  String id = '123',
}) => {
  'item_id': id,
  'item_name': '测试模组',
  'status': status,
  'pri_type': 2,
  'sub_type': 6,
  'price_type': 'free',
  'price': 0,
  'info': '<p>玩法介绍</p>',
  'mod_version': '3.9',
  'mc_version': [],
  'is_original': true,
  'res': [
    {
      'res_id': 7,
      'res_name': 'sample.zip',
      'res_url': 'res_url',
      'mc_version': [],
      'add_version': true,
      'res_info': {'res_size': 25},
    },
  ],
  'channel': [
    {'channel_id': 3, 'channel_url': 'saved-image', 'version': 2},
    {'channel_id': 5, 'channel_url': 'saved-image'},
  ],
};

http.Response ok(dynamic data) => http.Response(
  jsonEncode({'status': 'ok', 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'HTTP 200 with platform failure never becomes a successful save',
    () async {
      final api = McDevApi(
        cookie: 'secret',
        category: 'pe',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'status': 'invalid', 'msg': '缺少资源文件'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.saveResource(resourceCategory: 'pe', payload: {}),
        throwsA(
          isA<McDevException>().having(
            (e) => e.message,
            'message',
            contains('缺少资源文件'),
          ),
        ),
      );
    },
  );

  test(
    'list uses website fuzzy_key, status and pagination parameters',
    () async {
      final api = McDevApi(
        cookie: 'session',
        category: 'pe',
        client: MockClient((request) async {
          expect(request.url.path, '/items/categories/pe/');
          expect(request.url.queryParameters, containsPair('fuzzy_key', '测试'));
          expect(
            request.url.queryParameters,
            containsPair('status', 'reviewing'),
          );
          expect(request.url.queryParameters['start'], '30');
          expect(request.url.queryParameters['span'], '30');
          expect(request.url.queryParameters.containsKey('keyword'), false);
          return ok({
            'count': 116,
            'item': [testResource()],
          });
        }),
      );
      addTearDown(api.close);
      final page = await api.fetchResources(
        resourceCategory: 'pe',
        start: 30,
        span: 30,
        keyword: '测试',
        status: 'reviewing',
      );
      expect(page.total, 116);
      expect(page.items.single.name, '测试模组');
    },
  );

  test(
    'upload retains signed metadata and never forwards login cookies to filepicker',
    () async {
      var progress = 0;
      final api = McDevApi(
        cookie: 'login=private',
        category: 'pe',
        client: MockClient((request) async {
          if (request.url.host == 'mc-launcher.webapp.163.com') {
            expect(request.url.path, '/filepicker/file_token');
            expect(request.url.queryParameters['file_type'], 'zip_package');
            expect(request.headers['Cookie'], 'login=private');
            return ok({'token': 'scoped-upload-token'});
          }
          expect(
            request.url.toString(),
            'https://fp.ps.netease.com/x19/file/new/',
          );
          expect(request.headers['Accept'], 'application/json');
          expect(request.headers['Origin'], 'https://mcdev.webapp.163.com');
          expect(request.headers['Referer'], 'https://mcdev.webapp.163.com/');
          expect(
            request.headers.keys.map((e) => e.toLowerCase()),
            isNot(contains('cookie')),
          );
          expect(
            request.headers.keys.map((e) => e.toLowerCase()),
            isNot(contains('account-token')),
          );
          expect(
            request.body,
            contains('name="fpfile"; filename="sample.zip"'),
          );
          expect(request.body, contains('scoped-upload-token'));
          return http.Response(
            '{"url":"https://x19.fp.ps.netease.com/file/example","fsize":3,"md5":"abc"}',
            200,
            headers: {'x-ntes-signature': 'signed-proof'},
          );
        }),
      );
      addTearDown(api.close);
      final uploaded = await api.uploadResourceFile(
        name: 'sample.zip',
        length: 3,
        stream: Stream.value([1, 2, 3]),
        fileType: 'zip_package',
        onProgress: (sent, total) => progress = sent,
      );
      expect(progress, 3);
      expect(uploaded.signedValue, {
        'body':
            '{"url": "https://x19.fp.ps.netease.com/file/example", "fsize": 3, "md5": "abc"}',
        'file_type': 'zip_package',
        'sign': 'signed-proof',
      });
    },
  );

  test('unsigned upload response is rejected', () async {
    final api = McDevApi(
      cookie: '',
      category: 'pe',
      client: MockClient(
        (request) async => request.url.host == 'mc-launcher.webapp.163.com'
            ? ok({'token': 'upload'})
            : http.Response(
                '{"url":"https://x19.fp.ps.netease.com/file/example"}',
                200,
              ),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.uploadResourceFile(
        name: 'x.zip',
        length: 1,
        stream: Stream.value([1]),
        fileType: 'zip_package',
      ),
      throwsA(isA<McDevException>()),
    );
  });

  test('signed iframe upload response is decoded without executing HTML', () async {
    final api = McDevApi(
      cookie: '',
      category: 'pe',
      client: MockClient((request) async {
        if (request.url.host == 'mc-launcher.webapp.163.com') {
          return ok({'token': 'upload'});
        }
        return http.Response(
          '<!DOCTYPE HTML><html><head></head><body>'
          '<script>document.domain="netease.com";</script>'
          '<textarea>{"url": "https://x19.fp.ps.netease.com/file/example?a=1&amp;b=2", '
          '"mime": "image/png; charset=binary", "fsize": 3, "md5": "abc", "picSize": [992, 558]}</textarea></body></html>',
          200,
          headers: {
            'content-type': 'text/html; charset=utf-8',
            'x-ntes-signature': 'signed-proof',
          },
        );
      }),
    );
    addTearDown(api.close);
    final uploaded = await api.uploadResourceFile(
      name: 'cover.png',
      length: 3,
      stream: Stream.value([1, 2, 3]),
      fileType: 'image',
    );
    expect(uploaded.url, 'https://x19.fp.ps.netease.com/file/example?a=1&b=2');
    expect(uploaded.signedValue, {
      'body':
          '{"url": "https://x19.fp.ps.netease.com/file/example?a=1&b=2", "mime": "image/png; charset=binary", "fsize": 3, "md5": "abc", "picSize": [992, 558]}',
      'file_type': 'image',
      'sign': 'signed-proof',
    });
  });

  test(
    'upload protocol errors are distinguished from platform login errors',
    () async {
      for (final scenario in [
        (
          status: 200,
          body: '<html>upstream gateway error</html>',
          signature: 'signed',
          message: '响应格式异常',
        ),
        (
          status: 200,
          body: '<textarea>{"url":"https://example.com/image"}</textarea>',
          signature: '',
          message: '响应格式异常',
        ),
        (
          status: 200,
          body: '<textarea>{invalid}</textarea>',
          signature: 'signed',
          message: '响应格式异常',
        ),
        (
          status: 200,
          body: '<textarea>{}</textarea><textarea>{}</textarea>',
          signature: 'signed',
          message: '响应格式异常',
        ),
        (status: 401, body: 'Require Token', signature: '', message: '上传凭证'),
        (
          status: 413,
          body: '<html>Request Entity Too Large</html>',
          signature: '',
          message: '大小限制',
        ),
        (
          status: 503,
          body: '<html>Service Unavailable</html>',
          signature: '',
          message: 'HTTP 503',
        ),
      ]) {
        final api = McDevApi(
          cookie: '',
          category: 'pe',
          client: MockClient((request) async {
            if (request.url.host == 'mc-launcher.webapp.163.com') {
              return ok({'token': 'upload'});
            }
            return http.Response(
              scenario.body,
              scenario.status,
              headers: {'x-ntes-signature': scenario.signature},
            );
          }),
        );
        addTearDown(api.close);
        await expectLater(
          api.uploadResourceFile(
            name: 'cover.png',
            length: 1,
            stream: Stream.value([1]),
            fileType: 'image',
          ),
          throwsA(
            isA<McDevException>().having(
              (e) => e.message,
              'message',
              allOf(contains(scenario.message), isNot(contains('登录'))),
            ),
          ),
        );
      }
    },
  );

  test(
    'review uses independent PUT and preserves queue confirmation semantics',
    () async {
      final requests = <http.Request>[];
      final api = McDevApi(
        cookie: '',
        category: 'pe',
        client: MockClient((request) async {
          requests.add(request);
          return ok({
            'need_check_apply': requests.length == 1,
            'queue_length': 42,
          });
        }),
      );
      addTearDown(api.close);
      final pending = await api.submitResourceReview(
        resourceCategory: 'pe',
        itemId: '123',
        notes: '修复说明',
      );
      expect(pending['data']['need_check_apply'], true);
      expect(requests.length, 1); // No hidden automatic retry/confirmation.
      await api.submitResourceReview(
        resourceCategory: 'pe',
        itemId: '123',
        notes: '修复说明',
        confirmQueue: true,
      );
      for (final r in requests) {
        expect(r.method, 'PUT');
        expect(r.url.path, '/items/categories/pe/123/apply_review');
        expect(jsonDecode(r.body)['apply_review_text'], '修复说明');
      }
      expect(jsonDecode(requests.first.body)['is_check_apply'], false);
      expect(jsonDecode(requests.last.body)['is_check_apply'], true);
    },
  );

  test('feedback singular endpoint handles HTML object response', () async {
    final api = McDevApi(
      cookie: '',
      category: 'pe',
      client: MockClient((r) async {
        expect(r.url.path, '/items/categories/pe/123/feedback');
        return ok({'feedback': '<p>需要修复贴图</p>', 'op_time': '2026-09-27'});
      }),
    );
    addTearDown(api.close);
    expect(
      (await api.fetchResourceFeedbacks(
        resourceCategory: 'pe',
        itemId: '123',
      )).single['feedback'],
      contains('修复贴图'),
    );
  });

  test(
    'editing preserves uploaded files, nested synchronization and unknown settings',
    () {
      final source = testResource()
        ..addAll({
          'mc_version': '',
          'future_setting': {'enabled': true},
          'sync_item_info': {'item_id': '456', 'info': '<p>PC</p>'},
          'prerequisite_items': [
            {'item_id': '789', 'item_name': '前置'},
          ],
        });
      final draft = ResourceDraft(category: 'pe', source: source);
      draft.set('sync_item_info.info', '<p>更新</p>');
      draft.set('pri_type', '2');
      final result = draft.toPayload();
      expect(result['item_id'], isNull);
      expect(result['status'], isNull);
      expect(result['pri_type'], 2);
      expect(result['mc_version'], isEmpty);
      expect(result['res'], source['res']);
      expect(result['channel'], source['channel']);
      expect(result['future_setting'], {'enabled': true});
      expect(result['sync_item_info'], {'item_id': '456', 'info': '<p>更新</p>'});
      expect(result['prerequisite_item_ids'], ['789']);
      expect(
        (source['sync_item_info'] as Map)['info'],
        '<p>PC</p>',
      ); // Deep copy.
    },
  );

  test('validation uses special skin channels and typed price constraints', () {
    final options = ResourceOptions(testOptions);
    final draft = ResourceDraft(category: 'pe', source: testResource());
    expect(draft.validate(options), isEmpty);
    draft.set('price_type', 'diamond');
    draft.set('price', 'abc');
    expect(draft.validate(options), contains('价格必须是非负整数'));
    draft.set('price', 15);
    expect(draft.validate(options).join(), contains('步进'));
    draft.set('price_type', 'free');
    draft.set('price', 0);
    draft.set('pri_type', 4);
    draft.set('sub_type', 13);
    draft.set('body_type', 'normal');
    draft.set('channel', [
      {'channel_id': 5, 'channel_url': 'skin-image'},
    ]);
    expect(draft.validate(options), isEmpty);
  });

  test(
    'status actions do not offer publication while reviewing or deletion after release',
    () {
      final review = ResourceItem.fromJson(
        'pe',
        testResource(status: 'reviewing'),
      );
      expect(resourceActions(review), [('cancel_review', '撤销审核')]);
      final online = ResourceItem.fromJson(
        'pe',
        testResource(status: 'online'),
      );
      expect(resourceActions(online), isEmpty);
      final pc = ResourceItem.fromJson('comp', testResource());
      expect(
        resourceActions(pc).map((e) => e.$1),
        isNot(contains('self-test-apply')),
      );
    },
  );
  test('ranked pricing keeps server tiers and channel constraints', () {
    final settings = ResourcePriceSettings({
      'new_price_rank_switch': '1',
      'item_price_rank':
          '[{"price":100},{"price":200},{"price":300},{"price":400}]',
    }, hasChannel: true);
    final draft = ResourceDraft(category: 'pe', source: testResource());
    draft.set('price_type', 'diamond');
    draft.set('price', 200);
    draft.set('price_rank', 1);
    draft.set('other_channel_price', 100);
    draft.set('channel_price_rank', 0);
    expect(settings.validate(draft), contains('渠道平台价格不能低于官方平台价格'));
    draft.set('channel_price_rank', 1);
    draft.set('other_channel_price', 200);
    expect(settings.validate(draft), isEmpty);
    draft.set('price', 250);
    expect(settings.validate(draft), contains('请选择官方平台定价档位'));
    expect(settings.choices(current: 1).map((e) => e['id']), [0, 1, 2]);
  });

  test(
    'PE prerequisite query selects platform prerequisite category',
    () async {
      final api = McDevApi(
        cookie: '',
        category: 'pe',
        client: MockClient((r) async {
          expect(r.url.queryParameters, containsPair('pri_type', '9'));
          expect(r.url.queryParameters, containsPair('item_name', '前置'));
          return ok({
            'list': [
              {'item_id': '7', 'item_name': '前置'},
            ],
          });
        }),
      );
      addTearDown(api.close);
      expect((await api.searchRequirements('pe', '前置')).single['item_id'], '7');
    },
  );

  test('permission-controlled actions and synchronized PC restrictions', () {
    final pc = ResourceItem.fromJson(
      'comp',
      testResource(status: 'reviewing')..['remindable'] = true,
    );
    expect(resourceActions(pc), contains(('remind', '催促审核')));
    final synced = ResourceItem.fromJson(
      'comp',
      testResource()..['sync_pc_flag'] = true,
    );
    expect(resourceActions(synced), isEmpty);
    final online = ResourceItem.fromJson('pe', testResource(status: 'online'));
    expect(
      resourceActions(
        online,
        permissions: {'exempt_review_weak_offline_remain': 1},
      ),
      contains(('exempt_review', '免审弱下架')),
    );
  });
  test(
    'DLC update preserves other slave packages and refreshes self metadata',
    () {
      final draft = ResourceDraft(
        category: 'pe',
        source: testResource()
          ..['dlc_info'] = {
            'dlc_switch': true,
            'dlc_type': 'slave',
            'master': {'item_id': '1', 'item_name': '主包'},
            'slave_list': [
              {'item_id': '2', 'item_name': '其他副包'},
              {'item_id': '123', 'item_name': '旧名称'},
            ],
          },
      );
      draft.set('item_name', '新名称');
      final dlc = draft.toPayload()['dlc_info'];
      expect(dlc['slave_list'], [
        {'item_id': '2', 'item_name': '其他副包'},
        {'item_id': '123', 'item_name': '新名称'},
      ]);
      draft.set('dlc_info.master', {});
      expect(
        draft.validate(ResourceOptions(testOptions)),
        contains('请选择 DLC 主包'),
      );
    },
  );

  test(
    'server errors and invalid responses mark save outcomes as uncertain',
    () async {
      for (final response in [
        http.Response('upstream failed', 502),
        http.Response('not json', 200),
      ]) {
        final api = McDevApi(
          cookie: '',
          category: 'pe',
          client: MockClient((_) async => response),
        );
        await expectLater(
          api.saveResource(resourceCategory: 'pe', payload: {}),
          throwsA(
            isA<McDevException>().having(
              (e) => e.outcomeUnknown,
              'outcomeUnknown',
              true,
            ),
          ),
        );
        api.close();
      }
    },
  );
}
