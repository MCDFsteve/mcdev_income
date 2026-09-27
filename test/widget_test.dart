import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:mcdev_income/main.dart';
import 'resource_workflow_test.dart' as fixtures;

Widget host(Widget page, {bool dark = false}) => MaterialApp(
  theme: ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    extensions: [dark ? OreThemeData.dark() : OreThemeData.light()],
  ),
  home: Scaffold(body: page),
);

McDevApi fakeApi({
  void Function(String, Map<String, String>)? onList,
  List<Map<String, dynamic>>? listResources,
  List<Map<String, dynamic>>? reviews,
  Map<String, dynamic>? resource,
}) => McDevApi(
  cookie: '',
  category: 'pe',
  client: MockClient((r) async {
    if (r.url.path == '/items/mc_consts/') {
      return fixtures.ok(fixtures.testOptions);
    }
    if (r.url.path == '/users/me' || r.url.path == '/users/author_info') {
      return fixtures.ok({'can_set_conflict_notify': true});
    }
    if (r.url.path == '/items/categories/pe/') {
      onList?.call(r.url.path, r.url.queryParameters);
      return fixtures.ok({
        'count': 31,
        'item':
            listResources ??
            [
              fixtures.testResource(
                id: r.url.queryParameters['start'] == '30' ? '456' : '123',
              ),
            ],
      });
    }
    if (r.url.path.endsWith('/feedback')) {
      return fixtures.ok({'feedback': '<p>请补充玩法说明</p>'});
    }
    if (r.url.path.endsWith('/apply_review')) {
      reviews?.add(Map<String, dynamic>.from(jsonDecode(r.body)));
      return fixtures.ok({
        'need_check_apply': reviews?.length == 1,
        'queue_length': 42,
      });
    }
    if (r.url.path == '/setting/common/') {
      return fixtures.ok({
        'setting': {'queue_too_long_notify': '队列中有 {{queue_length}} 个作品'},
      });
    }
    return fixtures.ok(resource ?? fixtures.testResource());
  }),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('application opens without a session', (tester) async {
    await tester.pumpWidget(const McDevIncomeApp());
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is MaterialApp && widget.title == '我的世界开发者管理',
      ),
      findsOneWidget,
    );
    expect(find.text('主页'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource list can reach later pages on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final offsets = <String>[];
    await tester.pumpWidget(
      host(
        ResourceManagementPage(
          apiFactory: () => fakeApi(onList: (_, q) => offsets.add(q['start']!)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ID：123'), findsOneWidget);
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('ID：456'), findsOneWidget);
    expect(offsets, ['0', '30']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource cards use desktop columns and search controls align', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        ResourceManagementPage(
          apiFactory: () => fakeApi(
            listResources: [
              for (final id in ['101', '102', '103'])
                fixtures.testResource(id: id),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cards = find.byType(OreCard);
    expect(cards, findsNWidgets(3));
    final first = tester.getTopLeft(cards.at(0));
    final second = tester.getTopLeft(cards.at(1));
    final third = tester.getTopLeft(cards.at(2));
    expect(first.dx, lessThan(second.dx));
    expect(second.dx, lessThan(third.dx));
    expect(first.dy, second.dy);
    expect(second.dy, third.dy);

    final field = tester.getRect(find.byType(OreTextField));
    final button = tester.getRect(
      find.ancestor(of: find.text('搜索'), matching: find.byType(OreButton)),
    );
    expect((field.center.dy - button.center.dy).abs(), lessThan(1));
    expect(tester.getTopLeft(find.text('PE 资源')).dx, lessThan(40));

    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(cards.at(0)).dx,
      tester.getTopLeft(cards.at(1)).dx,
    );
    expect(
      tester.getTopLeft(cards.at(0)).dy,
      lessThan(tester.getTopLeft(cards.at(1)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('review queue requires an explicit second confirmation', (
    tester,
  ) async {
    final reviews = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      host(
        ResourceReviewPage(
          item: ResourceItem.fromJson('pe', fixtures.testResource()),
          apiFactory: () => fakeApi(reviews: reviews),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('请补充玩法说明', findRichText: true), findsOneWidget);
    final submit = find.widgetWithText(OreButton, '提交审核').last;
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(reviews.length, 1);
    expect(reviews.first['is_check_apply'], false);
    expect(find.text('队列中有 42 个作品'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(reviews.length, 1);
    expect(find.text('状态：待提交审核'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor restores a draft and validates without sending a save', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'resource_draft_v1:test:pe:new': jsonEncode(fixtures.testResource()),
    });
    await tester.pumpWidget(
      host(
        ResourceEditorPage(
          category: const ResourceCategory(
            value: 'pe',
            label: 'PE 资源',
            uploadLabel: '上传 PE 资源',
          ),
          apiFactory: fakeApi,
        ),
        dark: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复草稿'));
    await tester.pumpAndSettle();
    expect(find.text('测试模组'), findsOneWidget);
    expect(find.text('已恢复本机草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saved resource survives review failure without duplicate creation',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'resource_draft_v1:test:pe:new': jsonEncode(fixtures.testResource()),
      });
      final writes = <String>[];
      McDevApi api() => McDevApi(
        cookie: '',
        category: 'pe',
        client: MockClient((r) async {
          if (r.method != 'GET') writes.add(r.url.path);
          if (r.url.path == '/items/mc_consts/') {
            return fixtures.ok(fixtures.testOptions);
          }
          if (r.url.path.startsWith('/users/')) return fixtures.ok({});
          if (r.url.path == '/setting/common/') {
            return fixtures.ok({'setting': {}});
          }
          if (r.url.path.endsWith('/upload')) {
            return fixtures.ok({'item_id': '789'});
          }
          if (r.url.path.endsWith('/feedback')) {
            return fixtures.ok({'feedback': ''});
          }
          if (r.url.path.endsWith('/apply_review')) {
            return http.Response(
              jsonEncode({'status': 'invalid', 'msg': '需要补充说明'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return fixtures.ok(fixtures.testResource(id: '789'));
        }),
      );
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            apiFactory: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并提交审核'));
      await tester.pumpAndSettle();
      expect(find.text('资源编号：789'), findsOneWidget);
      final submit = find.widgetWithText(OreButton, '提交审核').last;
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已保存的资源仍然保留'), findsOneWidget);
      Navigator.of(tester.element(find.byType(ResourceReviewPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并提交审核'));
      await tester.pumpAndSettle();
      expect(find.text('资源编号：789'), findsOneWidget);
      expect(writes, [
        '/items/categories/pe/upload',
        '/items/categories/pe/789/apply_review',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ambiguous new save blocks duplicate upload and keeps draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'resource_draft_v1:test:pe:new': jsonEncode(fixtures.testResource()),
    });
    var writes = 0;
    McDevApi api() => McDevApi(
      cookie: '',
      category: 'pe',
      client: MockClient((r) async {
        if (r.url.path == '/items/mc_consts/') {
          return fixtures.ok(fixtures.testOptions);
        }
        if (r.url.path.endsWith('/upload')) {
          writes++;
          return fixtures.ok({});
        }
        return fixtures.ok({});
      }),
    );
    await tester.pumpWidget(
      host(
        ResourceEditorPage(
          category: const ResourceCategory(
            value: 'pe',
            label: 'PE',
            uploadLabel: '新建',
          ),
          apiFactory: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存到平台'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.textContaining('保存结果尚未确认'), findsOneWidget);
    expect(
      tester
          .widget<OreButton>(find.widgetWithText(OreButton, '保存到平台'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OreButton>(find.widgetWithText(OreButton, '保存并提交审核'))
          .onPressed,
      isNull,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('resource_draft_v1:test:pe:new'), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synchronized PC resource cannot submit independently', (
    tester,
  ) async {
    final resource = fixtures.testResource()..['sync_pc_flag'] = true;
    await tester.pumpWidget(
      host(
        ResourceReviewPage(
          item: ResourceItem.fromJson('comp', resource),
          apiFactory: () => McDevApi(
            cookie: '',
            category: 'comp',
            client: MockClient((r) async {
              if (r.url.path.endsWith('/feedback')) {
                return fixtures.ok({'feedback': ''});
              }
              if (r.url.path.startsWith('/users/')) return fixtures.ok({});
              return fixtures.ok(resource);
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OreButton, '提交审核'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editor keeps OreUI save actions visible on a narrow dark screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            item: ResourceItem.fromJson('pe', fixtures.testResource()),
            apiFactory: fakeApi,
          ),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('保存并提交审核').hitTestable(), findsOneWidget);
      expect(find.text('保存本机草稿').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor reflows into desktop columns without losing edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        ResourceEditorPage(
          category: const ResourceCategory(
            value: 'pe',
            label: 'PE',
            uploadLabel: '新建',
          ),
          item: ResourceItem.fromJson('pe', fixtures.testResource()),
          apiFactory: fakeApi,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '宽屏编辑中的作品');
    await tester.pumpAndSettle();
    for (final width in [1280.0, 1920.0, 390.0, 1600.0, 1000.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.text('宽屏编辑中的作品'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-pane-media')),
        width >= 1000 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('editor-pane-details')),
        width >= 1600 ? findsOneWidget : findsNothing,
      );
      if (width >= 1000) {
        expect(
          tester.getTopLeft(find.text('资源文件')).dx,
          greaterThan(tester.getTopLeft(find.text('基本信息')).dx),
        );
        expect(find.text('资源文件').hitTestable(), findsOneWidget);
        expect(find.text('展示图片').hitTestable(), findsOneWidget);
      }
      if (width >= 1600) {
        expect(
          tester.getTopLeft(find.text('资源介绍')).dx,
          greaterThan(tester.getTopLeft(find.text('资源文件')).dx),
        );
        expect(find.text('资源介绍').hitTestable(), findsOneWidget);
      }
      expect(find.text('保存并提交审核').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('保存本机草稿'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('resource_draft_v1:test:pe:123')!);
    expect(saved['item_name'], '宽屏编辑中的作品');
  });

  testWidgets('display images share a row and removal preserves other images', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        ResourceEditorPage(
          category: const ResourceCategory(
            value: 'pe',
            label: 'PE',
            uploadLabel: '新建',
          ),
          item: ResourceItem.fromJson('pe', fixtures.testResource()),
          apiFactory: fakeApi,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cover = find.byKey(const ValueKey('channel-tile-channel-3'));
    final skin = find.byKey(const ValueKey('channel-tile-channel-5'));
    final coverRect = tester.getRect(cover);
    final skinRect = tester.getRect(skin);
    expect(coverRect.top, skinRect.top);
    expect(skinRect.left, greaterThan(coverRect.right));
    expect(
      coverRect.height,
      lessThan(120),
      reason: 'Empty previews reserve no image height.',
    );
    await tester.tap(find.descendant(of: cover, matching: find.text('移除')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: cover, matching: find.text('上传图片')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: skin, matching: find.text('替换图片')),
      findsOneWidget,
    );
    await tester.tap(find.text('保存本机草稿'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('resource_draft_v1:test:pe:123')!);
    expect((saved['channel'] as List).map((e) => e['channel_id']), [5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop panes scroll independently and reveal validation errors',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            apiFactory: fakeApi,
          ),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      Finder pane(String name) => find.byKey(ValueKey('editor-pane-$name'));
      ScrollController controller(String name) => tester
          .widget<ListView>(
            find.descendant(of: pane(name), matching: find.byType(ListView)),
          )
          .controller!;
      // The desktop scrollbar must work immediately, before wheel scrolling.
      final rail = tester.getTopRight(pane('media')) + const Offset(-11, 80);
      await tester.dragFrom(rail, const Offset(0, 200));
      await tester.pumpAndSettle();
      final mediaOffset = controller('media').offset;
      expect(mediaOffset, greaterThan(0));
      expect(controller('basic').offset, 0);
      expect(controller('details').offset, 0);
      await tester.drag(pane('basic'), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(controller('basic').offset, greaterThan(0));
      await tester.tap(find.text('保存到平台'));
      await tester.pumpAndSettle();
      expect(find.text('需要处理').hitTestable(), findsOneWidget);
      expect(controller('basic').offset, 0);
      expect(controller('media').offset, mediaOffset);
      expect(find.text('保存并提交审核').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated queue confirmation is not reported as a successful save',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'resource_draft_v1:test:pe:new': jsonEncode(fixtures.testResource()),
      });
      final confirmations = <bool>[];
      McDevApi api() => McDevApi(
        cookie: '',
        category: 'pe',
        client: MockClient((r) async {
          if (r.url.path == '/items/mc_consts/') {
            return fixtures.ok(fixtures.testOptions);
          }
          if (r.url.path.endsWith('/upload')) {
            confirmations.add(jsonDecode(r.body)['is_check_apply'] == true);
            return fixtures.ok({'need_check_apply': true, 'queue_length': 42});
          }
          return fixtures.ok({});
        }),
      );
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            apiFactory: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到平台'));
      await tester.pumpAndSettle();
      expect(confirmations, [false]);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(confirmations, [false, true]);
      expect(find.textContaining('平台仍要求确认排队'), findsOneWidget);
      expect(find.text('资源已保存，尚未提交审核'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
