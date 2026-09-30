part of mcdev_income_app;

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.developmentSupported,
    this.developmentPageBuilder,
    this.developmentSupportProbe,
  });

  final bool? developmentSupported;
  final WidgetBuilder? developmentPageBuilder;
  final Future<bool> Function()? developmentSupportProbe;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _developmentSupported = false;
  bool _developmentVisited = false;

  @override
  void initState() {
    super.initState();
    _developmentSupported = widget.developmentSupported ?? false;
    if (widget.developmentSupported == null) _detectDevelopment();
  }

  Future<void> _detectDevelopment() async {
    final supported =
        await (widget.developmentSupportProbe ?? supportsDevelopment)();
    if (!mounted || !supported) return;
    setState(() {
      if (_index == 4) _index = 5;
      _developmentSupported = true;
    });
  }

  void _select(int value) => setState(() {
    _index = value;
    if (_developmentSupported && value == 4) _developmentVisited = true;
  });

  List<String> get _titles => [
    '主页',
    '收益汇总',
    'Mod 列表',
    '资源管理',
    if (_developmentSupported) '开发',
    '设置',
  ];
  List<(IconData, String)> get _navEntries => [
    (Icons.home, '主页'),
    (Icons.query_stats, '收益'),
    (Icons.view_list, 'Mod'),
    (Icons.inventory_2, '资源'),
    if (_developmentSupported) (Icons.code, '开发'),
    (Icons.settings, '设置'),
  ];

  List<Widget> get _pages => [
    const HomePage(),
    const IncomePage(),
    const ModsPage(),
    const ResourceManagementPage(),
    if (_developmentSupported)
      _developmentVisited
          ? KeyedSubtree(
              key: const ValueKey('shell-development'),
              child:
                  widget.developmentPageBuilder?.call(context) ??
                  const DevelopmentPage(),
            )
          : const SizedBox.shrink(key: ValueKey('shell-development')),
    const SettingsPage(key: ValueKey('shell-settings')),
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

  bool _canShowNavLabels(BuildContext context, double? buttonWidth) {
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

  List<Widget> _buildNavItems(BuildContext context, {double? buttonWidth}) {
    final showLabels = _canShowNavLabels(context, buttonWidth);
    return _navEntries.map((entry) {
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
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final ore = OreTheme.of(context);
    final navCount = _navEntries.length;
    final overlap = ore.borderWidth;
    final mobileButtonWidth = (width + overlap * (navCount - 1)) / navCount;
    final railButtonWidth = OreTokens.controlHeightMd * 3;
    final navPalette = _fixedBarPalette();
    final navItems = _buildNavItems(
      context,
      buttonWidth: isWide ? null : mobileButtonWidth,
    );

    if (isWide) {
      return Scaffold(
        appBar: buildOreAppBar(
          context,
          title: _titles[_index],
          actions: [MailboxButton(refreshToken: _index)],
        ),
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
                  onChanged: _select,
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
      appBar: buildOreAppBar(
        context,
        title: _titles[_index],
        actions: [MailboxButton(refreshToken: _index)],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: !_canShowNavLabels(context, mobileButtonWidth)
            ? ColoredBox(
                color: navPalette.background,
                child: Row(
                  children: [
                    for (var i = 0; i < _navEntries.length; i++)
                      Expanded(
                        child: OreIconButton(
                          icon: OrePixelIcon(icon: _navEntries[i].$1, size: 20),
                          tooltip: _navEntries[i].$2,
                          color: i == _index
                              ? ore.colors.success
                              : ore.colors.textPrimary,
                          onPressed: () => _select(i),
                        ),
                      ),
                  ],
                ),
              )
            : OreChoiceButtons(
                items: navItems,
                selectedIndex: _index,
                onChanged: _select,
                dock: OreChoiceDock.bottom,
                buttonWidth: mobileButtonWidth,
              ),
      ),
    );
  }
}
