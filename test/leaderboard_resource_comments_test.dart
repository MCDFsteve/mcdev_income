import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/core.dart';

const _resourceId = '4685624094850259947';

LeaderboardEntry _entry({bool desktop = false, String id = _resourceId}) =>
    LeaderboardEntry(
      {'item_id': id},
      type: desktop ? 'pc_like' : 'pe_hot',
      fallbackRank: 1,
    );

Map<String, dynamic> _comment(String id) => {
  'comment_id': id,
  'nickname': '冒险家',
  'user_comment': '期待更新\n很好玩',
  'stars': 4,
  'publish_time': 1772512537,
  'good_num': 14,
  'commented_num': 2,
  'head_image': 'https://example.test/avatar.png',
  'is_developer': 0,
};

Map<String, dynamic> _entity({int length = 20}) => {
  'entity_id': _resourceId,
  'master_comment_count': 43,
  'comment_list': List.generate(length, (index) => _comment('${index + 10}')),
  'top_comment_list': [
    {..._comment('1'), 'is_developer': 1},
  ],
  'hot_comment_list': [],
};

http.Response _response(Object? entity, {int code = 0}) => http.Response(
  jsonEncode({'code': code, 'entity': entity}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

McDevApi _api(Future<http.Response> Function(http.Request) handler) => McDevApi(
  cookie: 'private-developer-cookie',
  category: 'pe',
  client: MockClient(handler),
);

void main() {
  test(
    'public comments use the exact signed body and no credentials',
    () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return _response(_entity());
      });
      addTearDown(api.close);

      final result = await api.fetchLeaderboardResourceComments(_entry());
      expect(sent.method, 'POST');
      expect(
        sent.url.toString(),
        'https://g79apigatewayobt.nie.netease.com/h5/pe-user-comment',
      );
      expect(jsonDecode(sent.body), {
        'item_id': _resourceId,
        'length': 20,
        'sort_type': 0,
        'order': 0,
        'sign': 'bb2a21ef419c8b4fe4745311f5709ccf',
      });
      expect(sent.headers.keys.map((key) => key.toLowerCase()), [
        'content-type',
      ]);
      expect(result.total, 43);
      expect(result.requestedLength, 20);
      expect(result.comments.length, 21);
      expect(result.hasMore, isTrue);
    },
  );

  test(
    'requesting more replaces a growing prefix and stops at the end',
    () async {
      final lengths = <int>[];
      final api = _api((request) async {
        final length = jsonDecode(request.body)['length'] as int;
        lengths.add(length);
        return _response(_entity(length: length > 42 ? 42 : length));
      });
      addTearDown(api.close);

      final first = await api.fetchLeaderboardResourceComments(_entry());
      final next = await api.fetchLeaderboardResourceComments(
        _entry(),
        length: first.requestedLength + 20,
      );
      final last = await api.fetchLeaderboardResourceComments(
        _entry(),
        length: next.requestedLength + 20,
      );
      expect(lengths, [20, 40, 60]);
      expect(
        next.comments.take(first.comments.length).map((c) => c.id),
        first.comments.map((c) => c.id),
      );
      expect(next.hasMore, isTrue);
      expect(last.comments.length, 43);
      expect(last.hasMore, isFalse);
    },
  );

  test(
    'pinned and hot duplicates are displayed once with correct precedence',
    () {
      final result = LeaderboardResourceComments.fromJson({
        ..._entity(length: 2),
        'top_comment_list': [_comment('10')],
        'hot_comment_list': [_comment('10'), _comment('11')],
      }, requestedLength: 2);
      expect(result.comments.map((c) => c.id), ['10', '11']);
      expect(result.comments.first.isPinned, isTrue);
      expect(result.comments.last.isHot, isTrue);
      expect(() => result.comments.clear(), throwsUnsupportedError);
    },
  );

  test('comment fields retain scores, Unicode, dates and reply counts', () {
    final result = LeaderboardResourceComment.fromJson({
      ..._comment('23'),
      'is_developer': 1,
    });
    expect(result.author, '冒险家');
    expect(result.text, '期待更新\n很好玩');
    expect(result.rating, 4);
    expect(
      result.publishedAt,
      DateTime.fromMillisecondsSinceEpoch(1772512537000, isUtc: true),
    );
    expect(result.likes, 14);
    expect(result.replyCount, 2);
    expect(result.avatarUrl, 'https://example.test/avatar.png');
    expect(result.isDeveloper, isTrue);
  });

  test('missing and invalid fields do not fabricate ratings or dates', () {
    for (final rating in [null, 0, -1, 6, 'NaN', 'Infinity']) {
      final comment = LeaderboardResourceComment.fromJson({
        'stars': rating,
        'publish_time': rating,
        'good_num': -1,
        'head_image': 'javascript:alert(1)',
      });
      expect(comment.rating, isNull);
      expect(comment.likes, isNull);
      expect(comment.avatarUrl, isNull);
    }
    for (final timestamp in [null, 0, -1, 'NaN', 'Infinity', 1e20]) {
      expect(
        LeaderboardResourceComment.fromJson({
          'publish_time': timestamp,
        }).publishedAt,
        isNull,
      );
    }
    final missing = LeaderboardResourceComments.fromJson({
      'comment_list': [],
    }, requestedLength: 20);
    expect(missing.total, isNull);
    expect(missing.hasMore, isFalse);
    final empty = LeaderboardResourceComments.fromJson({
      'comment_list': [],
      'master_comment_count': 0,
    }, requestedLength: 20);
    expect(empty.total, 0);
    expect(empty.comments, isEmpty);
    expect(empty.hasMore, isFalse);
  });

  test(
    'invalid IDs and PC comments never send misleading mobile queries',
    () async {
      final requests = <http.Request>[];
      final api = _api((request) async {
        requests.add(request);
        return _response(_entity());
      });
      addTearDown(api.close);
      await expectLater(
        api.fetchLeaderboardResourceComments(_entry(desktop: true)),
        throwsUnsupportedError,
      );
      await expectLater(
        api.fetchLeaderboardResourceComments(_entry(id: '../123')),
        throwsArgumentError,
      );
      for (final length in [0, -1]) {
        await expectLater(
          api.fetchLeaderboardResourceComments(_entry(), length: length),
          throwsArgumentError,
        );
      }
      expect(requests, isEmpty);
    },
  );

  test('malformed, non-success and mismatched responses fail safely', () async {
    for (final response in [
      http.Response('unavailable', 503),
      http.Response('not json', 200),
      http.Response('[]', 200),
      _response(null, code: 16),
      _response(_entity(), code: 12),
      _response(null),
      _response({}),
      _response({..._entity(), 'entity_id': '123'}),
      _response({..._entity(), 'comment_list': {}}),
      _response({..._entity(), 'top_comment_list': 123}),
    ]) {
      final api = _api((_) async => response);
      addTearDown(api.close);
      await expectLater(
        api.fetchLeaderboardResourceComments(_entry()),
        throwsA(isA<McDevException>()),
      );
    }
  });

  test('connection errors become a recoverable comment error', () async {
    final api = _api((_) async => throw http.ClientException('offline'));
    addTearDown(api.close);
    await expectLater(
      api.fetchLeaderboardResourceComments(_entry()),
      throwsA(
        isA<McDevException>().having(
          (error) => error.toString(),
          'message',
          contains('无法连接评论服务'),
        ),
      ),
    );
  });
}
