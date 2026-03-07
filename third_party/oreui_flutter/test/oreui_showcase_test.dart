import 'package:flutter_test/flutter_test.dart';

import 'package:oreui_flutter/oreui_flutter.dart';

void main() {
  testWidgets('OreShowcasePage renders without exceptions',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OreShowcaseApp());
    await tester.pumpAndSettle();

    expect(find.text('Ore UI Showcase'), findsOneWidget);
    expect(find.text('Buttons'), findsOneWidget);
    expect(find.text('Form'), findsOneWidget);
    expect(find.text('难度'), findsOneWidget);
    expect(find.text('和平'), findsOneWidget);
    expect(find.text('简单'), findsOneWidget);
    expect(find.text('一般'), findsOneWidget);
    expect(find.text('困难'), findsOneWidget);
    expect(
        find.text('没有敌对生物，只会生成一些中立生物。饥饿条不会消耗，且生命值会随时间回复。'),
        findsOneWidget);
    expect(
        find.text('会生成敌对生物，但其造成的伤害较少。饥饿条会消耗，且生命值降低至5颗心。'),
        findsNothing);
    expect(
        find.text('会生成敌对生物，造成正常伤害。饥饿条会消耗，且生命值降低至一半颗心。'),
        findsNothing);
    expect(
        find.text('会生成敌对生物，且其造成的伤害增加。饥饿条会消耗，且生命值降低为零。'),
        findsNothing);
    expect(find.text('Toggles'), findsOneWidget);
    expect(find.byType(OreDropdownButton<String>), findsOneWidget);
    expect(find.text('选项一'), findsWidgets);
  });
}
