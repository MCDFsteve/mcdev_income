part of mcdev_income_app;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['主页', '收益汇总', 'Mod 列表', '设置'];
  static const _navEntries = [
    (Icons.home, '主页'),
    (Icons.query_stats, '收益'),
    (Icons.view_list, 'Mod'),
    (Icons.settings, '设置'),
  ];

  final _pages = const [
    HomePage(),
    IncomePage(),
    ModsPage(),
    SettingsPage(),
  ];

  double _navLabelWidth(BuildContext context, String label) {
    final style = OreTheme.of(context).typography.label;
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  bool _canShowNavLabels(
    BuildContext context,
    double? buttonWidth,
  ) {
    if (buttonWidth == null) {
      return true;
    }
    final ore = OreTheme.of(context);
    final padding = ore.borderWidth * OreTokens.buttonPadMdHUnits;
    final iconSize = 16.0;
    final gap = OreTokens.gapXs;
    final maxLabelWidth = _navEntries
        .map((entry) => _navLabelWidth(context, entry.$2))
        .fold<double>(0, (value, element) => element > value ? element : value);
    final neededWidth = padding * 2 + iconSize + gap + maxLabelWidth;
    return buttonWidth >= neededWidth;
  }

  List<Widget> _buildNavItems(
    BuildContext context, {
    double? buttonWidth,
  }) {
    final showLabels = _canShowNavLabels(context, buttonWidth);
    return _navEntries
        .map(
          (entry) {
            final icon = OrePixelIcon(icon: entry.$1, size: 16);
            if (!showLabels) {
              return icon;
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: OreTokens.gapXs),
                Text(entry.$2),
              ],
            );
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final ore = OreTheme.of(context);
    final navCount = _navEntries.length;
    final overlap = ore.borderWidth;
    final mobileButtonWidth =
        (width + overlap * (navCount - 1)) / navCount;
    final railButtonWidth = OreTokens.controlHeightMd * 3;
    final navPalette = _fixedBarPalette();
    final navItems = _buildNavItems(
      context,
      buttonWidth: isWide ? null : mobileButtonWidth,
    );

    if (isWide) {
      return Scaffold(
        appBar: buildOreAppBar(context, title: _titles[_index]),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: double.infinity,
              child: OreSurface(
                color: navPalette.background,
                borderColor: navPalette.border,
                highlightColor: navPalette.highlight,
                shadowColor: navPalette.shadow,
                borderWidth: ore.borderWidth,
                depth: ore.borderWidth * 2,
                highlightDepth: ore.borderWidth,
                shadowDepth: ore.borderWidth * 2,
                padding: EdgeInsets.zero,
                child: OreChoiceButtons(
                  items: navItems,
                  selectedIndex: _index,
                  onChanged: (value) => setState(() => _index = value),
                  dock: OreChoiceDock.left,
                  buttonWidth: railButtonWidth,
                  fullWidth: true,
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(index: _index, children: _pages),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: buildOreAppBar(context, title: _titles[_index]),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: OreChoiceButtons(
          items: navItems,
          selectedIndex: _index,
          onChanged: (value) => setState(() => _index = value),
          dock: OreChoiceDock.bottom,
          buttonWidth: mobileButtonWidth,
        ),
      ),
    );
  }
}
