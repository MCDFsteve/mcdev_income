import 'package:flutter_test/flutter_test.dart';

import 'package:oreui_flutter/oreui_flutter.dart';

void main() {
  test('OreThemeData copyWith overrides fields', () {
    final theme = OreThemeData.dark();
    final updated = theme.copyWith(radius: 10);
    expect(updated.radius, 10);
    expect(updated.colors, theme.colors);
  });

  test('OreColors lerp returns blended colors', () {
    final light = OreColors.light();
    final dark = OreColors.dark();
    final blended = OreColors.lerp(light, dark, 0.5);
    expect(blended.background, isNotNull);
    expect(blended.accent, isNotNull);
  });
}
