part of mcdev_income_app;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _numberFontFamily = 'Minecraft Seven v4';
  static const _numberFontPackage = 'oreui_flutter';
  static const _diamondAsset = 'assets/diamond.png';
  static const _downloadAsset = 'assets/free_download.png';

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

  TextStyle _numberStyle(TextStyle? base) {
    final resolved = base ?? const TextStyle();
    return resolved.copyWith(
      fontFamily: _numberFontFamily,
      package: _numberFontPackage,
    );
  }

  Size _assetBaseSize(String asset) {
    switch (asset) {
      case _diamondAsset:
        return const Size(16, 16);
      case _downloadAsset:
        return const Size(8, 10);
    }
    return const Size(16, 16);
  }

  Widget _pixelAsset(String asset, {required double targetHeight}) {
    final base = _assetBaseSize(asset);
    final baseScale = max(1.0, targetHeight / base.height);
    final multiplier = asset == _diamondAsset ? 1.25 : 1.0;
    final scale = baseScale * multiplier;
    final width = (base.width * scale).roundToDouble();
    final height = (base.height * scale).roundToDouble();
    return Image.asset(
      asset,
      width: width,
      height: height,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      fit: BoxFit.fill,
    );
  }

  Widget _buildStatValue({
    required String value,
    required TextStyle? style,
    String? iconAsset,
  }) {
    final text = Text(value, style: _numberStyle(style));
    if (iconAsset == null) {
      return text;
    }
    final targetHeight = style?.fontSize ?? 18;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pixelAsset(iconAsset, targetHeight: targetHeight),
        const SizedBox(width: 6),
        text,
      ],
    );
  }

  Widget _buildSimpleCard(
    BuildContext context, {
    required String title,
    required String value,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return OreCard(
      padding: const EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: _numberStyle(theme.textTheme.titleLarge)),
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
    String? iconAsset,
  }) {
    final theme = Theme.of(context);
    final isUp = diff > 0;
    final diffText =
        diff == 0 ? '0' : '${isUp ? '+' : ''}${_formatInt(diff)}';
    final diffColor = diff == 0
        ? (theme.textTheme.bodySmall?.color ??
            theme.colorScheme.onSurface)
        : (isUp ? Colors.red : Colors.green);
    return OreCard(
      padding: const EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            _buildStatValue(
              value: mainValue,
              style: theme.textTheme.titleLarge,
              iconAsset: iconAsset,
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodySmall,
                children: [
                  TextSpan(text: '$subtitleLabel '),
                  TextSpan(
                    text: subtitleValue,
                    style: _numberStyle(theme.textTheme.bodySmall),
                  ),
                  TextSpan(text: '  较$subtitleLabel '),
                  TextSpan(
                    text: diffText,
                    style: _numberStyle(
                      theme.textTheme.bodySmall?.copyWith(
                        color: diffColor,
                        fontWeight: FontWeight.w600,
                      ),
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
                                subtitleLabel: '上月整月',
                                subtitleValue:
                                    _formatInt(stats.lastMonthDiamond),
                                diff: stats.thisMonthDiamond -
                                    stats.lastMonthDiamond,
                                iconAsset: _diamondAsset,
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
                                iconAsset: _diamondAsset,
                              ),
                              _buildPairCard(
                                context,
                                title: '本月资源下载数',
                                mainValue: _formatInt(stats.thisMonthDownload),
                                subtitleLabel: '上月整月',
                                subtitleValue:
                                    _formatInt(stats.lastMonthDownload),
                                diff: stats.thisMonthDownload -
                                    stats.lastMonthDownload,
                                iconAsset: _downloadAsset,
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
                                iconAsset: _downloadAsset,
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
