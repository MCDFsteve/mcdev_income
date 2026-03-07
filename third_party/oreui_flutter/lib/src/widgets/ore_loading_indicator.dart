import 'package:flutter/material.dart';

import '../theme/ore_tokens.dart';

enum OreLoadingTone { auto, light, dark }

class OreLoadingIndicator extends StatelessWidget {
  const OreLoadingIndicator({
    super.key,
    this.size = OreTokens.controlHeightSm,
    this.tone = OreLoadingTone.auto,
    this.semanticLabel,
  });

  final double size;
  final OreLoadingTone tone;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedTone = tone == OreLoadingTone.auto
        ? (Theme.of(context).brightness == Brightness.dark
            ? OreLoadingTone.light
            : OreLoadingTone.dark)
        : tone;
    final assetName = resolvedTone == OreLoadingTone.light
        ? 'assets/loading/Loading_white.gif'
        : 'assets/loading/Loading.gif';

    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          assetName,
          package: 'oreui_flutter',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
