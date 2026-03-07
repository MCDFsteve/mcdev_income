import 'package:flutter/widgets.dart';

enum OreShadowSide { bottom, top, left, right }

extension OreShadowSideAxis on OreShadowSide {
  Axis get depthAxis {
    switch (this) {
      case OreShadowSide.left:
      case OreShadowSide.right:
        return Axis.horizontal;
      case OreShadowSide.top:
      case OreShadowSide.bottom:
        return Axis.vertical;
    }
  }

  bool get isHorizontal => depthAxis == Axis.horizontal;
}
