import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/main.dart';
import 'package:mcdev_income/cli/cli.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'resource_workflow_test.dart' as fixtures;

class DashboardBackend {
  final requests = <Uri>[];
  bool advanced = true, failOverview = false, failDetail = false;
  int rankTotal = 51;
  int unread = 2;
  final read = <String>{};
  Completer<void>? slowRank, slowDetail;

  McDevApi api([String cookie = 'test', String category = 'pe']) => McDevApi(
    cookie: cookie,
    category: category,
    client: MockClient((r) async {
      requests.add(r.url);
      final path = r.url.path, q = r.url.queryParameters;
      if (path == '/data_analysis/overview/') {
        if (failOverview) {
          return http.Response(
            '{"status":"error","msg":"overview unavailable"}',
            503,
          );
        }
        return fixtures.ok({'this_month_diamond': 123456789});
      }
      if (path.startsWith('/users/')) {
        return fixtures.ok({'can_us_rank': advanced});
      }
      if (path.startsWith('/square/')) {
        if (q['type'] == 'pe_sell') await slowRank?.future;
        final offset = int.parse(q['start']!);
        return fixtures.ok({
          'count': rankTotal,
          'data': [
            {
              'rank': offset + 1,
              'item_id': '$offset',
              'item_name': '${q['type']}-${q['first_type']}-$offset',
              'rank_change': -2,
            },
          ],
        });
      }
      if (path == '/mailbox/unread/count') {
        return fixtures.ok({'count': unread});
      }
      if (path == '/mailbox/') {
        final offset = q['start'] == '30' ? 30 : 0;
        return fixtures.ok({
          'count': 32,
          'unread_count': unread,
          'mail': [
            for (var i = 1; i <= 2; i++)
              {
                '_id': 'mail${i + offset}',
                'title': '通知 ${i + offset}',
                'have_read': read.contains('mail${i + offset}'),
                'mail_type': 'review_notice',
                'time': '2026-09-27 12:34:00',
              },
          ],
        });
      }
      if (path.startsWith('/mailbox/')) {
        if (failDetail) {
          return http.Response(
            '{"status":"error","msg":"detail unavailable"}',
            503,
          );
        }
        final id = path.split('/').last;
        if (id == 'mail1') await slowDetail?.future;
        if (read.add(id)) unread--;
        return fixtures.ok({
          'detail': '<p><strong>$id 正文</strong></p><p>第二段</p>',
          'sender': '系统',
          'extra_list': [
            {
              'file_name': '性能报告.pdf',
              'file_url': 'https://example.test/report.pdf',
            },
          ],
        });
      }
      throw StateError('Unexpected request: ${r.url}');
    }),
  );
}

Widget host(Widget child, {bool dark = false}) => MaterialApp(
  theme: oreAppTheme(brightness: dark ? Brightness.dark : Brightness.light),
  scrollBehavior: const OreScrollBehavior(),
  home: Scaffold(body: child),
);
void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('platform leaderboard categories, pagination and rank movement', () async {
    final backend = DashboardBackend();
    final client = backend.api();
    addTearDown(client.close);
    for (final type in leaderboardTypes.keys) {
      for (final kind in leaderboardKinds.keys) {
        final page = await client.fetchLeaderboard(
          type: type,
          kind: kind,
          start: 50,
        );
        final request = backend.requests.last;
        expect(
          request.path,
          ['pe_hot', 'hot_search'].contains(type)
              ? '/square/us_rank_list/'
              : '/square/rank_list/',
        );
        expect(
          request.queryParameters['first_type'],
          '${type == 'hot_search' ? 0 : (type.startsWith('pe_') ? {'mods': 2, 'maps': 1, 'textures': 3, 'multiplayer': 6} : {'mods': 3, 'maps': 5, 'textures': 4, 'multiplayer': 11})[kind]}',
        );
        expect(page.items.single.rank, 51);
        expect(page.items.single.change, -2);
        expect(page.total, 51);
      }
    }
    expect(
      LeaderboardEntry(
        {'rank': 1, 'hot_search_value': 1.25},
        type: 'hot_search',
        fallbackRank: 1,
      ).metric,
      '搜索指数 125.0',
    );
    expect(
      LeaderboardEntry(
        {'rank': 3, 'last_rank': 1},
        type: 'pe_hot',
        fallbackRank: 1,
      ).change,
      2,
    );
    expect(
      LeaderboardEntry(
        {'rank': 1, 'last_rank': -1},
        type: 'pe_hot',
        fallbackRank: 1,
      ).isNew,
      true,
    );
    expect(
      LeaderboardEntry({}, type: 'pe_download', fallbackRank: 1).metric,
      isEmpty,
    );
    await expectLater(
      client.fetchLeaderboard(kind: 'unknown'),
      throwsArgumentError,
    );
  });

  test(
    'leaderboard CSV fetches every selected page and preserves raw fields',
    () async {
      final requests = <Uri>[];
      final client = McDevApi(
        cookie: 'test',
        category: 'pe',
        client: MockClient((request) async {
          requests.add(request.url);
          final query = request.url.queryParameters;
          final start = int.parse(query['start']!);
          final span = int.parse(query['span']!);
          if (span > 50) {
            return http.Response(
              '{"status":"error","msg":"params error"}',
              200,
            );
          }
          final isSearch = query['type'] == 'hot_search';
          final total = isSearch ? 1 : 101;
          return fixtures.ok({
            'count': total,
            'data': [
              for (
                var index = start;
                index < total && index < start + span;
                index++
              )
                {
                  'rank': index + 1,
                  'item_id': 'id$index',
                  'item_name': index == 0 ? '中文,"名称' : '名称$index',
                  'developer_name': '作者',
                  'extra': {
                    'tags': ['a', 'b'],
                  },
                },
            ],
          });
        }),
      );
      addTearDown(client.close);
      final progress = <String>[];
      final rows = await fetchLeaderboardExportRows(
        api: client,
        types: {'pe_hot', 'pe_download', 'hot_search'},
        kinds: {'mods', 'maps'},
        onProgress: (done, total) => progress.add('$done/$total'),
      );

      expect(rows, hasLength(405));
      expect(progress, ['1/5', '2/5', '3/5', '4/5', '5/5']);
      expect(requests, hasLength(13));
      for (final type in ['pe_hot', 'pe_download']) {
        expect(
          requests
              .where((uri) => uri.queryParameters['type'] == type)
              .map((uri) => uri.queryParameters['start']),
          ['0', '50', '100', '0', '50', '100'],
        );
      }
      expect(
        requests.where((uri) => uri.queryParameters['type'] == 'hot_search'),
        hasLength(1),
      );
      final csv = buildLeaderboardCsv(rows);
      expect(csv, startsWith('\ufeff"榜单","类别","排名"'));
      expect(csv, contains('"中文,""名称"'));
      expect(csv, contains('"原始字段:extra"'));
      expect(csv, contains('"{""tags"":[""a"",""b""]}"'));
      expect(csv, contains('"热搜榜","全部"'));
      expect(csv.split('\r\n'), hasLength(407));
    },
  );

  test(
    'mail filters omit defaults; detail validates IDs and response shape',
    () async {
      final backend = DashboardBackend(), api = DashboardBackend().api();
      api.close();
      final client = backend.api();
      addTearDown(client.close);
      expect(await client.fetchUnreadMailCount(), 2);
      final page = await client.fetchMail();
      expect(page.items.first.isRead, false);
      expect(backend.requests.last.queryParameters, {
        'start': '0',
        'span': '30',
      });
      await client.fetchMail(
        type: 'review_notice',
        haveRead: false,
        query: ' 审核 ',
        start: 30,
      );
      expect(backend.requests.last.queryParameters, {
        'start': '30',
        'span': '30',
        'mail_type': 'review_notice',
        'have_read': 'false',
        'title': '审核',
      });
      expect(
        backend.read,
        isEmpty,
        reason: 'Listing mail must not mark it read.',
      );
      expect((await client.fetchMailDetail('mail1')).isRead, true);
      expect(await client.fetchUnreadMailCount(), 1);
      await expectLater(
        client.fetchMailDetail('../other'),
        throwsArgumentError,
      );
      final broken = McDevApi(
        cookie: '',
        category: 'pe',
        client: MockClient((_) async => fixtures.ok({'unexpected': true})),
      );
      addTearDown(broken.close);
      await expectLater(
        broken.fetchMailDetail('mail1'),
        throwsA(isA<McDevException>()),
      );
      await expectLater(
        broken.fetchUnreadMailCount(),
        throwsA(isA<McDevException>()),
      );
      await expectLater(
        broken.fetchLeaderboard(),
        throwsA(isA<McDevException>()),
      );
    },
  );

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('home shows ranks, switches categories and pages at $size', (
      tester,
    ) async {
      viewport(tester, size);
      final backend = DashboardBackend();
      await tester.pumpWidget(
        host(HomePage(apiFactory: backend.api), dark: size.width < 900),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('rank-type-pc_download')),
      );
      await tester.tap(find.byKey(const ValueKey('rank-type-pc_download')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('rank-kind-maps')));
      await tester.tap(find.byKey(const ValueKey('rank-kind-maps')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('pc_download-5-0'));
      expect(find.text('pc_download-5-0').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('下一页'));
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('pc_download-5-50'), findsOneWidget);
      expect(
        tester.getSize(find.text('51')).height,
        lessThan(50),
        reason: 'Multi-digit ranks must stay on one line.',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('home respects rank permissions and isolates overview errors', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final backend = DashboardBackend()
      ..advanced = false
      ..failOverview = true;
    await tester.pumpWidget(host(HomePage(apiFactory: backend.api)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rank-type-pe_hot')), findsNothing);
    expect(find.text('pe_download-2-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home CSV dialog applies leaderboard and kind selection', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final backend = DashboardBackend()..rankTotal = 1;
    String? savedCsv;
    await tester.pumpWidget(
      host(
        HomePage(
          apiFactory: backend.api,
          csvSaver: ({required fileName, required content}) async {
            expect(fileName, endsWith('.csv'));
            savedCsv = content;
            return '/tmp/ranks.csv';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    backend.requests.clear();

    await tester.tap(find.byKey(const ValueKey('export-rank-csv')));
    await tester.pumpAndSettle();
    expect(find.text('导出排行榜数据'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-rank-type-pe_hot')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('export-rank-kind-mods')),
    );
    await tester.tap(find.byKey(const ValueKey('export-rank-kind-mods')));
    await tester.pump();
    await tester.tap(find.text('导出CSV').last);
    await tester.pumpAndSettle();

    expect(savedCsv, isNotNull);
    expect(savedCsv, isNot(contains('手游热门飙升')));
    expect(savedCsv, isNot(contains('"模组"')));
    final rankRequests = backend.requests
        .where((uri) => uri.path.startsWith('/square/'))
        .toList();
    expect(rankRequests, hasLength(13));
    expect(
      rankRequests.any((uri) => uri.queryParameters['type'] == 'pe_hot'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest selected rank wins over a slow previous response', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final backend = DashboardBackend()..slowRank = Completer<void>();
    await tester.pumpWidget(host(HomePage(apiFactory: backend.api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rank-type-pe_sell')));
    await tester.pump();
    expect(find.byType(OreLoadingIndicator), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('rank-type-pc_like')));
    await tester.pumpAndSettle();
    backend.slowRank!.complete();
    await tester.pumpAndSettle();
    expect(find.text('pc_like-3-0'), findsOneWidget);
    expect(find.text('pe_sell-2-0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      'mail dialog reads rendered mail and refreshes count at $size',
      (tester) async {
        viewport(tester, size);
        final backend = DashboardBackend();
        await tester.pumpWidget(
          host(MailboxButton(apiFactory: backend.api), dark: size.width < 900),
        );
        await tester.pumpAndSettle();
        expect(find.text('2'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('mailbox-entry')));
        await tester.pumpAndSettle();
        expect(
          ModalRoute.of(tester.element(find.byType(MailboxPage))),
          isA<RawDialogRoute<void>>(),
        );
        expect(backend.read, isEmpty);
        await tester.tap(find.byKey(const ValueKey('mail-mail1')));
        await tester.pumpAndSettle();
        expect(find.text('mail1 正文', findRichText: true), findsOneWidget);
        expect(find.text('第二段', findRichText: true), findsOneWidget);
        expect(find.text('性能报告.pdf'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('通知 1').last).dy,
          lessThan(160),
          reason: 'Short mail content starts at the top of its pane.',
        );
        expect(find.textContaining('<p>'), findsNothing);
        expect(backend.unread, 1);
        if (size.width < 900) {
          expect(find.byKey(const ValueKey('mail-mail2')), findsNothing);
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is OreIconButton && w.tooltip == '返回邮件列表',
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('mail-mail2')), findsOneWidget);
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is OreIconButton && w.tooltip == '关闭邮件',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MailboxPage), findsNothing);
        expect(find.text('1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          const SizedBox(),
        ); // dispose periodic refresh timer
      },
    );
  }

  testWidgets(
    'mail search, unread filter and pagination keep query parameters',
    (tester) async {
      viewport(tester, const Size(1280, 900));
      final backend = DashboardBackend();
      await tester.pumpWidget(host(MailboxPage(apiFactory: backend.api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), '审核');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('只看未读'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is OreIconButton && w.tooltip == '下一页邮件',
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.requests.last.queryParameters, {
        'start': '30',
        'span': '30',
        'have_read': 'false',
        'title': '审核',
      });
      expect(find.text('通知 31'), findsOneWidget);
      expect(backend.read, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed detail keeps unread state and retry marks only that mail read',
    (tester) async {
      viewport(tester, const Size(1280, 900));
      final backend = DashboardBackend()..failDetail = true;
      var refreshes = 0;
      await tester.pumpWidget(
        host(MailboxPage(apiFactory: backend.api, onRead: () => refreshes++)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mail-mail1')));
      await tester.pumpAndSettle();
      expect(backend.unread, 2);
      expect(refreshes, 0);
      expect(find.text('重试'), findsOneWidget);
      backend.failDetail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(backend.read, {'mail1'});
      expect(refreshes, 1);
      expect(find.text('mail1 正文', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mail selection ignores late detail while keeping read state', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final backend = DashboardBackend()..slowDetail = Completer<void>();
    await tester.pumpWidget(host(MailboxPage(apiFactory: backend.api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mail-mail1')));
    await tester.pump();
    expect(find.byType(OreLoadingIndicator), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('mail-mail2')));
    await tester.pumpAndSettle();
    backend.slowDetail!.complete();
    await tester.pumpAndSettle();
    expect(find.text('mail2 正文', findRichText: true), findsOneWidget);
    expect(find.text('mail1 正文', findRichText: true), findsNothing);
    expect(backend.read, {'mail1', 'mail2'});
    expect(tester.takeException(), isNull);
  });

  test(
    'headless rank and mail commands output one JSON result and validate inputs',
    () async {
      final home = await Directory.systemTemp.createTemp('mcdev-dashboard-');
      addTearDown(() => home.delete(recursive: true));
      final backend = DashboardBackend();
      Future<({int code, Map<String, dynamic> json})> run(
        List<String> args,
      ) async {
        final output = <String>[];
        final code = await McdevCli(
          output: output.add,
          diagnostic: (_) {},
          environment: {'MCDEV_COOKIE': 'test'},
          apiFactory: backend.api,
        ).run(['--home', home.path, ...args]);
        expect(output, hasLength(1));
        return (
          code: code,
          json: jsonDecode(output.single) as Map<String, dynamic>,
        );
      }

      final rank = await run([
        'rank',
        '--type',
        'pc_like',
        '--kind',
        'maps',
        '--page',
        '2',
        '--limit',
        '50',
      ]);
      expect(rank.code, 0);
      expect(rank.json['data']['items'][0]['rank'], 51);
      expect(rank.json['data']['next_offset'], isNull);
      expect((await run(['mail', 'count'])).json['data']['unread'], 2);
      expect(
        (await run(['mail', 'list', '--unread'])).json['data']['items'],
        hasLength(2),
      );
      expect(backend.read, isEmpty);
      expect(
        (await run(['mail', 'show', 'mail1'])).json['data']['detail'],
        contains('mail1 正文'),
      );
      expect((await run(['mail', 'count'])).json['data']['unread'], 1);
      expect((await run(['rank', '--type', 'unknown'])).code, 2);
      expect((await run(['mail', 'list', '--limit', '0'])).code, 2);
      expect((await run(['mail', 'show', '../invalid'])).code, 2);
    },
  );
}
