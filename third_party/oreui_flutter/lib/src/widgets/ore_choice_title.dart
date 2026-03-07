import 'package:flutter/widgets.dart';

import '../theme/ore_theme.dart';
import '../theme/ore_tokens.dart';

class OreChoiceTitle extends StatelessWidget {
  const OreChoiceTitle({
    super.key,
    required this.child,
    this.style,
    this.alignment = Alignment.centerLeft,
    this.padding,
  });

  final Widget child;
  final TextStyle? style;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = OreTheme.of(context);
    final resolvedPadding = padding ??
        const EdgeInsets.only(
          left: OreTokens.gapXs,
          right: OreTokens.gapXs,
          top: 0,
          bottom: 0,
        );
    return DefaultTextStyle.merge(
      style: style ?? theme.typography.choiceTitle,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: resolvedPadding,
          child: child,
        ),
      ),
    );
  }
}
