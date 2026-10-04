import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/main.dart';
import 'package:mcdev_income/ui/ore_material.dart' as ui;
import 'package:oreui_flutter/oreui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget incomeHost() => MaterialApp(
  theme: ThemeData(extensions: [OreThemeData.light()]),
  home: const Scaffold(body: IncomePage()),
);

Map<String, dynamic> preset({String id = 'custom'}) => {
  'id': id,
  'name': '自定义分成',
  'category': 'java',
  'scope': 'single',
  'modIds': ['123'],
  'defaultInternalRatio': 0.5,
  'defaultNeteaseRatio': 0.7,
  'taxRate': 0.1,
};

ui.TextField ratioField(WidgetTester tester, String label) => tester
    .widgetList<ui.TextField>(find.byType(ui.TextField))
    .firstWhere((field) => field.decoration?.labelText == label);

ui.DropdownButtonFormField<String> presetField(WidgetTester tester) =>
    tester.widget(find.byType(ui.DropdownButtonFormField<String>));

Future<void> reopen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(incomeHost());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('fresh income uses 0.39 while explicit preset splits survive', (
    tester,
  ) async {
    await tester.pumpWidget(incomeHost());
    await tester.pumpAndSettle();
    expect(ratioField(tester, '默认网易分成').controller!.text, '0.39');
    expect(IncomePreset.fromJson({'id': 'legacy'}).defaultNeteaseRatio, 0.39);
    expect(
      IncomePreset.fromJson({
        'id': 'explicit',
        'defaultNeteaseRatio': 1.0,
      }).defaultNeteaseRatio,
      1.0,
    );
  });

  testWidgets(
    'date picker persists the selected range across page recreation',
    (tester) async {
      await tester.pumpWidget(incomeHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择日期'));
      await tester.pumpAndSettle();
      tester
          .widget<OreCalendarDatePicker>(find.byType(OreCalendarDatePicker))
          .onDateChanged(DateTime(2026, 9, 2));
      await tester.pump();
      tester
          .widget<OreCalendarDatePicker>(find.byType(OreCalendarDatePicker))
          .onDateChanged(DateTime(2026, 9, 23));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('income_date_range_v1')!), {
        'start': '2026-09-02',
        'end': '2026-09-23',
      });
      await reopen(tester);
      expect(find.text('时间范围: 2026-09-02 ~ 2026-09-23'), findsOneWidget);
      await tester.tap(find.text('选择日期'));
      await tester.pumpAndSettle();
      final calendar = tester.widget<OreCalendarDatePicker>(
        find.byType(OreCalendarDatePicker),
      );
      expect(calendar.rangeStart, DateTime(2026, 9, 2));
      expect(calendar.rangeEnd, DateTime(2026, 9, 23));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected preset restores its parameters and Mod even offline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'income_presets_v1': jsonEncode([preset()]),
      'income_date_range_v1': jsonEncode({
        'start': '2026-09-01',
        'end': '2026-09-30',
      }),
    });
    await tester.pumpWidget(incomeHost());
    await tester.pumpAndSettle();
    presetField(tester).onChanged!('custom');
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'income_selected_preset_v1',
      ),
      'custom',
    );
    await reopen(tester);
    expect(presetField(tester).value, 'custom');
    expect(find.text('时间范围: 2026-09-01 ~ 2026-09-30'), findsOneWidget);
    expect(find.text('当前单选: 123'), findsOneWidget);
    expect(
      tester
          .widget<ui.SegmentedButton<ModCategory>>(
            find.byType(ui.SegmentedButton<ModCategory>),
          )
          .selected,
      {ModCategory.java},
    );
    expect(ratioField(tester, '默认内部分成').controller!.text, '0.5');
    expect(ratioField(tester, '默认网易分成').controller!.text, '0.7');
    expect(ratioField(tester, '税收比例').controller!.text, '0.1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing the selected preset remains cleared after reopening', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'income_presets_v1': jsonEncode([preset()]),
      'income_selected_preset_v1': 'custom',
    });
    await tester.pumpWidget(incomeHost());
    await tester.pumpAndSettle();
    presetField(tester).onChanged!('__none__');
    await tester.pumpAndSettle();
    await reopen(tester);
    expect(presetField(tester).value, '__none__');
    expect(ratioField(tester, '默认网易分成').controller!.text, '0.39');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'income_selected_preset_v1',
      ),
      isNull,
    );
  });

  testWidgets('saving a new preset also persists its active selection', (
    tester,
  ) async {
    await tester.pumpWidget(incomeHost());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is OreIconButton && widget.tooltip == '保存为新预设',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is ui.TextField && widget.decoration?.labelText == '预设名称',
        ),
        matching: find.byType(EditableText),
      ),
      '新预设',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString('income_selected_preset_v1');
    expect(selected, isNotNull);
    final saved =
        (jsonDecode(prefs.getString('income_presets_v1')!) as List).single;
    expect(saved['id'], selected);
    expect(saved['defaultNeteaseRatio'], 0.39);
    await reopen(tester);
    expect(presetField(tester).value, selected);
  });

  testWidgets('damaged presets do not prevent restoring a valid saved range', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'income_presets_v1': 'broken JSON',
      'income_selected_preset_v1': 'missing',
      'income_date_range_v1': jsonEncode({
        'start': '2026-09-01',
        'end': '2026-09-30',
      }),
    });
    await tester.pumpWidget(incomeHost());
    await tester.pumpAndSettle();
    expect(find.text('时间范围: 2026-09-01 ~ 2026-09-30'), findsOneWidget);
    expect(presetField(tester).value, '__none__');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid stored ranges fall back without breaking preset restore',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'income_presets_v1': jsonEncode([preset()]),
        'income_selected_preset_v1': 'custom',
        'income_date_range_v1': jsonEncode({
          'start': '2026-09-30',
          'end': '2026-09-01',
        }),
      });
      await tester.pumpWidget(incomeHost());
      await tester.pumpAndSettle();
      expect(find.text('时间范围: 未选择'), findsOneWidget);
      expect(presetField(tester).value, 'custom');
      expect(tester.takeException(), isNull);
    },
  );
}
