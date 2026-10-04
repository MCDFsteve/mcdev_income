import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcdev_income/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_test.dart' show host, viewport;

class ModsResourceBackend {
  final requests = <http.Request>[];
  bool unavailable = false;

  McDevApi api(String category) => McDevApi(
    cookie: 'developer-cookie=private',
    category: category,
    client: MockClient((request) async {
      requests.add(request);
      Object response;
      if (request.url.path.startsWith('/items/categories/')) {
        response = {
          'status': 'ok',
          'data': {
            'count': 1,
            'item': [
              {
                'item_id': category == 'java'
                    ? '4635523327531425944'
                    : '4685624094850259947',
                'item_name': category == 'java' ? 'Java 组件' : 'PE 组件',
                'price': 0,
                'status': unavailable ? 'offline' : 'online',
              },
            ],
          },
        };
      } else if (request.url.path == '/data_analysis/day_detail/') {
        response = {
          'status': 'ok',
          'data': {'data': []},
        };
      } else if (request.url.path == '/h5/pe-item-detail-v2' ||
          request.url.path == '/item/query/search-by-iid') {
        final id = jsonDecode(request.body)['item_id'];
        response = {
          'code': unavailable ? 16 : 0,
          'entity': {
            'item_id': id,
            'entity_id': id,
            'res_name': 'PE 详情',
            'name': 'Java 详情',
            'developer_name': '测试开发者',
          },
        };
      } else {
        throw StateError('Unexpected request: ${request.url}');
      }
      return http.Response(
        jsonEncode(response),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final location in ['center', 'bottom']) {
      testWidgets(
        'phone Mod card opens details from $location on $platform',
        (tester) async {
          viewport(tester, const Size(360, 640));
          final backend = ModsResourceBackend();
          await tester.pumpWidget(host(ModsPage(apiFactory: backend.api)));
          await tester.pumpAndSettle();
          final tile = find.byKey(
            const ValueKey('mod-resource-pe-4685624094850259947'),
          );
          final card = find
              .ancestor(of: tile, matching: find.byType(OreCard))
              .first;
          final rect = tester.getRect(card);
          await tester.tapAt(
            location == 'center'
                ? rect.center
                : Offset(rect.center.dx, rect.bottom - 12),
          );
          await tester.pumpAndSettle();
          expect(find.byType(LeaderboardResourceDialog), findsOneWidget);
          expect(find.text('PE 详情'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  for (final java in [false, true]) {
    testWidgets(
      '${java ? 'Java' : 'PE'} Mod opens its public resource detail',
      (tester) async {
        viewport(tester, java ? const Size(1280, 900) : const Size(600, 900));
        final backend = ModsResourceBackend();
        await tester.pumpWidget(
          host(ModsPage(apiFactory: backend.api), dark: java),
        );
        await tester.pumpAndSettle();
        if (java) {
          await tester.tap(find.text('Java'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(java ? 'Java 组件' : 'PE 组件'));
        await tester.pumpAndSettle();

        final dialog = tester.widget<LeaderboardResourceDialog>(
          find.byType(LeaderboardResourceDialog),
        );
        expect(dialog.entry.isDesktop, java);
        expect(dialog.entry.rank, 0);
        expect(find.text(java ? 'Java 详情' : 'PE 详情'), findsOneWidget);
        expect(find.textContaining('#0'), findsNothing);
        final details = backend.requests.where(
          (request) => request.method == 'POST',
        );
        expect(details, hasLength(1));
        final request = details.single;
        expect(
          request.url.host,
          java
              ? 'x19mclobt.nie.netease.com'
              : 'g79apigatewayobt.nie.netease.com',
        );
        expect(
          jsonDecode(request.body)['item_id'],
          java ? '4635523327531425944' : '4685624094850259947',
        );
        expect(request.headers.keys.map((key) => key.toLowerCase()), [
          'content-type',
        ]);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(LeaderboardResourceDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('offline Mods retain their name and reuse detail retry', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final backend = ModsResourceBackend()..unavailable = true;
    await tester.pumpWidget(host(ModsPage(apiFactory: backend.api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PE 组件'));
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardResourceDialog), findsOneWidget);
    expect(find.text('暂时找不到该资源，可能已下架'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LeaderboardResourceDialog),
        matching: find.text('PE 组件'),
      ),
      findsOneWidget,
    );
    backend.unavailable = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('PE 详情'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
