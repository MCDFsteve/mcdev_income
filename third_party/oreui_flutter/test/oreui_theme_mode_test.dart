import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oreui_flutter/oreui_flutter.dart';

class _ThemeToggleHarness extends StatelessWidget {
  const _ThemeToggleHarness({required this.controller});

  final OreThemeController controller;

  @override
  Widget build(BuildContext context) {
    return OreThemeBuilder(
      controller: controller,
      builder: (context, data, brightness) {
        return MaterialApp(
          theme: ThemeData(brightness: brightness, extensions: [data]),
          home: Column(
            children: [
              const OreThemeModeSwitch(key: Key('theme-switch')),
              OreStrip(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OreButton(
                        onPressed: () {},
                        child: const Text('Button'),
                      ),
                      const SizedBox(height: 8),
                      OreChoiceButtons(
                        items: const [
                          Text('A'),
                          Text('B'),
                        ],
                        selectedIndex: 0,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 8),
                      OreSlider(
                        value: 0.5,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 8),
                      OreSwitch(
                        value: true,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 8),
                      OreDropdownButton<String>(
                        items: const [
                          OreDropdownItem(value: 'A', child: Text('A')),
                          OreDropdownItem(value: 'B', child: Text('B')),
                        ],
                        value: 'A',
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

void main() {
  testWidgets('OreThemeModeSwitch toggles light/dark theme',
      (WidgetTester tester) async {
    final controller = OreThemeController(brightness: Brightness.dark);
    await tester.pumpWidget(_ThemeToggleHarness(controller: controller));

    final beforeContext = tester.element(find.byType(OreButton));
    final colorsBefore = OreTheme.of(beforeContext).colors;
    expect(colorsBefore.background, const Color(0xFF48494A));

    await tester.tap(find.byKey(const Key('theme-switch')));
    await tester.pumpAndSettle();

    final afterContext = tester.element(find.byType(OreButton));
    final colorsAfter = OreTheme.of(afterContext).colors;
    expect(colorsAfter.background, const Color(0xFFE7E8EA));
  });
}
