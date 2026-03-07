import 'package:flutter/widgets.dart';

import 'ore_theme.dart';
import 'ore_tokens.dart';

class OreHighlight {
  const OreHighlight._();

  static Color resolve({
    required OreColors colors,
    required bool colored,
    required bool hovered,
  }) {
    if (colored) {
      return hovered
          ? OreTokens.coloredHighlightStrong
          : OreTokens.coloredHighlight;
    }
    return hovered ? colors.highlightStrong : colors.highlight;
  }

  static Color muted({
    required OreColors colors,
    double factor = 0.4,
  }) {
    final base = colors.highlight;
    if (base.a == 0) return base;
    final nextOpacity = (base.a * factor).clamp(0.0, 1.0);
    return base.withValues(alpha: nextOpacity);
  }

  static Color mutedColored({double factor = 0.4}) {
    final base = OreTokens.coloredHighlight;
    if (base.a == 0) return base;
    final nextOpacity = (base.a * factor).clamp(0.0, 1.0);
    return base.withValues(alpha: nextOpacity);
  }
}
