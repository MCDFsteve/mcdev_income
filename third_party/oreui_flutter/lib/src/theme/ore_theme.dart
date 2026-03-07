import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'ore_tokens.dart';

const _oreFontFamily = 'Minecraft Seven v4';
const _oreFontPackage = 'oreui_flutter';

@immutable
class OreColors {
  final Color background;
  final Color surface;
  final Color surfaceHover;
  final Color surfacePressed;
  final Color surfaceDark;
  final Color border;
  final Color borderLight;
  final Color shadow;
  final Color shadowStrong;
  final Color highlight;
  final Color highlightStrong;
  final Color textPrimary;
  final Color textInverse;
  final Color textMuted;
  final Color textDisabled;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color danger;
  final Color dangerHover;
  final Color dangerPressed;
  final Color info;
  final Color warning;
  final Color success;
  final Color selection;

  const OreColors({
    required this.background,
    required this.surface,
    required this.surfaceHover,
    required this.surfacePressed,
    required this.surfaceDark,
    required this.border,
    required this.borderLight,
    required this.shadow,
    required this.shadowStrong,
    required this.highlight,
    required this.highlightStrong,
    required this.textPrimary,
    required this.textInverse,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.danger,
    required this.dangerHover,
    required this.dangerPressed,
    required this.info,
    required this.warning,
    required this.success,
    required this.selection,
  });

  factory OreColors.ore() => OreColors.dark();

  factory OreColors.dark() {
    return const OreColors(
      background: Color(0xFF48494A),
      surface: Color(0xFF5B5D60),
      surfaceHover: Color(0xFF676A6D),
      surfacePressed: Color(0xFF535559),
      surfaceDark: Color(0xFF2E2F31),
      border: Color(0xFF141516),
      borderLight: Color(0xFF7B7D80),
      shadow: Color(0xFF1F2022),
      shadowStrong: Color(0xFF121314),
      highlight: Color(0x55FFFFFF),
      highlightStrong: Color(0x88FFFFFF),
      textPrimary: Color(0xFFF2F2F2),
      textInverse: Color(0xFFFFFFFF),
      textMuted: Color(0xFFB2B4B7),
      textDisabled: Color(0xFF6A6C70),
      accent: Color(0xFF3C8527),
      accentHover: Color(0xFF2A641C),
      accentPressed: Color(0xFF1D4D13),
      danger: Color(0xFFC33636),
      dangerHover: Color(0xFFC02D2D),
      dangerPressed: Color(0xFFAD1D1D),
      info: Color(0xFF2E6BE5),
      warning: Color(0xFFFFE866),
      success: Color(0xFF6CC349),
      selection: Color(0x806CC349),
    );
  }

  factory OreColors.light() {
    return const OreColors(
      background: Color(0xFFE6E6E6),
      surface: Color(0xFFF7F8FA),
      surfaceHover: Color(0xFFE3E6EA),
      surfacePressed: Color(0xFFD6D9DE),
      surfaceDark: Color(0xFFBFC4CB),
      border: Color(0xFF1E1F22),
      borderLight: Color(0xFF9DA0A5),
      shadow: Color(0xFF9EA1A6),
      shadowStrong: Color(0xFF6B6D70),
      highlight: Color(0x99FFFFFF),
      highlightStrong: Color(0xCCFFFFFF),
      textPrimary: Color(0xFF111111),
      textInverse: Color(0xFFFFFFFF),
      textMuted: Color(0xFF6F7175),
      textDisabled: Color(0xFFB1B2B5),
      accent: Color(0xFF3C8527),
      accentHover: Color(0xFF2A641C),
      accentPressed: Color(0xFF1D4D13),
      danger: Color(0xFFC33636),
      dangerHover: Color(0xFFC02D2D),
      dangerPressed: Color(0xFFAD1D1D),
      info: Color(0xFF2E6BE5),
      warning: Color(0xFFFFE866),
      success: Color(0xFF6CC349),
      selection: Color(0x806CC349),
    );
  }

  OreColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHover,
    Color? surfacePressed,
    Color? surfaceDark,
    Color? border,
    Color? borderLight,
    Color? shadow,
    Color? shadowStrong,
    Color? highlight,
    Color? highlightStrong,
    Color? textPrimary,
    Color? textInverse,
    Color? textMuted,
    Color? textDisabled,
    Color? accent,
    Color? accentHover,
    Color? accentPressed,
    Color? danger,
    Color? dangerHover,
    Color? dangerPressed,
    Color? info,
    Color? warning,
    Color? success,
    Color? selection,
  }) {
    return OreColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      border: border ?? this.border,
      borderLight: borderLight ?? this.borderLight,
      shadow: shadow ?? this.shadow,
      shadowStrong: shadowStrong ?? this.shadowStrong,
      highlight: highlight ?? this.highlight,
      highlightStrong: highlightStrong ?? this.highlightStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textInverse: textInverse ?? this.textInverse,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentPressed: accentPressed ?? this.accentPressed,
      danger: danger ?? this.danger,
      dangerHover: dangerHover ?? this.dangerHover,
      dangerPressed: dangerPressed ?? this.dangerPressed,
      info: info ?? this.info,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      selection: selection ?? this.selection,
    );
  }

  static OreColors lerp(OreColors a, OreColors b, double t) {
    return OreColors(
      background: Color.lerp(a.background, b.background, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      surfaceHover: Color.lerp(a.surfaceHover, b.surfaceHover, t)!,
      surfacePressed: Color.lerp(a.surfacePressed, b.surfacePressed, t)!,
      surfaceDark: Color.lerp(a.surfaceDark, b.surfaceDark, t)!,
      border: Color.lerp(a.border, b.border, t)!,
      borderLight: Color.lerp(a.borderLight, b.borderLight, t)!,
      shadow: Color.lerp(a.shadow, b.shadow, t)!,
      shadowStrong: Color.lerp(a.shadowStrong, b.shadowStrong, t)!,
      highlight: Color.lerp(a.highlight, b.highlight, t)!,
      highlightStrong: Color.lerp(a.highlightStrong, b.highlightStrong, t)!,
      textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
      textInverse: Color.lerp(a.textInverse, b.textInverse, t)!,
      textMuted: Color.lerp(a.textMuted, b.textMuted, t)!,
      textDisabled: Color.lerp(a.textDisabled, b.textDisabled, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      accentHover: Color.lerp(a.accentHover, b.accentHover, t)!,
      accentPressed: Color.lerp(a.accentPressed, b.accentPressed, t)!,
      danger: Color.lerp(a.danger, b.danger, t)!,
      dangerHover: Color.lerp(a.dangerHover, b.dangerHover, t)!,
      dangerPressed: Color.lerp(a.dangerPressed, b.dangerPressed, t)!,
      info: Color.lerp(a.info, b.info, t)!,
      warning: Color.lerp(a.warning, b.warning, t)!,
      success: Color.lerp(a.success, b.success, t)!,
      selection: Color.lerp(a.selection, b.selection, t)!,
    );
  }
}

@immutable
class OreTypography {
  final TextStyle title;
  final TextStyle body;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle choiceTitle;

  const OreTypography({
    required this.title,
    required this.body,
    required this.label,
    required this.caption,
    required this.choiceTitle,
  });

  factory OreTypography.ore(OreColors colors) {
    return OreTypography(
      title: TextStyle(
        fontFamily: _oreFontFamily,
        package: _oreFontPackage,
        fontSize: 30,
        height: 1.1,
        color: colors.textPrimary,
      ),
      body: TextStyle(
        fontFamily: _oreFontFamily,
        package: _oreFontPackage,
        fontSize: 14,
        height: 1.4,
        color: colors.textPrimary,
      ),
      label: TextStyle(
        fontFamily: _oreFontFamily,
        package: _oreFontPackage,
        fontSize: 14,
        height: 1.2,
        color: colors.textPrimary,
      ),
      caption: TextStyle(
        fontFamily: _oreFontFamily,
        package: _oreFontPackage,
        fontSize: 12,
        height: 1.2,
        color: colors.textMuted,
      ),
      choiceTitle: TextStyle(
        fontFamily: _oreFontFamily,
        package: _oreFontPackage,
        fontSize: 18,
        height: 1.2,
        color: colors.textPrimary,
      ),
    );
  }

  OreTypography copyWith({
    TextStyle? title,
    TextStyle? body,
    TextStyle? label,
    TextStyle? caption,
    TextStyle? choiceTitle,
  }) {
    return OreTypography(
      title: title ?? this.title,
      body: body ?? this.body,
      label: label ?? this.label,
      caption: caption ?? this.caption,
      choiceTitle: choiceTitle ?? this.choiceTitle,
    );
  }

  static OreTypography lerp(OreTypography a, OreTypography b, double t) {
    return OreTypography(
      title: TextStyle.lerp(a.title, b.title, t)!,
      body: TextStyle.lerp(a.body, b.body, t)!,
      label: TextStyle.lerp(a.label, b.label, t)!,
      caption: TextStyle.lerp(a.caption, b.caption, t)!,
      choiceTitle: TextStyle.lerp(a.choiceTitle, b.choiceTitle, t)!,
    );
  }
}

@immutable
class OreThemeData extends ThemeExtension<OreThemeData> {
  final OreColors colors;
  final OreTypography typography;
  final double radius;
  final double borderWidth;
  final double focusWidth;
  final double gap;
  final double bevelDepth;

  const OreThemeData({
    required this.colors,
    required this.typography,
    required this.radius,
    required this.borderWidth,
    required this.focusWidth,
    required this.gap,
    required this.bevelDepth,
  });

  factory OreThemeData.ore() {
    return OreThemeData._fromColors(OreColors.dark());
  }

  factory OreThemeData.dark() => OreThemeData._fromColors(OreColors.dark());

  factory OreThemeData.light() => OreThemeData._fromColors(OreColors.light());

  factory OreThemeData.fromBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? OreThemeData.dark()
        : OreThemeData.light();
  }

  static OreThemeData fallback() => OreThemeData.ore();

  factory OreThemeData._fromColors(OreColors colors) {
    return OreThemeData(
      colors: colors,
      typography: OreTypography.ore(colors),
      radius: OreTokens.radius,
      borderWidth: OreTokens.borderWidth,
      focusWidth: OreTokens.focusWidth,
      gap: OreTokens.gapSm,
      bevelDepth: OreTokens.borderWidth * 2,
    );
  }

  @override
  OreThemeData copyWith({
    OreColors? colors,
    OreTypography? typography,
    double? radius,
    double? borderWidth,
    double? focusWidth,
    double? gap,
    double? bevelDepth,
  }) {
    return OreThemeData(
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      radius: radius ?? this.radius,
      borderWidth: borderWidth ?? this.borderWidth,
      focusWidth: focusWidth ?? this.focusWidth,
      gap: gap ?? this.gap,
      bevelDepth: bevelDepth ?? this.bevelDepth,
    );
  }

  @override
  OreThemeData lerp(ThemeExtension<OreThemeData>? other, double t) {
    if (other is! OreThemeData) {
      return this;
    }
    return OreThemeData(
      colors: OreColors.lerp(colors, other.colors, t),
      typography: OreTypography.lerp(typography, other.typography, t),
      radius: lerpDouble(radius, other.radius, t)!,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t)!,
      focusWidth: lerpDouble(focusWidth, other.focusWidth, t)!,
      gap: lerpDouble(gap, other.gap, t)!,
      bevelDepth: lerpDouble(bevelDepth, other.bevelDepth, t)!,
    );
  }
}

class OreTheme extends InheritedTheme {
  const OreTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final OreThemeData data;

  static OreThemeData of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<OreTheme>();
    final extension = Theme.of(context).extension<OreThemeData>();
    return inherited?.data ?? extension ?? OreThemeData.fallback();
  }

  @override
  bool updateShouldNotify(OreTheme oldWidget) => data != oldWidget.data;

  @override
  Widget wrap(BuildContext context, Widget child) {
    return OreTheme(data: data, child: child);
  }
}

class OreThemeController extends ChangeNotifier {
  OreThemeController({Brightness brightness = Brightness.dark})
      : _brightness = brightness;

  Brightness _brightness;

  Brightness get brightness => _brightness;

  bool get isDark => _brightness == Brightness.dark;

  set brightness(Brightness value) {
    if (value == _brightness) return;
    _brightness = value;
    notifyListeners();
  }

  void toggle() {
    brightness = isDark ? Brightness.light : Brightness.dark;
  }
}

class OreThemeProvider extends InheritedNotifier<OreThemeController> {
  const OreThemeProvider({
    super.key,
    required OreThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static OreThemeController of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<OreThemeProvider>();
    assert(provider != null, 'OreThemeProvider not found in context.');
    return provider!.notifier!;
  }
}

typedef OreThemeWidgetBuilder = Widget Function(
  BuildContext context,
  OreThemeData data,
  Brightness brightness,
);

class OreThemeBuilder extends StatelessWidget {
  const OreThemeBuilder({
    super.key,
    required this.controller,
    required this.builder,
  });

  final OreThemeController controller;
  final OreThemeWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final data = OreThemeData.fromBrightness(controller.brightness);
        return OreThemeProvider(
          controller: controller,
          child: OreTheme(
            data: data,
            child: builder(context, data, controller.brightness),
          ),
        );
      },
    );
  }
}
