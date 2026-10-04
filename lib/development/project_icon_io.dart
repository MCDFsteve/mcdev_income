import 'dart:io';

import 'package:flutter/widgets.dart';

Widget buildProjectIcon({
  required List<String> paths,
  required double size,
  required int cacheWidth,
  required Widget fallback,
}) {
  Widget candidate(int index) {
    if (index >= paths.length) return fallback;
    return Image.file(
      File(paths[index]),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.low,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) => candidate(index + 1),
    );
  }

  return candidate(0);
}
