part of mcdev_income_app;

class _FixedBarPalette {
  const _FixedBarPalette({
    required this.background,
    required this.border,
    required this.highlight,
    required this.shadow,
    required this.shadowStrong,
  });

  final Color background;
  final Color border;
  final Color highlight;
  final Color shadow;
  final Color shadowStrong;
}

_FixedBarPalette _fixedBarPalette() {
  final light = OreColors.light();
  final dark = OreColors.dark();
  return _FixedBarPalette(
    background: dark.surface,
    border: light.border,
    highlight: light.highlight,
    shadow: light.shadow,
    shadowStrong: light.shadowStrong,
  );
}

PreferredSizeWidget buildOreAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
}) {
  final ore = OreTheme.of(context);
  final colors = ore.colors;
  final palette = _fixedBarPalette();
  final textStyle =
      ore.typography.choiceTitle.copyWith(color: Colors.white);
  final borderWidth = ore.borderWidth;
  final depth = borderWidth * 2;
  final actionWidgets = actions ?? const <Widget>[];

  return PreferredSize(
    preferredSize: const Size.fromHeight(kToolbarHeight),
    child: OreSurface(
      color: palette.background,
      borderColor: palette.border,
      highlightColor: palette.highlight,
      shadowColor: palette.shadowStrong,
      borderWidth: borderWidth,
      depth: depth,
      highlightDepth: borderWidth,
      shadowDepth: depth,
      padding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: DefaultTextStyle(
                  style: textStyle,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (actionWidgets.isNotEmpty)
                IconTheme(
                  data: const IconThemeData(color: Colors.white),
                  child: DefaultTextStyle.merge(
                    style: textStyle,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final widget in actionWidgets)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: widget,
                          ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
