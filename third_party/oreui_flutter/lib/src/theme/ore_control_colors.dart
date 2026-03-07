import 'package:flutter/material.dart';

import 'ore_theme.dart';

OreColors resolveControlColors(BuildContext context, OreColors baseColors) {
  final brightness = Theme.of(context).brightness;
  final inverted = brightness == Brightness.dark
      ? OreColors.light()
      : OreColors.dark();
  final adjusted = brightness == Brightness.dark
      ? inverted.copyWith(
          surface: const Color(0xFFD0D1D4),
          surfaceHover: const Color(0xFFB1B2B5),
          surfacePressed: const Color(0xFFB1B2B5),
        )
      : inverted;
  return adjusted.copyWith(
    accent: baseColors.accent,
    accentHover: baseColors.accentHover,
    accentPressed: baseColors.accentPressed,
    danger: baseColors.danger,
    dangerHover: baseColors.dangerHover,
    dangerPressed: baseColors.dangerPressed,
    info: baseColors.info,
    warning: baseColors.warning,
    success: baseColors.success,
    selection: baseColors.selection,
    textInverse: baseColors.textInverse,
  );
}
