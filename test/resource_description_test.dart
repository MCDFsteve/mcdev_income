import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_crop_test.dart' show samplePng;
import 'resource_workflow_test.dart' as fixtures;
import 'widget_test.dart' show host, fakeApi;

void main() {
  testWidgets(
    'description renders paragraphs and images by default and preserves signed HTML when edited',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1920, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = (await tester.runAsync(samplePng))!;
      final html =
          '<p>跨服背包：</p><p><br></p><p><strong>保存背包</strong></p>'
          '<p><img src="data:image/png;base64,${base64Encode(bytes)}" '
          'data-fp-body="{&quot;url&quot;:&quot;saved-image&quot;}" data-fp-sign="original-signature"></p>';
      final resource = fixtures.testResource()..['info'] = html;
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            item: ResourceItem.fromJson('pe', resource),
            apiFactory: () => fakeApi(resource: resource),
          ),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      final section = find.byKey(const ValueKey('description-info'));
      final preview = find.byKey(const ValueKey('description-preview-info'));
      expect(preview, findsOneWidget);
      expect(find.text('跨服背包：', findRichText: true), findsOneWidget);
      expect(find.text('保存背包', findRichText: true), findsOneWidget);
      expect(
        find.descendant(of: preview, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: section, matching: find.byType(EditableText)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(of: section, matching: find.text('编辑 HTML')),
      );
      await tester.pumpAndSettle();
      final editor = find.descendant(
        of: section,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editor).controller.text, html);
      final updated = html.replaceFirst('跨服背包：', '跨服背包使用方法：');
      await tester.enterText(editor, updated);
      await tester.tap(
        find.descendant(of: section, matching: find.text('排版效果')),
      );
      await tester.pumpAndSettle();
      expect(find.text('跨服背包使用方法：', findRichText: true), findsOneWidget);
      await tester.tap(find.text('保存本机草稿'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        prefs.getString('resource_draft_v1:test:pe:123')!,
      );
      expect(saved['info'], updated);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'synchronized PC description also renders independently on a narrow screen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resource = fixtures.testResource()
        ..['sync_pc_flag'] = true
        ..['sync_item_info'] = {
          'item_name': 'PC 作品',
          'info': '<p>PC 版本使用说明</p><ul><li>先保存背包</li></ul>',
        };
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            item: ResourceItem.fromJson('pe', resource),
            apiFactory: () => fakeApi(resource: resource),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final section = find.byKey(
        const ValueKey('description-sync_item_info.info'),
      );
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('editor-pane-basic')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        section,
        400,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();
      expect(find.text('PC 版本使用说明', findRichText: true), findsOneWidget);
      expect(find.text('先保存背包', findRichText: true), findsOneWidget);
      expect(
        find.descendant(of: section, matching: find.byType(EditableText)),
        findsNothing,
      );
      await tester.tap(
        find.descendant(of: section, matching: find.text('编辑 HTML')),
      );
      await tester.pumpAndSettle();
      final editor = find.descendant(
        of: section,
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(editor).controller.text,
        resource['sync_item_info']['info'],
      );
      await tester.tap(
        find.descendant(of: section, matching: find.text('排版效果')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('description-preview-sync_item_info.info')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
