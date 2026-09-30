import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/main.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_test.dart' show host, viewport;

const peId = '4685624094850259947';
const pcId = '4635523327531425944';
const peDetail = {
  'item_id': peId,
  'res_name': '森林探险',
  'developer_name': '方块工作室',
  'mod_version': '3.7',
  'download_num': '21322',
  'stars': 3.4,
  'remark_num': 472,
  'comment_count': 530,
  'diamond': 300,
  'points': 0,
  'normal_number': '6702266',
  'info': '<p><strong>探索新的森林</strong></p><p>支持多人协作。</p>',
};
const pcDetail = {
  'entity_id': pcId,
  'name': '连锁采集',
  'developer_name': '方块工作室',
  'item_version': '8.4',
  'download_num': 9794198,
  'like_num': 182677,
  'normal_number': '1805564',
  'vanity_number': '7015',
  'brief_summary': ' ',
};

LeaderboardEntry resourceEntry([String type = 'pe_hot']) => LeaderboardEntry(
  {
    'item_id': type.startsWith('pc_') ? pcId : peId,
    'item_name': '榜单中的名称',
    'developer_name': '榜单作者',
  },
  type: type,
  fallbackRank: 1,
);

http.Response detailResponse(Object? entity, {int code = 0}) => http.Response(
  jsonEncode({'code': code, 'entity': entity}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class ResourceDetailBackend {
  final requests = <http.Request>[];
  bool fail = false;
  bool gallery = false;
  String? intro;
  Completer<void>? pending;

  Iterable<http.Request> get details =>
      requests.where((r) => r.method == 'POST');

  McDevApi api() => McDevApi(
    cookie: 'developer-cookie=private',
    category: 'pe',
    client: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/data_analysis/overview/') {
        return http.Response('{"status":"ok","data":{}}', 200);
      }
      if (request.url.path.startsWith('/users/')) {
        return http.Response(
          '{"status":"ok","data":{"can_us_rank":true}}',
          200,
        );
      }
      if (request.url.path.startsWith('/square/')) {
        final type = request.url.queryParameters['type']!;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {
              'count': 1,
              'data': [
                if (type == 'hot_search')
                  {'content': '探索', 'hot_search_value': 1.2}
                else
                  resourceEntry(type).raw,
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      await pending?.future;
      if (fail) return detailResponse(null, code: 16);
      return detailResponse(
        request.url.host.startsWith('x19')
            ? pcDetail
            : {
                ...peDetail,
                if (intro != null) 'info': intro,
                if (gallery) 'title_image_url': 'https://example.test/icon.png',
                if (gallery)
                  'pic_url_list': [
                    'https://example.test/one.png',
                    'https://example.test/two.png',
                  ],
              },
      );
    }),
  );
}

Finder iconButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is OreIconButton && widget.tooltip == tooltip,
);

Widget dialogLauncher(
  ResourceDetailBackend backend, {
  String type = 'pe_hot',
}) => Builder(
  builder: (context) => TextButton(
    onPressed: () => showOreDialog<void>(
      context: context,
      builder: (_) => LeaderboardResourceDialog(
        entry: resourceEntry(type),
        apiFactory: backend.api,
      ),
    ),
    child: const Text('打开详情'),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'mobile public API signs exact ID and sends no account credentials',
    () async {
      final backend = ResourceDetailBackend();
      final api = backend.api();
      addTearDown(api.close);
      final detail = await api.fetchLeaderboardResource(resourceEntry());
      final request = backend.requests.single;
      expect(
        request.url.toString(),
        'https://g79apigatewayobt.nie.netease.com/h5/pe-item-detail-v2',
      );
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'channel_id': 5,
        'item_id': peId,
        'sign': '2846eb502c8e995d444d24e6fe05464c',
      });
      expect(request.headers.keys.map((key) => key.toLowerCase()), [
        'content-type',
      ]);
      expect(detail.name, '森林探险');
      expect(detail.downloads, 21322);
      expect(detail.rating, 3.4);
      expect(detail.ratingCount, 472);
      expect(detail.commentCount, 530);
      expect(detail.priceLabel, '300 钻石');
      expect(detail.componentCode, '6702266');
    },
  );

  test(
    'PC query uses its own endpoint and preserves unavailable prices',
    () async {
      final backend = ResourceDetailBackend();
      final api = backend.api();
      addTearDown(api.close);
      final detail = await api.fetchLeaderboardResource(
        resourceEntry('pc_like'),
      );
      final request = backend.requests.single;
      expect(
        request.url.toString(),
        'https://x19mclobt.nie.netease.com/item/query/search-by-iid',
      );
      expect(jsonDecode(request.body), {'item_id': pcId});
      expect(request.headers.keys.map((key) => key.toLowerCase()), [
        'content-type',
      ]);
      expect(detail.isDesktop, isTrue);
      expect(detail.name, '连锁采集');
      expect(detail.likes, 182677);
      expect(detail.componentCode, '7015');
      expect(detail.priceLabel, isNull);
      expect(detail.rating, isNull);
      expect(detail.description, isEmpty);
    },
  );

  test(
    'keyword-only and invalid resource IDs cannot trigger a query',
    () async {
      final backend = ResourceDetailBackend();
      final api = backend.api();
      addTearDown(api.close);
      for (final id in [null, '', '0', '../123', '12.5', 'NaN']) {
        final entry = LeaderboardEntry(
          {'item_id': id, 'content': '搜索词'},
          type: 'hot_search',
          fallbackRank: 1,
        );
        expect(entry.hasResourceDetails, isFalse);
        await expectLater(
          api.fetchLeaderboardResource(entry),
          throwsArgumentError,
        );
      }
      expect(backend.requests, isEmpty);
    },
  );

  test(
    'non-success, malformed and mismatched detail responses fail safely',
    () async {
      for (final response in [
        http.Response('unavailable', 503),
        http.Response('not json', 200),
        http.Response('[]', 200),
        detailResponse(null, code: 16),
        detailResponse(peDetail, code: 12),
        detailResponse(null),
        detailResponse({}),
        detailResponse({...peDetail, 'item_id': '123'}),
      ]) {
        final api = McDevApi(
          cookie: '',
          category: 'pe',
          client: MockClient((_) async => response),
        );
        addTearDown(api.close);
        await expectLater(
          api.fetchLeaderboardResource(resourceEntry()),
          throwsA(isA<McDevException>()),
        );
      }
    },
  );

  test(
    'public detail values distinguish zero, missing and invalid numbers',
    () {
      final missing = LeaderboardResourceDetail.fromJson({}, isDesktop: false);
      expect(missing.downloads, isNull);
      expect(missing.priceLabel, isNull);
      final free = LeaderboardResourceDetail.fromJson({
        'diamond': 0,
        'points': '0',
        'download_num': 0,
        'stars': 'NaN',
        'title_image_url': 'https://example.test/a.png',
        'pic_url_list': [
          'https://example.test/a.png',
          'https://example.test/b.png',
          null,
          'file:///private',
          'javascript:test',
        ],
      }, isDesktop: false);
      expect(free.priceLabel, '免费');
      expect(free.downloads, 0);
      expect(free.rating, isNull);
      expect(free.iconUrl, 'https://example.test/a.png');
      expect(free.images, ['https://example.test/b.png']);
      expect(
        LeaderboardResourceDetail.fromJson({
          'diamond': 0,
        }, isDesktop: false).priceLabel,
        isNull,
      );
    },
  );

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      'home opens a resource dialog and retains rank state at $size',
      (tester) async {
        viewport(tester, size);
        final backend = ResourceDetailBackend();
        await tester.pumpWidget(
          host(HomePage(apiFactory: backend.api), dark: size.width < 900),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(const ValueKey('rank-entry-pe_hot-1'));
        await tester.ensureVisible(entry);
        final position = tester.getTopLeft(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(LeaderboardResourceDialog), findsOneWidget);
        expect(find.text('森林探险'), findsOneWidget);
        expect(find.text('21,322'), findsOneWidget);
        expect(find.text('300 钻石'), findsOneWidget);
        await tester.ensureVisible(find.text('探索新的森林', findRichText: true));
        expect(find.text('探索新的森林', findRichText: true), findsOneWidget);
        expect(find.textContaining('<p>'), findsNothing);
        await tester.tap(iconButton('关闭资源详情'));
        await tester.pumpAndSettle();
        expect(find.byType(LeaderboardResourceDialog), findsNothing);
        expect(tester.getTopLeft(entry), position);
        expect(backend.details, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keyword-only hot search is not clickable', (tester) async {
    viewport(tester, const Size(1280, 900));
    final backend = ResourceDetailBackend();
    await tester.pumpWidget(host(HomePage(apiFactory: backend.api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rank-type-hot_search')));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('rank-entry-hot_search-1'));
    expect(tester.widget<OreListTile>(entry).onTap, isNull);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardResourceDialog), findsNothing);
    expect(backend.details, isEmpty);
  });

  testWidgets('detail failure retains basic info and retry recovers', (
    tester,
  ) async {
    final backend = ResourceDetailBackend()..fail = true;
    await tester.pumpWidget(host(dialogLauncher(backend)));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('榜单中的名称'), findsOneWidget);
    expect(find.text('手机版 · 榜单作者'), findsOneWidget);
    expect(find.text('暂时找不到该资源，可能已下架'), findsOneWidget);
    backend.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('森林探险'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(backend.details, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardResourceDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing while loading ignores the late response', (
    tester,
  ) async {
    final backend = ResourceDetailBackend()..pending = Completer<void>();
    await tester.pumpWidget(host(dialogLauncher(backend)));
    await tester.tap(find.text('打开详情'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(OreLoadingIndicator), findsOneWidget);
    await tester.tap(iconButton('关闭资源详情'));
    await tester.pumpAndSettle();
    backend.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardResourceDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC details stay honest when intro and prices are absent', (
    tester,
  ) async {
    viewport(tester, const Size(360, 640));
    final backend = ResourceDetailBackend();
    await tester.pumpWidget(
      host(dialogLauncher(backend, type: 'pc_download'), dark: true),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('连锁采集'), findsOneWidget);
    expect(find.text('9,794,198'), findsOneWidget);
    expect(find.text('182,677'), findsOneWidget);
    expect(find.text('暂无资源介绍'), findsOneWidget);
    expect(find.text('免费'), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardResourceDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery handles failed images and supports desktop arrows', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final backend = ResourceDetailBackend()..gallery = true;
    await tester.pumpWidget(host(dialogLauncher(backend)));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(iconButton('下一张展示图'));
    await tester.tap(iconButton('下一张展示图'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(
      tester.widget<OreIconButton>(iconButton('下一张展示图')).onPressed,
      isNull,
    );
    expect(find.text('展示图暂时无法加载'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop dialog puts icon beside title and intro beside gallery', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final backend = ResourceDetailBackend()..gallery = true;
    await tester.pumpWidget(host(dialogLauncher(backend)));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    final icon = tester.getRect(
      find.byKey(const ValueKey('resource-title-icon')),
    );
    final title = tester.getRect(find.text('森林探险'));
    final gallery = tester.getRect(find.byType(PageView));
    final intro = tester.getRect(find.text('资源介绍'));
    expect(icon.width, icon.height);
    expect(icon.right, lessThan(title.left));
    expect(icon.top, title.top);
    expect(gallery.right, lessThan(intro.left));
    expect(
      find.text('探索新的森林', findRichText: true).hitTestable(),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(OreCard)).height, lessThan(560));

    // Resizing the open dialog must keep the selected image and remain usable.
    await tester.tap(iconButton('下一张展示图'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('resource-detail-columns')), findsNothing);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.ensureVisible(find.text('探索新的森林', findRichText: true));
    expect(
      find.text('探索新的森林', findRichText: true).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 900), const Size(1280, 480)]) {
    testWidgets('desktop scroll moves only intro at $size', (tester) async {
      viewport(tester, size);
      final backend = ResourceDetailBackend()
        ..gallery = true
        ..intro = List.generate(40, (index) => '<p>简介第 $index 段</p>').join();
      await tester.pumpWidget(
        host(dialogLauncher(backend), dark: size.height < 600),
      );
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      final fixed = [
        find.text('森林探险'),
        find.text('21,322'),
        find.text('300 钻石'),
        find.text('资源介绍'),
        find.byType(PageView),
      ];
      final positions = fixed.map(tester.getTopLeft).toList();
      final firstParagraph = find.text('简介第 0 段', findRichText: true);
      expect(firstParagraph.hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('resource-intro-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(firstParagraph.hitTestable(), findsNothing);
      expect(fixed.map(tester.getTopLeft).toList(), positions);
      expect(find.text('21,322').hitTestable(), findsOneWidget);
      expect(find.text('资源介绍').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
