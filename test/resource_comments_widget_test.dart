import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/main.dart';

import 'dashboard_test.dart' show host, viewport;
import 'leaderboard_resource_test.dart'
    show peId, peDetail, pcDetail, resourceEntry, detailResponse, iconButton;

class CommentsBackend {
  final lengths = <int>[];
  bool fail = false;
  bool empty = false;
  bool gallery = false;
  Completer<void>? pending;

  Map<String, Object> comment(int id) => {
    'comment_id': '$id',
    'nickname': id == 1 ? '方块工作室' : '玩家 $id',
    'user_comment': id == 1 ? '感谢大家的支持，欢迎分享游玩体验。' : '第 $id 条评论：森林很漂亮，探索体验很好。',
    'stars': id == 1 ? 0 : 4,
    'publish_time': 1780000000,
    'good_num': id == 1 ? 23 : 2,
    'commented_num': id == 1 ? 3 : 0,
    'is_developer': id == 1 ? 1 : 0,
  };

  McDevApi api() => McDevApi(
    cookie: 'private-cookie',
    category: 'pe',
    client: MockClient((request) async {
      if (request.url.path != '/h5/pe-user-comment') {
        return detailResponse(
          request.url.host.startsWith('x19')
              ? pcDetail
              : {
                  ...peDetail,
                  if (gallery) 'pic_url_list': ['https://example.test/one.png'],
                },
        );
      }
      final length = jsonDecode(request.body)['length'] as int;
      lengths.add(length);
      await pending?.future;
      if (fail) return http.Response('unavailable', 503);
      return detailResponse({
        'entity_id': peId,
        'master_comment_count': empty ? 0 : 22,
        'top_comment_list': [if (!empty) comment(1)],
        'comment_list': [
          if (!empty)
            for (var i = 1; i <= (length > 22 ? 22 : length); i++) comment(i),
        ],
      });
    }),
  );
}

Widget launcher(CommentsBackend backend, {String type = 'pe_hot'}) => Builder(
  builder: (context) => TextButton(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => LeaderboardResourceDialog(
        entry: resourceEntry(type),
        apiFactory: backend.api,
      ),
    ),
    child: const Text('打开详情'),
  ),
);

Future<void> openComments(WidgetTester tester) async {
  await tester.tap(find.text('打开详情'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('评论与评分'));
  await tester.tap(find.text('评论与评分'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (platform, size) in [
    (TargetPlatform.android, const Size(360, 640)),
    (TargetPlatform.iOS, const Size(390, 844)),
  ]) {
    testWidgets(
      'phone comments tab is visible before scrolling on $platform',
      (tester) async {
        viewport(tester, size);
        final backend = CommentsBackend()..gallery = true;
        await tester.pumpWidget(
          host(launcher(backend), dark: platform == TargetPlatform.iOS),
        );
        await tester.tap(find.text('打开详情'));
        await tester.pumpAndSettle();
        expect(find.text('评论与评分').hitTestable(), findsOneWidget);
        expect(backend.lengths, isEmpty);
        await tester.tap(find.text('评论与评分'));
        await tester.pumpAndSettle();
        expect(find.text('3.4 / 5').hitTestable(), findsOneWidget);
        expect(find.text('感谢大家的支持，欢迎分享游玩体验。').hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text('加载更多评论'));
        await tester.pumpAndSettle();
        expect(find.text('资源介绍').hitTestable(), findsOneWidget);
        await tester.tap(find.text('资源介绍'));
        await tester.pumpAndSettle();
        expect(find.text('总下载').hitTestable(), findsOneWidget);
        expect(backend.lengths, [20]);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      'comments load on demand with scores and replace longer prefix at $size',
      (tester) async {
        viewport(tester, size);
        final backend = CommentsBackend();
        await tester.pumpWidget(
          host(launcher(backend), dark: size.width < 800),
        );
        await tester.tap(find.text('打开详情'));
        await tester.pumpAndSettle();
        expect(backend.lengths, isEmpty);
        await tester.ensureVisible(find.text('评论与评分'));
        await tester.tap(find.text('评论与评分'));
        await tester.pumpAndSettle();
        expect(find.text('3.4 / 5'), findsOneWidget);
        expect(find.text('472 人评分'), findsOneWidget);
        expect(find.text('置顶'), findsOneWidget);
        expect(find.text('开发者'), findsOneWidget);
        expect(find.text('★ 4.0 分'), findsWidgets);
        expect(find.textContaining('23 人点赞 · 3 条回复'), findsOneWidget);
        expect(find.text('感谢大家的支持，欢迎分享游玩体验。'), findsOneWidget);

        await tester.ensureVisible(find.text('加载更多评论'));
        backend.fail = true;
        await tester.tap(find.text('加载更多评论'));
        await tester.pumpAndSettle();
        expect(find.text('感谢大家的支持，欢迎分享游玩体验。'), findsOneWidget);
        backend.fail = false;
        await tester.ensureVisible(find.text('重试加载评论'));
        await tester.tap(find.text('重试加载评论'));
        await tester.pumpAndSettle();
        expect(backend.lengths, [20, 40, 40]);
        expect(find.text('感谢大家的支持，欢迎分享游玩体验。'), findsOneWidget);
        expect(find.textContaining('第 22 条评论'), findsOneWidget);
        expect(find.text('加载更多评论'), findsNothing);
        await tester.ensureVisible(find.text('资源介绍'));
        await tester.tap(find.text('资源介绍'));
        await tester.pumpAndSettle();
        expect(find.text('探索新的森林', findRichText: true), findsOneWidget);
        await tester.tap(find.text('评论与评分'));
        await tester.pumpAndSettle();
        expect(backend.lengths, [20, 40, 40]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'comment errors retry independently and empty results are explicit',
    (tester) async {
      final backend = CommentsBackend()..fail = true;
      await tester.pumpWidget(host(launcher(backend)));
      await openComments(tester);
      expect(find.text('森林探险'), findsOneWidget);
      expect(find.text('评论暂时无法获取，请稍后重试'), findsOneWidget);
      expect(find.text('3.4 / 5'), findsOneWidget);
      backend
        ..fail = false
        ..empty = true;
      await tester.ensureVisible(find.text('重试加载评论'));
      await tester.tap(find.text('重试加载评论'));
      await tester.pumpAndSettle();
      expect(find.text('暂无评论'), findsOneWidget);
      expect(find.text('加载更多评论'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing with pending comments ignores late response', (
    tester,
  ) async {
    final backend = CommentsBackend()..pending = Completer<void>();
    await tester.pumpWidget(host(launcher(backend)));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('评论与评分'));
    await tester.tap(find.text('评论与评分'));
    await tester.pump();
    await tester.tap(iconButton('关闭资源详情'));
    await tester.pumpAndSettle();
    backend.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardResourceDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC comments explain unavailable data without a mobile query', (
    tester,
  ) async {
    viewport(tester, const Size(360, 640));
    final backend = CommentsBackend();
    await tester.pumpWidget(
      host(launcher(backend, type: 'pc_download'), dark: true),
    );
    await openComments(tester);
    expect(find.text('当前公开接口暂不提供端游评论与评分'), findsOneWidget);
    expect(find.text('暂无评论'), findsNothing);
    expect(backend.lengths, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 480), const Size(900, 360)]) {
    testWidgets('gallery and comments stay usable in a short window at $size', (
      tester,
    ) async {
      viewport(tester, size);
      final backend = CommentsBackend()..gallery = true;
      await tester.pumpWidget(host(launcher(backend)));
      await openComments(tester);
      await tester.ensureVisible(find.text('感谢大家的支持，欢迎分享游玩体验。'));
      expect(find.text('感谢大家的支持，欢迎分享游玩体验。').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('加载更多评论'));
      expect(find.text('加载更多评论').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
