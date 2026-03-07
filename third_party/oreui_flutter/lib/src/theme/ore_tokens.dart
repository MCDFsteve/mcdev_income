import 'package:flutter/widgets.dart';

@immutable
class OreTokens {
  const OreTokens._();

  static const double radius = 0;
  static const double borderWidth = 2;
  static const double focusWidth = borderWidth;

  static const double _unit = borderWidth;

  static const double controlHeightSm = _unit * 16;
  static const double controlHeightMd = _unit * 20;
  static const double controlHeightLg = _unit * 24;

  static const double gapXs = _unit * 2;
  static const double gapSm = _unit * 3;
  static const double gapMd = _unit * 5;
  static const double gapLg = _unit * 7;
  static const double gapXl = _unit * 10;

  static const EdgeInsets paddingSm =
      EdgeInsets.symmetric(horizontal: _unit * 5);
  static const EdgeInsets paddingMd =
      EdgeInsets.symmetric(horizontal: _unit * 7);
  static const EdgeInsets paddingLg =
      EdgeInsets.symmetric(horizontal: _unit * 9);

  static const double switchAspect = 11 / 5;
  static const double switchTrackUnits = 14;
  static const double switchThumbUnits = 16;
  static const double switchIconUnits = 6;
  static const double sliderTrackUnits = 4;
  static const double sliderThumbUnits = 14;
  static const double scrollbarWidthUnits = 11;
  static const double scrollbarTrackWidthUnits = 3;
  static const double scrollbarThumbWidthUnits = 6;
  static const double scrollbarThumbMinLengthUnits = 18;
  static const double scrollbarTrackInsetUnits = 4;
  static const double checkboxSizeUnits = 14;
  static const double checkboxMarkUnits = checkboxSizeUnits * 4 / 5;
  static const double checkboxMixedWidthUnits = checkboxSizeUnits / 2;
  static const double checkboxMixedHeightUnits = checkboxSizeUnits / 10;
  static const double buttonPadSmHUnits = 10;
  static const double buttonPadSmVUnits = 5;
  static const double buttonPadMdHUnits = 12;
  static const double buttonPadMdVUnits = 6;
  static const double buttonPadLgHUnits = 14;
  static const double buttonPadLgVUnits = 7;
  static const double inputHintOffsetUnits = 1;
  static const double choiceIndicatorWidthFactor = 2 / 7;
  static const double choiceIndicatorHeightUnits = 1;

  static const Color coloredHighlight = Color(0x33FFFFFF);
  static const Color coloredHighlightStrong = Color(0x66FFFFFF);

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 240);
}
