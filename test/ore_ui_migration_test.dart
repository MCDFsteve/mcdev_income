import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mcdev_income/main.dart';
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'resource_workflow_test.dart' as fixtures;

Widget host(Widget child) => MaterialApp(
  theme: oreAppTheme(),
  scrollBehavior: const OreScrollBehavior(),
  home: Scaffold(body: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('new resource waits with Ore animation then opens the editor', (
    tester,
  ) async {
    final ready = Completer<void>();
    final api = McDevApi(
      cookie: '',
      category: 'pe',
      client: MockClient((r) async {
        if (r.url.path == '/items/mc_consts/') {
          await ready.future;
          return fixtures.ok(fixtures.testOptions);
        }
        return fixtures.ok(<String, dynamic>{});
      }),
    );
    await tester.pumpWidget(
      host(
        ResourceEditorPage(
          category: const ResourceCategory(
            value: 'pe',
            label: 'PE 资源',
            uploadLabel: '新建作品',
          ),
          apiFactory: () => api,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OreLoadingIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byType(OreLoadingIndicator), findsNothing);
    expect(find.text('保存到平台'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login checkbox and input controls are Ore on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(const LoginPage()));
    await tester.pumpAndSettle();
    expect(find.byType(OreCheckboxListTile), findsNWidgets(2));
    expect(find.byType(OreTextField), findsNWidgets(2));
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('保存密码用于自动刷新凭证'));
    await tester.pump();
    expect(
      tester
          .widget<OreCheckboxListTile>(find.byType(OreCheckboxListTile).last)
          .value,
      false,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(1100, 800),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('income date range still selects two dates at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(const IncomePage()));
      await tester.pumpAndSettle();
      final pickerButton = find.widgetWithText(OreButton, '选择日期');
      await tester.ensureVisible(pickerButton);
      await tester.tap(pickerButton);
      await tester.pumpAndSettle();
      expect(find.byType(OreCalendarDatePicker), findsOneWidget);
      expect(find.byType(CalendarDatePicker), findsNothing);
      final now = DateTime.now();
      final start = find.byKey(ValueKey('ore-date-${now.year}-${now.month}-5'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      final end = find.byKey(ValueKey('ore-date-${now.year}-${now.month}-12'));
      await tester.ensureVisible(end);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(find.byType(OreCalendarDatePicker), findsNothing);
      expect(find.textContaining('-05 ~'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'application pages cannot reintroduce default Material visual controls',
    () {
      final stock = RegExp(
        r'\b(CircularProgressIndicator|LinearProgressIndicator|IconButton|CheckboxListTile|RadioListTile|ListTile|Divider|Dialog|AlertDialog|showDialog|showModalBottomSheet|SnackBar|SelectionArea|SelectableText|CalendarDatePicker|Tooltip)\s*(?:<[^>]+>)?\(',
      );
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            file.path.endsWith('ore_material.dart'))
          continue;
        expect(
          stock.hasMatch(file.readAsStringSync()),
          false,
          reason: file.path,
        );
      }
    },
  );
}
