import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mcdev_income/ui/ore_material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const McDevIncomeApp());
}

class McDevIncomeApp extends StatefulWidget {
  const McDevIncomeApp({super.key});

  @override
  State<McDevIncomeApp> createState() => _McDevIncomeAppState();
}

class _McDevIncomeAppState extends State<McDevIncomeApp> {
  final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final stored = await ThemeModeStore.load();
    if (!mounted) {
      return;
    }
    _themeModeNotifier.value = stored;
  }

  @override
  void dispose() {
    _themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeController(
      notifier: _themeModeNotifier,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeModeNotifier,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'MC开发者收益助手',
            themeMode: themeMode,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
              useMaterial3: true,
              extensions: <ThemeExtension<dynamic>>[
                OreThemeData.light(),
              ],
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.dark,
              ),
              brightness: Brightness.dark,
              useMaterial3: true,
              extensions: <ThemeExtension<dynamic>>[
                OreThemeData.dark(),
              ],
            ),
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

class AppThemeController extends InheritedNotifier<ValueNotifier<ThemeMode>> {
  const AppThemeController({
    super.key,
    required ValueNotifier<ThemeMode> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<ThemeMode> of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<AppThemeController>();
    assert(widget != null, 'AppThemeController not found in context.');
    return widget!.notifier!;
  }
}

class ThemeModeStore {
  const ThemeModeStore._();

  static const _key = 'theme_mode';

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
    }
    return ThemeMode.system;
  }

  static String _serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key));
  }

  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _serialize(mode));
  }
}

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
      ore.typography.choiceTitle.copyWith(color: colors.textPrimary);
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
                  data: IconThemeData(color: colors.textPrimary),
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

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _numberFormat = NumberFormat.decimalPattern();
  bool _loading = false;
  String? _error;
  OverviewStats? _stats;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview() async {
    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = null;
        _loading = false;
        _error = '请先到“设置”里通过 WebView 登录。';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final api = McDevApi(
      cookie: cookieHeader,
      category: _categoryValue(_Category.pe),
    );
    try {
      final stats = await api.fetchOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = stats;
        _updatedAt = DateTime.now();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    } finally {
      api.close();
    }
  }

  String _formatInt(int value) => _numberFormat.format(value);

  Widget _buildSimpleCard(
    BuildContext context, {
    required String title,
    required String value,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return OreStrip(
      tone: OreStripTone.dark,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPairCard(
    BuildContext context, {
    required String title,
    required String mainValue,
    required String subtitleLabel,
    required String subtitleValue,
    required int diff,
  }) {
    final theme = Theme.of(context);
    final isUp = diff >= 0;
    final diffText = '${isUp ? '+' : ''}${_formatInt(diff)}';
    final diffColor = isUp ? Colors.green : Colors.red;
    return OreStrip(
      tone: OreStripTone.dark,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              mainValue,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: '$subtitleLabel $subtitleValue',
                style: theme.textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: '  较$subtitleLabel $diffText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: diffColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? '加载失败'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadOverview,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final stats = _stats;
    final columns = width >= 1200 ? 4 : (width >= 900 ? 3 : 1);

    return SafeArea(
      child: Column(
        children: [
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('数据概览', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          _updatedAt == null
                              ? '尚未更新'
                              : '最近更新 ${_dateTimeFormat.format(_updatedAt!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _loadOverview,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading && stats == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(theme)
                    : stats == null
                        ? const Center(child: Text('暂无数据'))
                        : GridView.count(
                            padding: EdgeInsets.zero,
                            crossAxisCount: columns,
                            mainAxisSpacing: 0,
                            crossAxisSpacing: 0,
                            childAspectRatio: columns >= 3 ? 1.6 : 2.4,
                            children: [
                              _buildPairCard(
                                context,
                                title: '本月钻石收益',
                                mainValue: _formatInt(stats.thisMonthDiamond),
                                subtitleLabel: '14天日均',
                                subtitleValue:
                                    _formatInt(stats.days14AverageDiamond),
                                diff: stats.thisMonthDiamond -
                                    stats.days14AverageDiamond,
                              ),
                              _buildPairCard(
                                context,
                                title: '昨日钻石收益',
                                mainValue: _formatInt(stats.yesterdayDiamond),
                                subtitleLabel: '14天日均',
                                subtitleValue:
                                    _formatInt(stats.days14AverageDiamond),
                                diff: stats.yesterdayDiamond -
                                    stats.days14AverageDiamond,
                              ),
                              _buildPairCard(
                                context,
                                title: '本月资源下载数',
                                mainValue: _formatInt(stats.thisMonthDownload),
                                subtitleLabel: '14天日均',
                                subtitleValue:
                                    _formatInt(stats.days14AverageDownload),
                                diff: stats.thisMonthDownload -
                                    stats.days14AverageDownload,
                              ),
                              _buildPairCard(
                                context,
                                title: '昨日资源下载数',
                                mainValue: _formatInt(stats.yesterdayDownload),
                                subtitleLabel: '14天日均',
                                subtitleValue:
                                    _formatInt(stats.days14AverageDownload),
                                diff: stats.yesterdayDownload -
                                    stats.days14AverageDownload,
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

class ModsPage extends StatefulWidget {
  const ModsPage({super.key});

  @override
  State<ModsPage> createState() => _ModsPageState();
}

class _ModsPageState extends State<ModsPage> {
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _numberFormat = NumberFormat.decimalPattern();
  _Category _category = _Category.pe;
  bool _loading = false;
  String? _error;
  List<ModItem> _mods = [];
  String _search = '';
  bool _salesLoading = false;
  String? _salesError;
  Map<String, int> _salesById = {};
  DateTime? _salesUpdatedAt;

  @override
  void initState() {
    super.initState();
    _loadMods();
  }

  Future<void> _loadMods() async {
    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _mods = [];
        _loading = false;
        _error = '请先到“设置”里通过 WebView 登录。';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final api = McDevApi(
      cookie: cookieHeader,
      category: _categoryValue(_category),
    );
    try {
      final mods = await api.fetchMods(onlyPriced: false, onlyPublished: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _mods = mods;
        _loading = false;
        _error = mods.isEmpty ? '未获取到 Mod。' : null;
        _salesById = {};
        _salesError = null;
        _salesUpdatedAt = null;
      });
      if (mods.isNotEmpty) {
        _loadSales(cookieHeader, mods);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    } finally {
      api.close();
    }
  }

  String _analysisCategory(_Category category) {
    return category == _Category.pe ? 'pe' : 'pc';
  }

  Future<Map<String, int>> _fetchSalesInBatches(
    McDevApi api,
    List<String> ids,
    DateTime startDate,
    DateTime endDate,
    String platform,
    String category,
  ) async {
    const batchSize = 10;
    final result = <String, int>{};
    for (var i = 0; i < ids.length; i += batchSize) {
      if (!mounted) {
        return result;
      }
      final batch = ids.sublist(i, min(i + batchSize, ids.length));
      final batchResult = await api.fetchSalesTotals(
        itemIds: batch,
        startDate: startDate,
        endDate: endDate,
        platform: platform,
        category: category,
      );
      result.addAll(batchResult);
    }
    return result;
  }

  Future<void> _loadSales(String cookieHeader, List<ModItem> mods) async {
    if (!mounted) {
      return;
    }
    if (mods.isEmpty) {
      setState(() {
        _salesById = {};
        _salesError = null;
        _salesLoading = false;
        _salesUpdatedAt = null;
      });
      return;
    }
    setState(() {
      _salesLoading = true;
      _salesError = null;
    });

    final api = McDevApi(
      cookie: cookieHeader,
      category: _categoryValue(_category),
    );
    try {
      final ids = mods.map((mod) => mod.id).toList();
      final now = DateTime.now();
      final start7 = now.subtract(const Duration(days: 7));
      final platform = _analysisCategory(_category);
      final category = platform;
      bool allZero(Map<String, int> map) =>
          map.isNotEmpty && map.values.every((value) => value == 0);
      var salesMap = await _fetchSalesInBatches(
        api,
        ids,
        start7,
        now,
        platform,
        category,
      );
      if (salesMap.isEmpty || allZero(salesMap)) {
        final start30 = now.subtract(const Duration(days: 30));
        salesMap = await _fetchSalesInBatches(
          api,
          ids,
          start30,
          now,
          platform,
          category,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _salesById = salesMap;
        _salesLoading = false;
        _salesUpdatedAt = DateTime.now();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _salesLoading = false;
          _salesError = error.toString();
        });
      }
    } finally {
      api.close();
    }
  }

  List<ModItem> _filteredMods() {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) {
      return _mods;
    }
    return _mods
        .where(
          (mod) =>
              mod.name.toLowerCase().contains(query) ||
              mod.id.toLowerCase().contains(query),
        )
        .toList();
  }

  String _statusLabel(ModItem mod) {
    final status = mod.status?.toLowerCase().trim();
    if (status == null || status.isEmpty) {
      return mod.weakOffline == true ? '弱下架' : '未知';
    }
    if (status.contains('online')) {
      return mod.weakOffline == true ? '弱下架' : '已上架';
    }
    if (status.contains('offline')) {
      return '已下架';
    }
    return mod.status ?? '未知';
  }

  Color _statusColor(ThemeData theme, String label) {
    if (label.contains('已上架')) {
      return Colors.green;
    }
    if (label.contains('下架')) {
      return theme.colorScheme.error;
    }
    return theme.colorScheme.primary;
  }

  String _priceLabel(ModItem mod) {
    final price = mod.price;
    if (price == null) {
      return '价格未知';
    }
    if (price <= 0) {
      return '免费';
    }
    final priceText = _numberFormat.format(price);
    final kind = _priceKind(mod.priceType);
    switch (kind) {
      case _PriceKind.diamond:
        return '$priceText 钻石';
      case _PriceKind.emerald:
        return '$priceText 绿宝石';
      case _PriceKind.other:
        return priceText;
    }
  }

  String _salesLabel(ModItem mod) {
    final sales = _salesById[mod.id];
    if (sales != null) {
      return _numberFormat.format(sales);
    }
    if (_salesLoading) {
      return '加载中';
    }
    return '暂无';
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? '加载失败'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadMods,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModCard(ModItem mod, ThemeData theme) {
    final statusLabel = _statusLabel(mod);
    final statusColor = _statusColor(theme, statusLabel);
    final releaseText =
        mod.releaseAt == null ? '上架时间未知' : _dateFormat.format(mod.releaseAt!);

    return OreCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mod.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('ID: ${mod.id}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('价格: ${_priceLabel(mod)}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('总销量: ${_salesLabel(mod)}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('上架: $releaseText', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segmentButtonWidth = OreTokens.controlHeightMd * 2.5;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final filtered = _filteredMods();

    return SafeArea(
      child: Column(
        children: [
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<_Category>(
                    segments: const [
                      ButtonSegment(
                        value: _Category.pe,
                        label: Text('PE'),
                      ),
                      ButtonSegment(
                        value: _Category.java,
                        label: Text('Java'),
                      ),
                    ],
                    selected: {_category},
                    buttonWidth: segmentButtonWidth,
                    onSelectionChanged: _loading
                        ? null
                        : (value) {
                            final next = value.first;
                            if (next == _category) {
                              return;
                            }
                            setState(() {
                              _category = next;
                              _mods = [];
                            });
                            _loadMods();
                          },
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _loadMods,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                    width: segmentButtonWidth,
                  ),
                  Text('显示 ${filtered.length} / 共 ${_mods.length}'),
                  if (_salesLoading) const Text('总销量加载中...'),
                  if (_salesError != null)
                    Text(
                      '总销量加载失败',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  if (!_salesLoading && _salesError == null)
                    Text(
                      _salesUpdatedAt == null
                          ? '总销量未更新'
                          : '总销量更新 ${_dateFormat.format(_salesUpdatedAt!)}',
                    ),
                ],
              ),
            ),
          ),
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: '搜索 Mod 名称或 ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(theme)
                    : filtered.isEmpty
                        ? const Center(child: Text('暂无 Mod'))
                        : Scrollbar(
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: isWide ? 2 : 1,
                                mainAxisSpacing: 0,
                                crossAxisSpacing: 0,
                                mainAxisExtent: isWide ? 190 : 210,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) =>
                                  _buildModCard(filtered[index], theme),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

enum IncomeScope { all, multiple, single }
enum _SummarySortKey { diamonds, releaseTime }

class IncomePreset {
  IncomePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.scope,
    required this.modIds,
    required this.internalRatios,
    required this.neteaseRatios,
    required this.defaultInternalRatio,
    required this.defaultNeteaseRatio,
    required this.taxRate,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final _Category category;
  final IncomeScope scope;
  final List<String> modIds;
  final Map<String, double> internalRatios;
  final Map<String, double> neteaseRatios;
  final double defaultInternalRatio;
  final double defaultNeteaseRatio;
  final double taxRate;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': _categoryValue(category),
      'scope': scope.name,
      'modIds': modIds,
      'internalRatios': internalRatios,
      'neteaseRatios': neteaseRatios,
      'defaultInternalRatio': defaultInternalRatio,
      'defaultNeteaseRatio': defaultNeteaseRatio,
      'taxRate': taxRate,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static IncomePreset fromJson(Map<String, dynamic> json) {
    final rawCategory = json['category']?.toString();
    final rawScope = json['scope']?.toString();
    final modIds = (json['modIds'] as List?)
            ?.map((entry) => entry.toString())
            .toList() ??
        <String>[];
    final internalRatios = _parseDoubleMap(json['internalRatios']);
    final neteaseRatios = _parseDoubleMap(json['neteaseRatios']);
    final defaultInternalRatio =
        _tryParseDouble(json['defaultInternalRatio']) ?? 1.0;
    final defaultNeteaseRatio =
        _tryParseDouble(json['defaultNeteaseRatio']) ?? 1.0;
    final taxRate = _tryParseDouble(json['taxRate']) ?? 0.2;
    final updatedAt =
        DateTime.tryParse(json['updatedAt']?.toString() ?? '');

    return IncomePreset(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名预设',
      category: _categoryFromValue(rawCategory),
      scope: IncomeScope.values.firstWhere(
        (scope) => scope.name == rawScope,
        orElse: () => IncomeScope.all,
      ),
      modIds: modIds,
      internalRatios: internalRatios,
      neteaseRatios: neteaseRatios,
      defaultInternalRatio: defaultInternalRatio,
      defaultNeteaseRatio: defaultNeteaseRatio,
      taxRate: taxRate,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

double? _tryParseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

Map<String, double> _parseDoubleMap(Object? raw) {
  final result = <String, double>{};
  if (raw is Map) {
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = _tryParseDouble(entry.value);
      if (value != null) {
        result[key] = value;
      }
    }
  }
  return result;
}

DateTime? _parseModReleaseAt(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is num) {
    return _epochToDateTime(raw.toInt());
  }
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final numeric = num.tryParse(text);
    if (numeric != null) {
      return _epochToDateTime(numeric.toInt());
    }
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      return parsed.toLocal();
    }
  }
  return null;
}

DateTime? _epochToDateTime(int value) {
  if (value <= 0) {
    return null;
  }
  if (value < 1000000000000) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
        .toLocal();
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
}

class _ParsedRate {
  const _ParsedRate(this.value, {this.error, this.isDefault = false});

  final double value;
  final String? error;
  final bool isDefault;

  bool get isValid => error == null;
}

class _ShareResult {
  const _ShareResult(this.netValue, {this.error});

  final double netValue;
  final String? error;

  bool get isValid => error == null;
}

class _RangePickerPanel extends StatefulWidget {
  const _RangePickerPanel({
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_RangePickerPanel> createState() => _RangePickerPanelState();
}

class _RangePickerPanelState extends State<_RangePickerPanel> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  final _format = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.initialStart;
    _rangeEnd = widget.initialEnd;
  }

  void _onDateTapped(DateTime date) {
    if (_rangeStart == null || _rangeEnd != null) {
      setState(() {
        _rangeStart = date;
        _rangeEnd = null;
      });
      return;
    }
    var start = _rangeStart!;
    var end = date;
    if (end.isBefore(start)) {
      final temp = start;
      start = end;
      end = temp;
    }
    Navigator.of(context).pop(DateTimeRange(start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _rangeStart == null
        ? '未选'
        : _format.format(_rangeStart!);
    final endLabel = _rangeEnd == null ? '未选' : _format.format(_rangeEnd!);
    final initialDate = _rangeEnd ?? _rangeStart ?? DateTime.now();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '选择时间范围',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('开始: $startLabel')),
                Expanded(child: Text('结束: $endLabel')),
              ],
            ),
            const SizedBox(height: 8),
            CalendarDatePicker(
              initialDate: initialDate,
              firstDate: DateTime(2020, 1, 1),
              lastDate: DateTime(DateTime.now().year + 1, 12, 31),
              onDateChanged: _onDateTapped,
            ),
            const SizedBox(height: 4),
            Text('点击起止日期后自动查询', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class LoginCookieHelper {
  static final _cookieUrls = [
    WebUri('https://mc-launcher.webapp.163.com/'),
    WebUri('https://mcdev.webapp.163.com/'),
  ];

  static Future<Map<String, String>> readCookies() async {
    final manager = CookieManager.instance();
    final cookieMap = <String, String>{};

    for (final url in _cookieUrls) {
      final cookies = await manager.getCookies(url: url);
      for (final cookie in cookies) {
        final name = cookie.name;
        if (name.isEmpty) {
          continue;
        }
        cookieMap[name] = cookie.value;
      }
    }

    return cookieMap;
  }

  static Future<String> buildCookieHeader() async {
    final cookies = await readCookies();
    if (cookies.isEmpty) {
      return '';
    }
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}

final _sensitiveKeyPattern = RegExp(
  r'(token|secret|password|passwd|cookie|session|auth|sid|uid|email|phone|mobile)',
  caseSensitive: false,
);

class _InfoItem {
  const _InfoItem(this.label, this.value);

  final String label;
  final String value;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = false;
  String _statusText = '未登录';
  int _cookieCount = 0;
  DateTime? _checkedAt;

  bool _devLoading = false;
  String? _devError;
  DeveloperProfile? _developerProfile;

  final _timeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _refreshStatus().then((loggedIn) {
      if (loggedIn) {
        _loadDeveloperProfile();
      }
    });
  }

  Future<bool> _refreshStatus() async {
    setState(() => _loading = true);
    final cookies = await LoginCookieHelper.readCookies();
    if (!mounted) {
      return false;
    }
    final count = cookies.length;
    final loggedIn = count > 0;
    setState(() {
      _cookieCount = count;
      _statusText = loggedIn ? '已登录' : '未登录';
      _checkedAt = DateTime.now();
      _loading = false;
    });
    return loggedIn;
  }

  Future<void> _openLoginWebView() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const LoginWebViewPage()),
    );
    if (result == true) {
      await _refreshStatus();
      await _loadDeveloperProfile();
    }
  }

  Future<void> _openDeveloperDetails() async {
    if (_devLoading) {
      return;
    }
    if (_developerProfile == null) {
      await _loadDeveloperProfile();
    }
    if (!mounted) {
      return;
    }
    final profile = _developerProfile;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获取到开发者信息，请稍后重试。')),
      );
      return;
    }

    final detailItems = _buildDeveloperInfoItems(profile)
        .where((item) => item.label != '昵称' && item.label != '简介')
        .toList();

    if (detailItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无更多可显示的开发者信息。')),
      );
      return;
    }

    final isWide = MediaQuery.of(context).size.width >= 900;
    if (isWide) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '开发者更多信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: detailItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = detailItems[index];
                          return ListTile(
                            dense: true,
                            title: Text(item.label),
                            subtitle: Text(item.value),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '开发者更多信息',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: detailItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = detailItems[index];
                        return ListTile(
                          dense: true,
                          title: Text(item.label),
                          subtitle: Text(item.value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _loadDeveloperProfile() async {
    setState(() {
      _devLoading = true;
      _devError = null;
    });

    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _devLoading = false;
        _devError = '请先登录后再获取开发者信息。';
      });
      return;
    }

    final api = McDevApi(cookie: cookieHeader, category: 'pe');
    try {
      final profile = await api.fetchDeveloperProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _developerProfile = profile;
        _devLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _devLoading = false;
        _devError = error.toString();
      });
    } finally {
      api.close();
    }
  }

  List<_InfoItem> _buildDeveloperInfoItems(DeveloperProfile profile) {
    final items = <_InfoItem>[];
    final usedKeys = <String>{};

    final status = profile.status;
    if (status != null && status.isNotEmpty) {
      items.add(_InfoItem('作者状态', _mapAuthorStatus(status)));
    }

    final updatedAt = _formatIso(profile.updatedAt);
    if (updatedAt != null) {
      items.add(_InfoItem('资料更新时间', updatedAt));
    }

    final bio = profile.bio == null ? null : _stripHtml(profile.bio!);
    if (bio != null && bio.isNotEmpty) {
      items.add(_InfoItem('简介', bio));
    }

    final user = profile.userRaw;
    if (user != null) {
      final nickname = _pickStringEntry(user, [
        'nickname',
        'nick_name',
        'user_name',
        'username',
        'name',
        'display_name',
      ]);
      if (nickname != null) {
        items.add(_InfoItem('昵称', nickname.value));
        usedKeys.add(nickname.key);
      }

      final userId = _pickStringEntry(user, [
        'uid',
        'user_id',
        'id',
        'account_id',
      ]);
      if (userId != null) {
        items.add(_InfoItem('账号ID', userId.value));
        usedKeys.add(userId.key);
      }

      final realName =
          _pickStringEntry(user, ['real_name', 'realname', 'realName']);
      if (realName != null) {
        items.add(_InfoItem('真实姓名', realName.value));
        usedKeys.add(realName.key);
      }

      final isRealName = _pickStringEntry(user, ['is_unirealname']);
      if (isRealName != null) {
        items.add(_InfoItem('实名认证', _formatBool(isRealName.value)));
        usedKeys.add(isRealName.key);
      }

      final email = _pickStringEntry(user, ['email']);
      if (email != null) {
        items.add(_InfoItem('邮箱', _maskValue(email.key, email.value)));
        usedKeys.add(email.key);
      }

      final phone = _pickStringEntry(user, ['mobile', 'phone']);
      if (phone != null) {
        items.add(_InfoItem('手机号', _maskValue(phone.key, phone.value)));
        usedKeys.add(phone.key);
      }

      final qq = _pickStringEntry(user, ['qq']);
      if (qq != null) {
        items.add(_InfoItem('QQ', _maskValue(qq.key, qq.value)));
        usedKeys.add(qq.key);
      }

      final province = _pickStringEntry(user, ['province']);
      if (province != null) {
        items.add(_InfoItem('省份', province.value));
        usedKeys.add(province.key);
      }

      final city = _pickStringEntry(user, ['city']);
      if (city != null) {
        items.add(_InfoItem('城市', city.value));
        usedKeys.add(city.key);
      }

      final provider = _pickStringEntry(user, ['provider_name']);
      if (provider != null) {
        items.add(_InfoItem('签约主体', provider.value));
        usedKeys.add(provider.key);
      }

      final authority = _pickStringEntry(user, ['official_authority']);
      if (authority != null) {
        items.add(_InfoItem('官方资质', authority.value));
        usedKeys.add(authority.key);
      }

      final cardNo = _pickStringEntry(user, ['card_no', 'id_card', 'idcard']);
      if (cardNo != null) {
        items.add(_InfoItem('证件号', _maskValue(cardNo.key, cardNo.value)));
        usedKeys.add(cardNo.key);
      }

      final enterpriseApplying =
          _pickStringEntry(user, ['is_enterprise_applying']);
      if (enterpriseApplying != null) {
        items.add(
          _InfoItem('企业认证申请中', _formatBool(enterpriseApplying.value)),
        );
        usedKeys.add(enterpriseApplying.key);
      }

      final enterpriseExpired =
          _pickStringEntry(user, ['is_enterprise_expired']);
      if (enterpriseExpired != null) {
        items.add(
          _InfoItem('企业认证已过期', _formatBool(enterpriseExpired.value)),
        );
        usedKeys.add(enterpriseExpired.key);
      }

      final needEnterprise = _pickStringEntry(user, ['need_enterprise_apply']);
      if (needEnterprise != null) {
        items.add(_InfoItem('需要企业认证', _formatBool(needEnterprise.value)));
        usedKeys.add(needEnterprise.key);
      }

      final enterpriseDeadline =
          _pickStringEntry(user, ['enterprise_deadline']);
      if (enterpriseDeadline != null) {
        items.add(_InfoItem('企业认证到期', enterpriseDeadline.value));
        usedKeys.add(enterpriseDeadline.key);
      }
    }

    return items;
  }

  _InfoItem? _findItem(List<_InfoItem> items, String label) {
    for (final item in items) {
      if (item.label == label) {
        return item;
      }
    }
    return null;
  }

  String _mapAuthorStatus(String raw) {
    switch (raw.toLowerCase()) {
      case 'accept':
        return '已通过';
      case 'pending':
        return '审核中';
      case 'reject':
        return '未通过';
      default:
        return raw;
    }
  }

  String? _formatIso(String? iso) {
    if (iso == null || iso.isEmpty) {
      return null;
    }
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _stripHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  String _maskValue(String key, String value) {
    if (key.toLowerCase().contains('email')) {
      final parts = value.split('@');
      if (parts.length == 2) {
        final name = parts.first;
        final domain = parts.last;
        if (name.length <= 2) {
          return '${name.substring(0, 1)}***@$domain';
        }
        return '${name.substring(0, 2)}***@${domain}';
      }
    }
    if (key.toLowerCase().contains('qq')) {
      if (value.length >= 4) {
        return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
      }
    }
    if (key.toLowerCase().contains('phone') ||
        key.toLowerCase().contains('mobile')) {
      if (value.length >= 7) {
        return '${value.substring(0, 3)}****${value.substring(value.length - 2)}';
      }
    }
    if (key.toLowerCase().contains('card')) {
      if (value.length >= 8) {
        return '${value.substring(0, 4)}********${value.substring(value.length - 2)}';
      }
    }
    return value;
  }

  String _formatBool(String raw) {
    final text = raw.toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') {
      return '是';
    }
    if (text == '0' || text == 'false' || text == 'no') {
      return '否';
    }
    return raw;
  }

  MapEntry<String, String>? _pickStringEntry(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString();
      if (text.isNotEmpty) {
        return MapEntry(key, text);
      }
    }
    return null;
  }

  int _themeModeIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 0;
      case ThemeMode.dark:
        return 1;
      case ThemeMode.system:
        return 2;
    }
  }

  ThemeMode _themeModeFromIndex(int index) {
    switch (index) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  double _choiceButtonWidth(BuildContext context, List<String> labels) {
    final ore = OreTheme.of(context);
    final style = ore.typography.label;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
    );
    var maxWidth = 0.0;
    for (final label in labels) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      if (painter.width > maxWidth) {
        maxWidth = painter.width;
      }
    }
    final horizontalPadding =
        ore.borderWidth * OreTokens.buttonPadMdHUnits * 2;
    return maxWidth + horizontalPadding;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeNotifier = AppThemeController.of(context);
    final themeMode = themeNotifier.value;
    final themeLabels = const ['浅色模式', '深色模式', '跟随系统'];
    final themeIndex = _themeModeIndex(themeMode);
    final themeButtonWidth = _choiceButtonWidth(context, themeLabels);
    final actionButtonWidth = OreTokens.controlHeightMd * 5;
    final checkedAt = _checkedAt == null
        ? '未检查'
        : _timeFormat.format(_checkedAt!);
    final devItems = _developerProfile == null
        ? null
        : _buildDeveloperInfoItems(_developerProfile!);
    final nicknameItem =
        devItems == null ? null : _findItem(devItems, '昵称');
    final bioItem = devItems == null ? null : _findItem(devItems, '简介');

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题模式', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  OreChoiceButtons(
                    items:
                        themeLabels.map((label) => Text(label)).toList(),
                    selectedIndex: themeIndex,
                    onChanged: (value) {
                      final next = _themeModeFromIndex(value);
                      if (next == themeNotifier.value) {
                        return;
                      }
                      themeNotifier.value = next;
                      ThemeModeStore.save(next);
                    },
                    buttonWidth: themeButtonWidth,
                  ),
                ],
              ),
            ),
          ),
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('登录状态', style: theme.textTheme.titleMedium),
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('状态: $_statusText'),
                  Text('Cookie 数量: $_cookieCount'),
                  const SizedBox(height: 4),
                  Text('上次检查: $checkedAt', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _openLoginWebView,
                        icon: const Icon(Icons.login),
                        label: const Text('WebView 登录'),
                        width: actionButtonWidth,
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () async {
                                final loggedIn = await _refreshStatus();
                                if (loggedIn) {
                                  await _loadDeveloperProfile();
                                }
                              },
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新状态'),
                        width: actionButtonWidth,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '开发者信息',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (_devLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_developerProfile == null && !_devLoading)
                    Text(
                      _statusText == '已登录'
                          ? '未加载到开发者信息，请点击“刷新信息”。'
                          : '请先登录后获取开发者信息。',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (_devError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _devError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (_developerProfile != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_developerProfile!.avatarUrl != null)
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: NetworkImage(
                              _developerProfile!.avatarUrl!,
                            ),
                          ),
                        if (_developerProfile!.avatarUrl != null)
                          const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nicknameItem?.value ?? '昵称未获取',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                bioItem?.value ?? '暂无简介',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _devLoading ? null : _loadDeveloperProfile,
                        icon: const Icon(Icons.person_search),
                        label:
                            Text(_developerProfile == null ? '加载信息' : '刷新信息'),
                        width: actionButtonWidth,
                      ),
                      ElevatedButton.icon(
                        onPressed: _devLoading ? null : _openDeveloperDetails,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('查看更多'),
                        width: actionButtonWidth,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IncomePage extends StatefulWidget {
  const IncomePage({super.key});

  @override
  State<IncomePage> createState() => _IncomePageState();
}

class _IncomePageState extends State<IncomePage> {
  final _dateFormat = DateFormat('yyyy-MM-dd');
  static const _presetStorageKey = 'income_presets_v1';

  DateTimeRange? _range;
  _Category _category = _Category.pe;
  _Category? _modsCategory;
  IncomeScope _scope = IncomeScope.all;
  bool _loading = false;
  String? _error;

  int _totalDiamonds = 0;
  int _totalPoints = 0;
  int _refundPendingOrders = 0;
  int _refundedOrders = 0;
  int _refundOtherOrders = 0;
  int _processed = 0;
  int _totalMods = 0;
  int _diamondPricedMods = 0;
  int _emeraldPricedMods = 0;
  int _otherPricedMods = 0;
  List<IncomeSummary> _summaries = [];
  List<ModItem> _mods = [];
  bool _modsLoading = false;
  String? _modsError;
  String _modSearch = '';
  Set<String> _selectedModIds = {};
  String? _singleModId;
  String? _lastSelectedModId;
  _SummarySortKey _summarySortKey = _SummarySortKey.diamonds;
  bool _summarySortAscending = false;
  Map<String, String> _internalRatioTextByModId = {};
  Map<String, String> _neteaseRatioTextByModId = {};
  final Map<String, TextEditingController> _internalRatioControllers = {};
  final Map<String, TextEditingController> _neteaseRatioControllers = {};
  final TextEditingController _defaultInternalRatioController =
      TextEditingController(text: '1.0');
  final TextEditingController _defaultNeteaseRatioController =
      TextEditingController(text: '1.0');
  final TextEditingController _taxRateController =
      TextEditingController(text: '0.2');
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  List<IncomePreset> _presets = [];
  String? _selectedPresetId;

  @override
  void initState() {
    super.initState();
    _loadPresets();
    _loadMods(silent: true);
    _defaultInternalRatioController.addListener(_onShareParamChanged);
    _defaultNeteaseRatioController.addListener(_onShareParamChanged);
    _taxRateController.addListener(_onShareParamChanged);
  }

  @override
  void dispose() {
    for (final controller in _internalRatioControllers.values) {
      controller.dispose();
    }
    for (final controller in _neteaseRatioControllers.values) {
      controller.dispose();
    }
    _defaultInternalRatioController.removeListener(_onShareParamChanged);
    _defaultNeteaseRatioController.removeListener(_onShareParamChanged);
    _taxRateController.removeListener(_onShareParamChanged);
    _defaultInternalRatioController.dispose();
    _defaultNeteaseRatioController.dispose();
    _taxRateController.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  void _onShareParamChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  String _rangeLabel() {
    final range = _range;
    if (range == null) {
      return '未选择';
    }
    return '${_dateFormat.format(range.start)} ~ ${_dateFormat.format(range.end)}';
  }

  String _scopeLabel() {
    switch (_scope) {
      case IncomeScope.all:
        return '全部';
      case IncomeScope.multiple:
        return '多个';
      case IncomeScope.single:
        return '单个';
    }
  }

  String _scopePreviewFor(IncomeScope scope) {
    final total = _mods.length;
    switch (scope) {
      case IncomeScope.all:
        return '当前：全部（${total > 0 ? total : '未加载'}）';
      case IncomeScope.multiple:
        return '当前：多选（已选 ${_selectedModIds.length}/$total）';
      case IncomeScope.single:
        final name = _modNameById(_singleModId);
        return '当前：单选（${name.isEmpty ? '未选择' : name}）';
    }
  }

  String _modNameById(String? id) {
    if (id == null || id.isEmpty) {
      return '';
    }
    for (final mod in _mods) {
      if (mod.id == id) {
        return mod.name;
      }
    }
    return id;
  }

  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_presetStorageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      final presets = <IncomePreset>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          presets.add(IncomePreset.fromJson(entry));
        } else if (entry is Map) {
          presets.add(IncomePreset.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ));
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _presets = presets;
      });
    } catch (_) {
      // 忽略损坏数据
    }
  }

  Future<void> _persistPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _presets.map((preset) => preset.toJson()).toList();
    await prefs.setString(_presetStorageKey, jsonEncode(payload));
  }

  Future<void> _saveNewPreset() async {
    final name = await _promptPresetName(title: '新建预设');
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final preset = _buildPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
    );
    setState(() {
      _presets = [preset, ..._presets];
      _selectedPresetId = preset.id;
    });
    await _persistPresets();
  }

  Future<void> _updateSelectedPreset() async {
    final presetId = _selectedPresetId;
    if (presetId == null) {
      return;
    }
    final index = _presets.indexWhere((preset) => preset.id == presetId);
    if (index < 0) {
      return;
    }
    final existing = _presets[index];
    final updated = _buildPreset(id: existing.id, name: existing.name);
    setState(() {
      final next = List<IncomePreset>.from(_presets);
      next[index] = updated;
      _presets = next;
    });
    await _persistPresets();
  }

  Future<void> _showPresetManager() async {
    if (_presets.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无预设')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final preset = _presets[index];
                return ListTile(
                  title: Text(preset.name),
                  subtitle: Text(
                    '${_categoryLabel(preset.category)} · ${_scopeLabelForPreset(preset.scope)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: '重命名',
                        onPressed: () async {
                          final name = await _promptPresetName(
                            title: '重命名预设',
                            initial: preset.name,
                          );
                          if (name == null || name.trim().isEmpty) {
                            return;
                          }
                          final updated = IncomePreset(
                            id: preset.id,
                            name: name.trim(),
                            category: preset.category,
                            scope: preset.scope,
                            modIds: preset.modIds,
                            internalRatios: preset.internalRatios,
                            neteaseRatios: preset.neteaseRatios,
                            defaultInternalRatio: preset.defaultInternalRatio,
                            defaultNeteaseRatio: preset.defaultNeteaseRatio,
                            taxRate: preset.taxRate,
                            updatedAt: preset.updatedAt,
                          );
                          setState(() {
                            final next = List<IncomePreset>.from(_presets);
                            next[index] = updated;
                            _presets = next;
                          });
                          sheetSetState(() {});
                          await _persistPresets();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除',
                        onPressed: () async {
                          setState(() {
                            _presets =
                                _presets.where((p) => p.id != preset.id).toList();
                            if (_selectedPresetId == preset.id) {
                              _selectedPresetId = null;
                            }
                          });
                          sheetSetState(() {});
                          await _persistPresets();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<String?> _promptPresetName({
    required String title,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final dialogButtonWidth = OreTokens.controlHeightMd * 3;
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '预设名称',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
              width: dialogButtonWidth,
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('确定'),
              width: dialogButtonWidth,
            ),
          ],
        );
      },
    );
    return result;
  }

  IncomePreset _buildPreset({required String id, required String name}) {
    final modIds = _currentSelectedModIds();
    final internalRatios = _collectRatioValues(
      _internalRatioTextByModId,
      limitIds: _scope == IncomeScope.all ? null : modIds,
    );
    final neteaseRatios = _collectRatioValues(
      _neteaseRatioTextByModId,
      limitIds: _scope == IncomeScope.all ? null : modIds,
    );
    final defaultInternalRatio = _parseRate(
      _defaultInternalRatioController.text,
      fieldName: '默认内部分成',
      defaultValue: 1.0,
      invalidValue: 1.0,
    ).value;
    final defaultNeteaseRatio = _parseRate(
      _defaultNeteaseRatioController.text,
      fieldName: '默认网易分成',
      defaultValue: 1.0,
      invalidValue: 1.0,
    ).value;
    final taxRate = _parseRate(
      _taxRateController.text,
      fieldName: '税收比例',
      defaultValue: 0.2,
      invalidValue: 0.2,
    ).value;
    return IncomePreset(
      id: id,
      name: name,
      category: _category,
      scope: _scope,
      modIds: modIds,
      internalRatios: internalRatios,
      neteaseRatios: neteaseRatios,
      defaultInternalRatio: defaultInternalRatio,
      defaultNeteaseRatio: defaultNeteaseRatio,
      taxRate: taxRate,
      updatedAt: DateTime.now(),
    );
  }

  List<String> _currentSelectedModIds() {
    switch (_scope) {
      case IncomeScope.all:
        return [];
      case IncomeScope.multiple:
        if (_mods.isEmpty) {
          return _selectedModIds.toList();
        }
        return _mods
            .where((mod) => _selectedModIds.contains(mod.id))
            .map((mod) => mod.id)
            .toList();
      case IncomeScope.single:
        return _singleModId == null ? [] : [_singleModId!];
    }
  }

  Map<String, double> _collectRatioValues(
    Map<String, String> source, {
    List<String>? limitIds,
  }) {
    final ratios = <String, double>{};
    final keys = limitIds ?? source.keys;
    for (final id in keys) {
      final raw = source[id];
      if (raw == null) {
        continue;
      }
      final value = double.tryParse(raw.trim());
      if (value != null) {
        ratios[id] = value;
      }
    }
    return ratios;
  }

  Future<void> _applyPresetById(String? presetId) async {
    if (presetId == null) {
      return;
    }
    IncomePreset? preset;
    for (final entry in _presets) {
      if (entry.id == presetId) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      return;
    }
    setState(() {
      _selectedPresetId = presetId;
    });
    await _applyPreset(preset);
  }

  Future<void> _applyPreset(IncomePreset preset) async {
    if (_category != preset.category) {
      setState(() {
        _category = preset.category;
      });
    }
    await _loadMods(silent: true);
    if (!mounted) {
      return;
    }

    final availableIds = _mods.map((mod) => mod.id).toSet();
    final missing = <String>[];
    final selectedIds = <String>[];
    String? singleId;

    switch (preset.scope) {
      case IncomeScope.all:
        break;
      case IncomeScope.multiple:
        for (final id in preset.modIds) {
          if (availableIds.contains(id)) {
            selectedIds.add(id);
          } else {
            missing.add(id);
          }
        }
        break;
      case IncomeScope.single:
        final id = preset.modIds.isNotEmpty ? preset.modIds.first : null;
        if (id != null) {
          if (availableIds.contains(id)) {
            singleId = id;
          } else {
            missing.add(id);
          }
        }
        break;
    }

    setState(() {
      _scope = preset.scope;
      _selectedModIds = selectedIds.toSet();
      _singleModId = singleId;
      _lastSelectedModId =
          singleId ?? (selectedIds.isNotEmpty ? selectedIds.last : null);
      _internalRatioTextByModId = preset.internalRatios.map(
        (key, value) => MapEntry(key, _formatRatio(value)),
      );
      _neteaseRatioTextByModId = preset.neteaseRatios.map(
        (key, value) => MapEntry(key, _formatRatio(value)),
      );
      _defaultInternalRatioController.text =
          _formatRatio(preset.defaultInternalRatio);
      _defaultNeteaseRatioController.text =
          _formatRatio(preset.defaultNeteaseRatio);
      _taxRateController.text = _formatRatio(preset.taxRate);
      _modSearch = '';
    });
    _syncRatioControllers();

    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已忽略 ${missing.length} 个不存在的 Mod')),
      );
    }
  }

  Future<List<ModItem>> _loadMods({bool silent = false}) async {
    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      if (!silent && mounted) {
        setState(() {
          _mods = [];
          _modsLoading = false;
          _modsError = '请先到“设置”里通过 WebView 登录。';
        });
      }
      return [];
    }

    if (mounted) {
      setState(() {
        _modsLoading = true;
        if (!silent) {
          _modsError = null;
        }
      });
    }

    final api = McDevApi(
      cookie: cookieHeader,
      category: _categoryValue(_category),
    );
    try {
      final mods = await api.fetchMods();
      if (!mounted) {
        return mods;
      }
      final availableIds = mods.map((mod) => mod.id).toSet();
      setState(() {
        _mods = mods;
        _modsCategory = _category;
        _modsLoading = false;
        _modsError =
            mods.isEmpty ? '未获取到任何 Mod，请确认账号权限与类别。' : null;
        _selectedModIds =
            _selectedModIds.where(availableIds.contains).toSet();
        if (_singleModId != null && !availableIds.contains(_singleModId)) {
          _singleModId = null;
        }
        if (_lastSelectedModId != null &&
            !availableIds.contains(_lastSelectedModId)) {
          _lastSelectedModId = null;
        }
      });
      return mods;
    } catch (error) {
      if (mounted) {
        setState(() {
          _modsLoading = false;
          _modsError = error.toString();
        });
      }
      return [];
    } finally {
      api.close();
    }
  }

  Future<List<ModItem>> _ensureModsLoaded() async {
    if (_mods.isNotEmpty && _modsCategory == _category) {
      return _mods;
    }
    return _loadMods();
  }

  void _setScope(IncomeScope value) {
    if (_scope == value) {
      return;
    }
    setState(() {
      if (value == IncomeScope.multiple) {
        if (_singleModId != null) {
          _selectedModIds.add(_singleModId!);
          _lastSelectedModId = _singleModId;
        }
      } else if (value == IncomeScope.single) {
        if (_singleModId == null) {
          if (_lastSelectedModId != null) {
            _singleModId = _lastSelectedModId;
          } else if (_selectedModIds.isNotEmpty) {
            _singleModId = _selectedModIds.first;
          }
        }
      }
      _scope = value;
    });
  }

  void _toggleMultiSelection(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedModIds.add(id);
      } else {
        _selectedModIds.remove(id);
      }
      _lastSelectedModId = id;
    });
  }

  void _selectSingle(String id) {
    setState(() {
      _singleModId = id;
      _lastSelectedModId = id;
    });
  }

  void _selectAllMods() {
    setState(() {
      _selectedModIds = _mods.map((mod) => mod.id).toSet();
      if (_selectedModIds.isNotEmpty) {
        _lastSelectedModId = _selectedModIds.last;
      }
    });
  }

  void _clearModSelection() {
    setState(() {
      _selectedModIds.clear();
    });
  }

  void _invertModSelection() {
    final all = _mods.map((mod) => mod.id).toSet();
    setState(() {
      _selectedModIds = all.difference(_selectedModIds);
      if (_selectedModIds.isNotEmpty) {
        _lastSelectedModId = _selectedModIds.last;
      }
    });
  }

  String _formatNumber(num value) {
    final doubleValue = value.toDouble();
    if (doubleValue == doubleValue.roundToDouble()) {
      return doubleValue.toInt().toString();
    }
    return doubleValue.toStringAsFixed(2);
  }

  List<IncomeSummary> _sortedSummaries(List<IncomeSummary> input) {
    final list = List<IncomeSummary>.from(input);
    list.sort((a, b) {
      switch (_summarySortKey) {
        case _SummarySortKey.diamonds:
          final cmp = a.totalDiamonds.compareTo(b.totalDiamonds);
          return _summarySortAscending ? cmp : -cmp;
        case _SummarySortKey.releaseTime:
          return _compareReleaseTime(a.releaseAt, b.releaseAt);
      }
    });
    return list;
  }

  int _compareReleaseTime(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    final cmp = a.compareTo(b);
    return _summarySortAscending ? cmp : -cmp;
  }

  String _formatRatio(double value) {
    final text = value.toString();
    if (!text.contains('.')) {
      return text;
    }
    return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  _ParsedRate _parseRate(
    String? raw, {
    required String fieldName,
    required double defaultValue,
    double invalidValue = 0,
  }) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return _ParsedRate(defaultValue, isDefault: true);
    }
    final value = double.tryParse(text);
    if (value == null) {
      return _ParsedRate(invalidValue, error: '$fieldName格式错误');
    }
    return _ParsedRate(value);
  }

  void _syncRatioControllers() {
    for (final entry in _internalRatioControllers.entries) {
      final text = _internalRatioTextByModId[entry.key] ?? '';
      if (entry.value.text != text) {
        entry.value.text = text;
      }
    }
    for (final entry in _neteaseRatioControllers.entries) {
      final text = _neteaseRatioTextByModId[entry.key] ?? '';
      if (entry.value.text != text) {
        entry.value.text = text;
      }
    }
  }

  String _categoryLabel(_Category category) {
    return category == _Category.pe ? 'PE' : 'Java';
  }

  String _scopeLabelForPreset(IncomeScope scope) {
    switch (scope) {
      case IncomeScope.all:
        return '全部';
      case IncomeScope.multiple:
        return '多个';
      case IncomeScope.single:
        return '单个';
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initialStart =
        _range?.start ?? DateTime(now.year, now.month, now.day);
    final initialEnd = _range?.end ?? initialStart;
    final isWide = MediaQuery.of(context).size.width >= 900;

    DateTimeRange? picked;
    if (isWide) {
      picked = await showDialog<DateTimeRange>(
        context: context,
        builder: (context) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _RangePickerPanel(
                initialStart: initialStart,
                initialEnd: initialEnd,
              ),
            ),
          );
        },
      );
    } else {
      picked = await showModalBottomSheet<DateTimeRange>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _RangePickerPanel(
              initialStart: initialStart,
              initialEnd: initialEnd,
            ),
          );
        },
      );
    }

    if (picked != null) {
      setState(() {
        _range = picked;
      });
      if (!_loading) {
        final cookieHeader = await LoginCookieHelper.buildCookieHeader();
        if (cookieHeader.isNotEmpty) {
          await _runQuery();
        }
      }
    }
  }

  Future<void> _runQuery() async {
    final range = _range;

    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      setState(() => _error = '请先到“设置”里通过 WebView 登录。');
      return;
    }
    if (range == null) {
      setState(() => _error = '请选择时间范围。');
      return;
    }

    final mods = await _ensureModsLoaded();
    if (!mounted) {
      return;
    }
    if (mods.isEmpty) {
      setState(() {
        _error = '未获取到任何 Mod，请确认账号权限与类别。';
      });
      return;
    }

    List<ModItem> targetMods = [];
    switch (_scope) {
      case IncomeScope.all:
        targetMods = mods;
        break;
      case IncomeScope.multiple:
        if (_selectedModIds.isEmpty) {
          setState(() {
            _error = '请选择要统计的 Mod。';
          });
          return;
        }
        targetMods =
            mods.where((mod) => _selectedModIds.contains(mod.id)).toList();
        break;
      case IncomeScope.single:
        if (_singleModId == null) {
          setState(() {
            _error = '请选择一个 Mod。';
          });
          return;
        }
        targetMods = mods.where((mod) => mod.id == _singleModId).toList();
        break;
    }
    if (targetMods.isEmpty) {
      setState(() {
        _error = '当前选择的 Mod 不存在或不可用。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _summaries = [];
      _totalDiamonds = 0;
      _totalPoints = 0;
      _refundPendingOrders = 0;
      _refundedOrders = 0;
      _refundOtherOrders = 0;
      _processed = 0;
      _totalMods = 0;
      _diamondPricedMods = 0;
      _emeraldPricedMods = 0;
      _otherPricedMods = 0;
    });

    final api = McDevApi(
      cookie: cookieHeader,
      category: _categoryValue(_category),
    );

    try {
      final isWide = MediaQuery.of(context).size.width >= 900;
      final batchSize = isWide ? 12 : 6;
      setState(() {
        _totalMods = targetMods.length;
      });

      final summaries = <IncomeSummary>[];
      int diamonds = 0;
      int points = 0;
      int diamondPriced = 0;
      int emeraldPriced = 0;
      int otherPriced = 0;
      int refundPending = 0;
      int refunded = 0;
      int refundOther = 0;
      int processed = 0;

      for (var i = 0; i < targetMods.length; i += batchSize) {
        final batch =
            targetMods.sublist(i, min(i + batchSize, targetMods.length));
        final results = await Future.wait(
          batch.map((mod) => api.fetchIncomeWithRetry(mod, range)),
        );
        if (!mounted) {
          return;
        }
        processed += results.length;
        for (final summary in results) {
          if (summary.error == null) {
            summaries.add(summary);
            diamonds += summary.totalDiamonds;
            points += summary.totalPoints;
            refundPending += summary.refundPendingCount;
            refunded += summary.refundedCount;
            refundOther += summary.refundOtherCount;
            final kind = _priceKind(summary.priceType);
            switch (kind) {
              case _PriceKind.diamond:
                diamondPriced += 1;
                break;
              case _PriceKind.emerald:
                emeraldPriced += 1;
                break;
              case _PriceKind.other:
                otherPriced += 1;
                break;
            }
          }
        }

        setState(() {
          _processed = processed;
          _summaries = List.of(summaries);
          _totalDiamonds = diamonds;
          _totalPoints = points;
          _refundPendingOrders = refundPending;
          _refundedOrders = refunded;
          _refundOtherOrders = refundOther;
          _diamondPricedMods = diamondPriced;
          _emeraldPricedMods = emeraldPriced;
          _otherPricedMods = otherPriced;
        });
      }

      summaries.sort((a, b) => b.totalDiamonds.compareTo(a.totalDiamonds));

      setState(() {
        _summaries = summaries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segmentButtonWidth = OreTokens.controlHeightMd * 2.5;
    final modSelectButtonWidth = OreTokens.controlHeightMd * 3;
    final defaultInternalParse = _parseRate(
      _defaultInternalRatioController.text,
      fieldName: '默认内部分成',
      defaultValue: 1.0,
      invalidValue: 1.0,
    );
    final defaultNeteaseParse = _parseRate(
      _defaultNeteaseRatioController.text,
      fieldName: '默认网易分成',
      defaultValue: 1.0,
      invalidValue: 1.0,
    );
    final taxParse = _parseRate(
      _taxRateController.text,
      fieldName: '税收比例',
      defaultValue: 0.2,
      invalidValue: 0.2,
    );
    final hasGlobalError =
        !defaultInternalParse.isValid ||
        !defaultNeteaseParse.isValid ||
        !taxParse.isValid;
    final shareResults = <String, _ShareResult>{};
    double shareTotal = 0;
    int ratioErrors = 0;
    if (_summaries.isNotEmpty) {
      for (final summary in _summaries) {
        final internalParse = _parseRate(
          _internalRatioTextByModId[summary.itemId],
          fieldName: '内部分成',
          defaultValue: defaultInternalParse.value,
          invalidValue: 0,
        );
        final neteaseParse = _parseRate(
          _neteaseRatioTextByModId[summary.itemId],
          fieldName: '网易分成',
          defaultValue: defaultNeteaseParse.value,
          invalidValue: 0,
        );
        final errorFields = <String>[];
        if (!internalParse.isValid) {
          errorFields.add('内部分成');
        }
        if (!neteaseParse.isValid) {
          errorFields.add('网易分成');
        }
        final gross = summary.totalDiamonds.toDouble() /
            100 *
            internalParse.value *
            neteaseParse.value;
        final net = gross * (1 - taxParse.value);
        final error =
            errorFields.isEmpty ? null : '参数错误: ${errorFields.join('、')}';
        shareResults[summary.itemId] = _ShareResult(net, error: error);
        shareTotal += net;
        if (error != null) {
          ratioErrors += 1;
        }
      }
    }

    final displaySummaries = _sortedSummaries(_summaries);
    final searchText = _modSearch.trim().toLowerCase();
    final filteredMods = searchText.isEmpty
        ? _mods
        : _mods
            .where((mod) =>
                mod.name.toLowerCase().contains(searchText) ||
                mod.id.toLowerCase().contains(searchText))
            .toList();
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final isWide = !isMobile && MediaQuery.of(context).size.width >= 1000;

    const noPresetValue = '__none__';
    final selectedPresetValue = _presets.any((preset) => preset.id == _selectedPresetId)
        ? _selectedPresetId
        : noPresetValue;

    Widget buildSection(Widget child) {
      return OreStrip(
        tone: OreStripTone.dark,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      );
    }

    final leftWidgets = <Widget>[
      buildSection(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类别', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            SegmentedButton<_Category>(
              segments: const [
                ButtonSegment(value: _Category.pe, label: Text('PE')),
                ButtonSegment(value: _Category.java, label: Text('Java')),
              ],
              selected: {_category},
              showSelectedIcon: false,
              buttonWidth: segmentButtonWidth,
              onSelectionChanged: (value) {
                if (value.isNotEmpty) {
                  setState(() => _category = value.first);
                  _loadMods();
                }
              },
            ),
          ],
        ),
      ),
      buildSection(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '时间范围: ${_rangeLabel()}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickRange,
              icon: const Icon(Icons.date_range),
              label: const Text('选择日期'),
            ),
          ],
        ),
      ),
      buildSection(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('统计范围', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            SegmentedButton<IncomeScope>(
              segments: const [
                ButtonSegment(value: IncomeScope.all, label: Text('全部')),
                ButtonSegment(value: IncomeScope.multiple, label: Text('多个')),
                ButtonSegment(value: IncomeScope.single, label: Text('单个')),
              ],
              selected: {_scope},
              showSelectedIcon: false,
              buttonWidth: segmentButtonWidth,
              onSelectionChanged: (value) {
                if (value.isNotEmpty) {
                  _setScope(value.first);
                }
              },
            ),
            const SizedBox(height: 6),
            OreChoiceDescription(
              items: IncomeScope.values
                  .map((scope) => Text(_scopePreviewFor(scope)))
                  .toList(),
              selectedIndex: IncomeScope.values.indexOf(_scope),
            ),
          ],
        ),
      ),
      buildSection(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('预设', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedPresetValue,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: '选择预设',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: noPresetValue,
                        child: Text('不选择预设'),
                      ),
                      ..._presets.map(
                        (preset) => DropdownMenuItem<String>(
                          value: preset.id,
                          child: Text(preset.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null || value == noPresetValue) {
                        setState(() {
                          _selectedPresetId = null;
                        });
                        return;
                      }
                      _applyPresetById(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '保存为新预设',
                  onPressed: _saveNewPreset,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  tooltip: '更新当前预设',
                  onPressed:
                      _selectedPresetId == null ? null : _updateSelectedPreset,
                  icon: const Icon(Icons.save_outlined),
                ),
                IconButton(
                  tooltip: '管理预设',
                  onPressed: _showPresetManager,
                  icon: const Icon(Icons.manage_accounts_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
      if (_scope != IncomeScope.all)
        OreStrip(
          tone: OreStripTone.dark,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择 Mod',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _modsLoading ? null : () => _loadMods(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新'),
                    ),
                  ],
                ),
                if (_modsLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                if (_modsError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _modsError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '搜索 Mod',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _modSearch = value;
                    });
                  },
                ),
                if (_scope == IncomeScope.multiple) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                    OutlinedButton(
                      onPressed: _mods.isEmpty ? null : _selectAllMods,
                      child: const Text('全选'),
                      width: modSelectButtonWidth,
                    ),
                    OutlinedButton(
                      onPressed: _selectedModIds.isEmpty
                          ? null
                          : _clearModSelection,
                      child: const Text('全不选'),
                      width: modSelectButtonWidth,
                    ),
                    OutlinedButton(
                      onPressed: _mods.isEmpty ? null : _invertModSelection,
                      child: const Text('反选'),
                      width: modSelectButtonWidth,
                    ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: filteredMods.isEmpty
                      ? Center(
                          child: Text(
                            _mods.isEmpty
                                ? '暂无 Mod，请先登录并刷新列表'
                                : '未找到匹配的 Mod',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      : ListView.separated(
                          itemCount: filteredMods.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final mod = filteredMods[index];
                            if (_scope == IncomeScope.multiple) {
                              final selected =
                                  _selectedModIds.contains(mod.id);
                              return CheckboxListTile(
                                value: selected,
                                dense: true,
                                title: Text(mod.name),
                                subtitle: Text(mod.id),
                                onChanged: (value) =>
                                    _toggleMultiSelection(
                                        mod.id, value ?? false),
                              );
                            }
                            return RadioListTile<String>(
                              value: mod.id,
                              groupValue: _singleModId,
                              dense: true,
                              title: Text(mod.name),
                              subtitle: Text(mod.id),
                              onChanged: (value) {
                                if (value != null) {
                                  _selectSingle(value);
                                }
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  _scope == IncomeScope.multiple
                      ? '已选 ${_selectedModIds.length} / ${_mods.length}'
                      : '当前单选: ${_modNameById(_singleModId).isEmpty ? '未选择' : _modNameById(_singleModId)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      OreStrip(
        tone: OreStripTone.dark,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('分成参数', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _defaultInternalRatioController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '默认内部分成',
                        hintText: '默认 1.0',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: defaultInternalParse.isValid
                            ? null
                            : defaultInternalParse.error,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _defaultNeteaseRatioController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '默认网易分成',
                        hintText: '默认 1.0',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: defaultNeteaseParse.isValid
                            ? null
                            : defaultNeteaseParse.error,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _taxRateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '税收比例',
                  hintText: '默认 0.2',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: taxParse.isValid ? null : taxParse.error,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                '分成=钻石/100×网易分成比例×内部分成比例×(1-税收比例)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '未填写的 Mod 比例将使用上述默认值。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      buildSection(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _runQuery,
            icon: const Icon(Icons.search),
            label: Text('开始查询 (${_scopeLabel()})'),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_loading) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text('已处理 $_processed / $_totalMods'),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
    ];

    Widget buildDetailList({
      required bool scrollable,
      required List<IncomeSummary> summaries,
    }) {
      return ListView.separated(
        controller: scrollable ? _rightScrollController : null,
        primary: false,
        shrinkWrap: !scrollable,
        physics: scrollable
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: summaries.length,
        separatorBuilder: (_, __) => const SizedBox.shrink(),
        itemBuilder: (context, index) {
          final summary = summaries[index];
          final internalText = _internalRatioTextByModId[summary.itemId] ?? '';
          final neteaseText = _neteaseRatioTextByModId[summary.itemId] ?? '';
          final internalParse = _parseRate(
            internalText,
            fieldName: '内部分成',
            defaultValue: defaultInternalParse.value,
            invalidValue: 0,
          );
          final neteaseParse = _parseRate(
            neteaseText,
            fieldName: '网易分成',
            defaultValue: defaultNeteaseParse.value,
            invalidValue: 0,
          );
          final share = shareResults[summary.itemId] ?? const _ShareResult(0);
          final internalController = _internalRatioControllers.putIfAbsent(
            summary.itemId,
            () => TextEditingController(text: internalText),
          );
          if (internalController.text != internalText) {
            internalController.text = internalText;
            internalController.selection = TextSelection.fromPosition(
              TextPosition(offset: internalController.text.length),
            );
          }
          final neteaseController = _neteaseRatioControllers.putIfAbsent(
            summary.itemId,
            () => TextEditingController(text: neteaseText),
          );
          if (neteaseController.text != neteaseText) {
            neteaseController.text = neteaseText;
            neteaseController.selection = TextSelection.fromPosition(
              TextPosition(offset: neteaseController.text.length),
            );
          }
          final refundInfo =
              ' · 退款中 ${summary.refundPendingCount} · 已退款 ${summary.refundedCount}'
              '${summary.refundOtherCount > 0 ? ' · 其他退款 ${summary.refundOtherCount}' : ''}';
          return OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          summary.itemName,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text('#${index + 1}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '钻石 ${summary.totalDiamonds} · 绿宝石 ${summary.totalPoints} · 订单 ${summary.orderCount}'
                    '$refundInfo'
                    '${summary.releaseAt == null ? '' : ' · 上架 ${_dateFormat.format(summary.releaseAt!)}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: internalController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: InputDecoration(
                            labelText: '内部分成比例',
                            hintText:
                                '默认 ${_formatNumber(defaultInternalParse.value)}',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            errorText: internalParse.isValid
                                ? null
                                : internalParse.error,
                          ),
                          onChanged: (value) {
                            setState(() {
                              final trimmed = value.trim();
                              if (trimmed.isEmpty) {
                                _internalRatioTextByModId
                                    .remove(summary.itemId);
                              } else {
                                _internalRatioTextByModId[summary.itemId] =
                                    value;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: neteaseController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: InputDecoration(
                            labelText: '网易分成比例',
                            hintText:
                                '默认 ${_formatNumber(defaultNeteaseParse.value)}',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            errorText: neteaseParse.isValid
                                ? null
                                : neteaseParse.error,
                          ),
                          onChanged: (value) {
                            setState(() {
                              final trimmed = value.trim();
                              if (trimmed.isEmpty) {
                                _neteaseRatioTextByModId
                                    .remove(summary.itemId);
                              } else {
                                _neteaseRatioTextByModId[summary.itemId] =
                                    value;
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '分成(税后): ${_formatNumber(share.netValue)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (share.error != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          share.error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    final rightWidgets = <Widget>[
      if (_summaries.isNotEmpty) ...[
        OreStrip(
          tone: OreStripTone.dark,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('汇总', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('总钻石: $_totalDiamonds'),
                Text('分成总计(税后): ${_formatNumber(shareTotal)}'),
                Text('退款中订单: $_refundPendingOrders'),
                Text('已退款订单: $_refundedOrders'),
                if (_refundOtherOrders > 0)
                  Text('其他退款状态: $_refundOtherOrders'),
                if (hasGlobalError)
                  Text(
                    '全局比例存在错误',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                if (ratioErrors > 0)
                  Text(
                    '比例错误: $ratioErrors',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                const SizedBox(height: 4),
                Text('总绿宝石: $_totalPoints'),
                const SizedBox(height: 4),
                Text('钻石定价 Mod: $_diamondPricedMods'),
                Text('绿宝石定价 Mod: $_emeraldPricedMods'),
                if (_otherPricedMods > 0)
                  Text('其他定价 Mod: $_otherPricedMods'),
                const SizedBox(height: 8),
                Text(
                  '提示: 查询时间会转换为 UTC 时间提交到接口。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        buildSection(
          Row(
            children: [
              Expanded(
                child: Text('按 Mod 明细', style: theme.textTheme.titleMedium),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<_SummarySortKey>(
                  value: _summarySortKey,
                  isDense: true,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _summarySortKey = value);
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: _SummarySortKey.diamonds,
                      child: Text('钻石'),
                    ),
                    DropdownMenuItem(
                      value: _SummarySortKey.releaseTime,
                      child: Text('上架时间'),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _summarySortAscending ? '升序' : '降序',
                icon: Icon(
                  _summarySortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                ),
                onPressed: () {
                  setState(() {
                    _summarySortAscending = !_summarySortAscending;
                  });
                },
              ),
            ],
          ),
        ),
        buildDetailList(scrollable: false, summaries: displaySummaries),
      ],
    ];

    if (isWide) {
      return SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: EdgeInsets.zero,
                child: Scrollbar(
                  controller: _leftScrollController,
                  thumbVisibility: true,
                  child: ListView(
                    controller: _leftScrollController,
                    children: leftWidgets,
                  ),
                ),
              ),
            ),
            Container(width: 1, color: theme.dividerColor),
            Expanded(
              flex: 6,
              child: Padding(
                padding: EdgeInsets.zero,
                child: _summaries.isEmpty
                    ? Center(
                        child: Text(
                          '暂无明细，请先查询',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OreStrip(
                            tone: OreStripTone.dark,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '汇总',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('总钻石: $_totalDiamonds'),
                                  Text(
                                    '分成总计(税后): ${_formatNumber(shareTotal)}',
                                  ),
                                  Text('退款中订单: $_refundPendingOrders'),
                                  Text('已退款订单: $_refundedOrders'),
                                  if (_refundOtherOrders > 0)
                                    Text('其他退款状态: $_refundOtherOrders'),
                                  if (hasGlobalError)
                                    Text(
                                      '全局比例存在错误',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  if (ratioErrors > 0)
                                    Text(
                                      '比例错误: $ratioErrors',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text('总绿宝石: $_totalPoints'),
                                  const SizedBox(height: 4),
                                  Text('钻石定价 Mod: $_diamondPricedMods'),
                                  Text('绿宝石定价 Mod: $_emeraldPricedMods'),
                                  if (_otherPricedMods > 0)
                                    Text('其他定价 Mod: $_otherPricedMods'),
                                  const SizedBox(height: 8),
                                  Text(
                                    '提示: 查询时间会转换为 UTC 时间提交到接口。',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          buildSection(
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '按 Mod 明细',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<_SummarySortKey>(
                                    value: _summarySortKey,
                                    isDense: true,
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(
                                          () => _summarySortKey = value,
                                        );
                                      }
                                    },
                                    items: const [
                                      DropdownMenuItem(
                                        value: _SummarySortKey.diamonds,
                                        child: Text('钻石'),
                                      ),
                                      DropdownMenuItem(
                                        value: _SummarySortKey.releaseTime,
                                        child: Text('上架时间'),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip:
                                      _summarySortAscending ? '升序' : '降序',
                                  icon: Icon(
                                    _summarySortAscending
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _summarySortAscending =
                                          !_summarySortAscending;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: _rightScrollController,
                              thumbVisibility: true,
                              child: buildDetailList(
                                scrollable: true,
                                summaries: displaySummaries,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...leftWidgets,
            ...rightWidgets,
          ],
        ),
      ),
    );
  }
}

enum _PriceKind { diamond, emerald, other }

_PriceKind _priceKind(String? raw) {
  if (raw == null || raw.isEmpty) {
    return _PriceKind.other;
  }
  final value = raw.toLowerCase();
  if (value.contains('diamond') || value.contains('钻石')) {
    return _PriceKind.diamond;
  }
  if (value.contains('emerald') ||
      value.contains('绿宝石') ||
      value.contains('point')) {
    return _PriceKind.emerald;
  }
  return _PriceKind.other;
}

enum _Category { pe, java }

String _categoryValue(_Category category) {
  switch (category) {
    case _Category.pe:
      return 'pe';
    case _Category.java:
      return 'java';
  }
}

_Category _categoryFromValue(String? raw) {
  if (raw == null) {
    return _Category.pe;
  }
  final value = raw.toLowerCase();
  if (value == 'java') {
    return _Category.java;
  }
  return _Category.pe;
}

class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key});

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String _status = '请在此页面登录，并进入收益页面后点击“完成登录”。';

  Future<void> _syncCookies() async {
    final cookieMap = await LoginCookieHelper.readCookies();
    if (!mounted) {
      return;
    }

    if (cookieMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未读取到 Cookie，请确认已登录并打开收益页面。')),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildOreAppBar(
        context,
        title: 'WebView 登录',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
          TextButton(onPressed: _syncCookies, child: const Text('完成登录')),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialSettings: InAppWebViewSettings(
                sharedCookiesEnabled: true,
                incognito: false,
                cacheEnabled: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri('https://mcdev.webapp.163.com/'),
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (_, __) {
                setState(() {
                  _loading = true;
                });
              },
              onLoadStop: (_, __) {
                setState(() {
                  _loading = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class McDevApi {
  McDevApi({required this.cookie, required this.category, http.Client? client})
    : _client = client ?? http.Client();

  final String cookie;
  final String category;
  final http.Client _client;
  final Random _random = Random();
  static const int _refundStatusPending = 309;
  static const int _refundStatusDone = 310;

  void _logRefund(String message) {
    if (kDebugMode) {
      debugPrint('[refund] $message');
    }
  }

  void close() {
    _client.close();
  }

  bool _isPublishedStatus(String? status, dynamic weakOffline) {
    final value = status?.toLowerCase().trim() ?? '';
    final isOffline = value.contains('offline') ||
        value.contains('下架') ||
        value.contains('下线') ||
        value.contains('封禁') ||
        value.contains('违规') ||
        value.contains('驳回') ||
        value.contains('拒绝') ||
        value.contains('草稿') ||
        value.contains('待发布') ||
        value.contains('预发布');
    if (isOffline) {
      return false;
    }
    if (value.contains('online') ||
        value.contains('publish') ||
        value.contains('on_shelf') ||
        value.contains('onshelf') ||
        value.contains('已上架') ||
        value.contains('已上线') ||
        value.contains('上架') ||
        value.contains('上线') ||
        value.contains('审核') ||
        value.contains('待审') ||
        value.contains('审查') ||
        value.contains('审批') ||
        value.contains('更新') ||
        value.contains('提交') ||
        value.contains('发布中') ||
        value.contains('上架中') ||
        value.contains('上线中') ||
        value.contains('review') ||
        value.contains('pending') ||
        value.contains('audit') ||
        value.contains('updat')) {
      return true;
    }
    if (weakOffline is bool && weakOffline) {
      return true;
    }
    if (weakOffline is String && weakOffline.toLowerCase() == 'true') {
      return true;
    }
    return false;
  }

  String _formatDateId(DateTime value) {
    return DateFormat('yyyyMMdd').format(value);
  }

  Future<OverviewStats> fetchOverview() async {
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/data_analysis/overview/',
    );
    final payload = await _getJson(uri);
    final status = payload['status']?.toString();
    if (status != null && status != 'ok') {
      final message =
          payload['message']?.toString() ?? payload['msg']?.toString() ?? '';
      throw McDevException('概览接口状态异常: $status $message', uri);
    }
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw McDevException('概览接口返回异常: data 非对象', uri);
    }
    return OverviewStats.fromJson(data);
  }

  Future<List<ModItem>> fetchMods({
    bool onlyPriced = true,
    bool onlyPublished = false,
  }) async {
    const span = 50;
    var start = 0;
    int? count;
    final items = <ModItem>[];

    while (true) {
      final uri = Uri.https(
        'mc-launcher.webapp.163.com',
        '/items/categories/$category/',
        {
          'is_third_party': 'false',
          'start': start.toString(),
          'span': span.toString(),
        },
      );
      final payload = await _getJson(uri);
      final data = payload['data'];
      List<dynamic> list = [];
      if (data is Map<String, dynamic>) {
        final rawList = data['item'];
        if (rawList is List) {
          list = rawList;
        }
        count ??= (data['count'] as num?)?.toInt();
      }

      for (final entry in list) {
        if (entry is Map<String, dynamic>) {
          final id = entry['item_id']?.toString();
          if (id == null || id.isEmpty) {
            continue;
          }
          final priceValue = entry['price'];
          int? price;
          if (priceValue is num) {
            price = priceValue.toInt();
          } else if (priceValue != null) {
            price = int.tryParse(priceValue.toString());
          }
          final status = entry['status']?.toString();
          final weakOffline = entry['weak_offline'];
          final isPublished = _isPublishedStatus(status, weakOffline);
          if (onlyPublished && !isPublished) {
            continue;
          }
          if (onlyPriced && (price == null || price <= 0)) {
            continue;
          }
          final name = entry['item_name']?.toString() ?? id;
          final priceType = entry['price_type']?.toString();
          final releaseAt = _parseModReleaseAt(
            entry['online_time'] ??
                entry['shelf_time'] ??
                entry['publish_time'] ??
                entry['on_shelf_time'] ??
                entry['create_time'] ??
                entry['update_time'],
          );
          items.add(
            ModItem(
              id: id,
              name: name,
              price: price,
              priceType: priceType,
              status: status,
              weakOffline:
                  weakOffline is bool ? weakOffline : weakOffline == 'true',
              releaseAt: releaseAt,
            ),
          );
        }
      }

      if (count != null && items.length >= count) {
        break;
      }
      if (list.length < span) {
        break;
      }
      start += span;
    }

    return items;
  }

  Future<Map<String, int>> fetchSalesTotals({
    required List<String> itemIds,
    required DateTime startDate,
    required DateTime endDate,
    required String platform,
    required String category,
  }) async {
    if (itemIds.isEmpty) {
      return {};
    }
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/data_analysis/day_detail/',
      {
        'platform': platform,
        'category': category,
        'start_date': _formatDateId(startDate),
        'end_date': _formatDateId(endDate),
        'item_list_str': itemIds.join(','),
        'sort': 'dateid',
        'order': 'ASC',
        'start': '0',
        'span': '999999999',
        'is_need_us_rank_data': 'true',
      },
    );

    final payload = await _getJson(uri);
    final status = payload['status']?.toString();
    if (status != null && status != 'ok') {
      final message =
          payload['message']?.toString() ?? payload['msg']?.toString() ?? '';
      throw McDevException('统计接口状态异常: $status $message', uri);
    }
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw McDevException('统计接口返回异常: data 非对象', uri);
    }
    final list = data['data'];
    if (list is! List) {
      return {};
    }

      final salesById = <String, int>{};
      for (final entry in list) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final id = entry['iid']?.toString();
      if (id == null || id.isEmpty) {
        continue;
      }
      final salesRaw = entry['download_num'];
      int? sales;
      if (salesRaw is num) {
        sales = salesRaw.toInt();
      } else if (salesRaw != null) {
        sales = int.tryParse(salesRaw.toString());
      }
      if (sales == null) {
        continue;
      }
      final prev = salesById[id];
      if (prev == null || sales > prev) {
        salesById[id] = sales;
      }
    }
    return salesById;
  }

  Future<DeveloperProfile> fetchDeveloperProfile() async {
    Map<String, dynamic>? authorData;
    Map<String, dynamic>? userData;
    Object? authorError;
    Object? userError;

    try {
      final authorPayload = await _getJson(
        Uri.https('mc-launcher.webapp.163.com', '/users/author_info'),
      );
      final data = authorPayload['data'];
      if (data is Map<String, dynamic>) {
        authorData = data;
      } else if (authorPayload['status']?.toString() == 'ok') {
        authorData = const {};
      }
    } catch (error) {
      authorError = error;
    }

    try {
      final userPayload = await _getJson(
        Uri.https('mc-launcher.webapp.163.com', '/users/me'),
      );
      final data = userPayload['data'];
      if (data is Map<String, dynamic>) {
        userData = data;
      } else if (userPayload['status']?.toString() == 'ok') {
        userData = const {};
      }
    } catch (error) {
      userError = error;
    }

    if (authorData == null && userData == null) {
      if (authorError != null) {
        throw authorError;
      }
      if (userError != null) {
        throw userError;
      }
      throw McDevException(
        '未获取到开发者信息',
        Uri.https('mc-launcher.webapp.163.com', '/users/author_info'),
      );
    }

    final avatarUrl = authorData?['head_img']?.toString();
    final bio = authorData?['content']?.toString();
    final status = authorData?['status']?.toString();
    final updatedAt = authorData?['update_time']?.toString();

    return DeveloperProfile(
      avatarUrl: avatarUrl,
      bio: bio,
      status: status,
      updatedAt: updatedAt,
      authorRaw: authorData,
      userRaw: userData,
    );
  }

  Future<IncomeSummary> fetchIncome(ModItem mod, DateTimeRange range) async {
    final beginUtc = _startOfDay(range.start).toUtc().toIso8601String();
    final endUtc = _endOfDay(range.end).toUtc().toIso8601String();
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/items/categories/$category/${mod.id}/incomes/',
      {'begin_time': beginUtc, 'end_time': endUtc},
    );

    final payload = await _getJson(uri);
    final status = payload['status']?.toString();
    if (status != null && status != 'ok') {
      final message =
          payload['message']?.toString() ?? payload['msg']?.toString() ?? '';
      throw McDevException('收益接口状态异常: $status $message', uri);
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw McDevException('收益接口返回异常: data 非对象', uri);
    }

    final totalDiamonds = (data['total_diamonds'] as num?)?.toInt() ?? 0;
    final totalPoints = (data['total_points'] as num?)?.toInt() ?? 0;
    final count = (data['count'] as num?)?.toInt() ?? 0;
    int refundPending = 0;
    int refunded = 0;
    int refundOther = 0;
    final orders = data['orders'];
    final ordersLength = orders is List ? orders.length : 0;
    if (orders is List) {
      for (final order in orders) {
        if (order is! Map<String, dynamic>) {
          continue;
        }
        final rawStatus = order['refund_status'];
        if (rawStatus == null) {
          continue;
        }
        final status = rawStatus.toString().trim();
        if (status.isEmpty) {
          continue;
        }
        if (status.contains('退款中')) {
          refundPending += 1;
        } else if (status.contains('已退款') || status.contains('退款成功')) {
          refunded += 1;
        } else {
          refundOther += 1;
        }
      }
    }
    _logRefund(
      'mod=${mod.id} name=${mod.name} count=$count orders=$ordersLength '
      'pendingByOrders=$refundPending refundedByOrders=$refunded otherByOrders=$refundOther',
    );
    final needsServerCounts = count > 0 &&
        (ordersLength < count ||
            (ordersLength > 0 && refundPending == 0 && refunded == 0));
    if (needsServerCounts) {
      try {
        final pendingCount = await _fetchRefundCount(
          mod,
          range,
          _refundStatusPending,
        );
        final refundedCount = await _fetchRefundCount(
          mod,
          range,
          _refundStatusDone,
        );
        _logRefund(
          'mod=${mod.id} serverCounts pending=$pendingCount refunded=$refundedCount',
        );
        if (pendingCount + refundedCount <= count) {
          refundPending = pendingCount;
          refunded = refundedCount;
          refundOther = 0;
          _logRefund('mod=${mod.id} useServerCounts');
        } else {
          _logRefund(
            'mod=${mod.id} ignoreServerCounts sum=${pendingCount + refundedCount} count=$count',
          );
        }
      } catch (error) {
        _logRefund('mod=${mod.id} serverCounts failed: $error');
        // Fall back to partial counts from orders list.
      }
    }

    return IncomeSummary(
      itemId: mod.id,
      itemName: mod.name,
      totalDiamonds: totalDiamonds,
      totalPoints: totalPoints,
      orderCount: count,
      refundPendingCount: refundPending,
      refundedCount: refunded,
      refundOtherCount: refundOther,
      priceType: mod.priceType,
      releaseAt: mod.releaseAt,
    );
  }

  Future<int> _fetchRefundCount(
    ModItem mod,
    DateTimeRange range,
    int refundStatus,
  ) async {
    final beginUtc = _startOfDay(range.start).toUtc().toIso8601String();
    final endUtc = _endOfDay(range.end).toUtc().toIso8601String();
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/items/categories/$category/${mod.id}/incomes/',
      {
        'begin_time': beginUtc,
        'end_time': endUtc,
        'refund_status': refundStatus.toString(),
      },
    );
    final payload = await _getJson(uri);
    final status = payload['status']?.toString();
    if (status != null && status != 'ok') {
      final message =
          payload['message']?.toString() ?? payload['msg']?.toString() ?? '';
      throw McDevException('收益接口状态异常: $status $message', uri);
    }
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw McDevException('收益接口返回异常: data 非对象', uri);
    }
    final count = (data['count'] as num?)?.toInt() ?? 0;
    final orders = data['orders'];
    final ordersLength = orders is List ? orders.length : 0;
    _logRefund(
      'mod=${mod.id} refundStatus=$refundStatus count=$count orders=$ordersLength',
    );
    return count;
  }

  Future<IncomeSummary> fetchIncomeWithRetry(
    ModItem mod,
    DateTimeRange range,
  ) async {
    const maxRetries = 2;
    Object? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await fetchIncome(mod, range);
      } catch (error) {
        lastError = error;
        if (attempt >= maxRetries) {
          break;
        }
        final backoffMs = 400 * (1 << attempt) + _random.nextInt(200);
        await Future.delayed(Duration(milliseconds: backoffMs));
      }
    }

    return IncomeSummary(
      itemId: mod.id,
      itemName: mod.name,
      totalDiamonds: 0,
      totalPoints: 0,
      orderCount: 0,
      error: '重试失败: ${lastError.toString()}',
      priceType: mod.priceType,
      releaseAt: mod.releaseAt,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: {
        'Cookie': cookie,
        'Accept': 'application/json',
        'Referer': 'https://mcdev.webapp.163.com/',
      },
    );
    if (response.statusCode != 200) {
      final snippet = response.body.length > 300
          ? response.body.substring(0, 300)
          : response.body;
      throw McDevException('请求失败: ${response.statusCode} $snippet', uri);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      final snippet = response.body.length > 300
          ? response.body.substring(0, 300)
          : response.body;
      throw McDevException('响应不是 JSON: $snippet', uri);
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw McDevException('响应不是 JSON 对象', uri);
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _endOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  }
}

class ModItem {
  ModItem({
    required this.id,
    required this.name,
    this.price,
    this.priceType,
    this.status,
    this.weakOffline,
    this.releaseAt,
  });

  final String id;
  final String name;
  final int? price;
  final String? priceType;
  final String? status;
  final bool? weakOffline;
  final DateTime? releaseAt;
}

class IncomeSummary {
  IncomeSummary({
    required this.itemId,
    required this.itemName,
    required this.totalDiamonds,
    required this.totalPoints,
    required this.orderCount,
    this.refundPendingCount = 0,
    this.refundedCount = 0,
    this.refundOtherCount = 0,
    this.error,
    this.priceType,
    this.releaseAt,
  });

  final String itemId;
  final String itemName;
  final int totalDiamonds;
  final int totalPoints;
  final int orderCount;
  final int refundPendingCount;
  final int refundedCount;
  final int refundOtherCount;
  final String? error;
  final String? priceType;
  final DateTime? releaseAt;
}

class OverviewStats {
  OverviewStats({
    required this.thisMonthDiamond,
    required this.lastMonthDiamond,
    required this.yesterdayDiamond,
    required this.days14AverageDiamond,
    required this.thisMonthDownload,
    required this.lastMonthDownload,
    required this.yesterdayDownload,
    required this.days14AverageDownload,
    required this.dayDiamondDiff,
    required this.dayDownloadDiff,
    required this.monthDiamondDiff,
    required this.monthDownloadDiff,
  });

  final int thisMonthDiamond;
  final int lastMonthDiamond;
  final int yesterdayDiamond;
  final int days14AverageDiamond;
  final int thisMonthDownload;
  final int lastMonthDownload;
  final int yesterdayDownload;
  final int days14AverageDownload;
  final int dayDiamondDiff;
  final int dayDownloadDiff;
  final int monthDiamondDiff;
  final int monthDownloadDiff;

  static int _parseInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  factory OverviewStats.fromJson(Map<String, dynamic> data) {
    return OverviewStats(
      thisMonthDiamond: _parseInt(data['this_month_diamond']),
      lastMonthDiamond: _parseInt(data['last_month_diamond']),
      yesterdayDiamond: _parseInt(data['yesterday_diamond']),
      days14AverageDiamond: _parseInt(data['days_14_average_diamond']),
      thisMonthDownload: _parseInt(data['this_month_download']),
      lastMonthDownload: _parseInt(data['last_month_download']),
      yesterdayDownload: _parseInt(data['yesterday_download']),
      days14AverageDownload: _parseInt(data['days_14_average_download']),
      dayDiamondDiff: _parseInt(data['day_diamond_diff']),
      dayDownloadDiff: _parseInt(data['day_download_diff']),
      monthDiamondDiff: _parseInt(data['month_diamond_diff']),
      monthDownloadDiff: _parseInt(data['month_download_diff']),
    );
  }
}

class DeveloperProfile {
  DeveloperProfile({
    this.avatarUrl,
    this.bio,
    this.status,
    this.updatedAt,
    this.authorRaw,
    this.userRaw,
  });

  final String? avatarUrl;
  final String? bio;
  final String? status;
  final String? updatedAt;
  final Map<String, dynamic>? authorRaw;
  final Map<String, dynamic>? userRaw;
}

class McDevException implements Exception {
  McDevException(this.message, this.uri);

  final String message;
  final Uri uri;

  @override
  String toString() => '$message (${uri.toString()})';
}
