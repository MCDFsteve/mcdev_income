part of '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.apiFactory, this.csvSaver});
  final McDevApi Function()? apiFactory;
  final Future<String?> Function({
    required String fileName,
    required String content,
  })?
  csvSaver;

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

  String _rankType = 'pe_hot';
  String _kind = 'mods';
  bool? _canAdvancedRanks;
  bool _rankLoading = true;
  String? _rankError;
  LeaderboardPage? _ranking;
  bool _exportingRanks = false;
  String? _exportProgress;
  int _rankStart = 0, _rankRequest = 0;
  final _rankHeader = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadOverview();
    _loadRanking();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<McDevApi> _openApi() async {
    if (widget.apiFactory != null) return widget.apiFactory!();
    final cookie = await LoginCookieHelper.buildCookieHeader();
    if (cookie.isEmpty) throw StateError('请先到“设置”里登录。');
    return McDevApi(cookie: cookie, category: 'pe');
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    McDevApi? api;
    try {
      api = await _openApi();
      final stats = await api.fetchOverview();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _updatedAt = DateTime.now();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      api?.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRanking() async {
    final request = ++_rankRequest;
    setState(() {
      _rankLoading = true;
      _rankError = null;
    });
    McDevApi? api;
    try {
      api = await _openApi();
      if (_canAdvancedRanks == null) {
        final profile = await api.fetchDeveloperProfile();
        if (!mounted || request != _rankRequest) return;
        _canAdvancedRanks = profile.userRaw?['can_us_rank'] == true;
        if (_canAdvancedRanks == false &&
            ['pe_hot', 'hot_search'].contains(_rankType)) {
          setState(() {
            _rankType = 'pe_download';
            _rankStart = 0;
          });
        }
      }
      final result = await api.fetchLeaderboard(
        type: _rankType,
        kind: _kind,
        start: _rankStart,
      );
      if (mounted && request == _rankRequest) setState(() => _ranking = result);
    } catch (error) {
      if (mounted && request == _rankRequest) {
        setState(() => _rankError = error.toString());
      }
    } finally {
      api?.close();
      if (mounted && request == _rankRequest) {
        setState(() => _rankLoading = false);
      }
    }
  }

  void _selectRank({String? type, String? kind, int start = 0}) {
    setState(() {
      _rankType = type ?? _rankType;
      _kind = kind ?? _kind;
      _rankStart = start;
      _ranking = null;
    });
    _loadRanking();
  }

  Future<void> _exportRanks() async {
    final selectedTypes = leaderboardTypes.keys
        .where(
          (type) =>
              _canAdvancedRanks != false ||
              !['pe_hot', 'hot_search'].contains(type),
        )
        .toSet();
    final selectedKinds = leaderboardKinds.keys.toSet();
    final selection =
        await showOreDialog<({Set<String> types, Set<String> kinds})>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => OreAlertDialog(
              title: const Text('导出排行榜数据'),
              content: SizedBox(
                width: min(380, MediaQuery.sizeOf(ctx).width - 100),
                height: min(450, MediaQuery.sizeOf(ctx).height * .55),
                child: ListView(
                  children: [
                    const Text('选择榜单'),
                    for (final entry in leaderboardTypes.entries)
                      if (_canAdvancedRanks != false ||
                          !['pe_hot', 'hot_search'].contains(entry.key))
                        OreCheckboxListTile(
                          key: ValueKey('export-rank-type-${entry.key}'),
                          value: selectedTypes.contains(entry.key),
                          dense: true,
                          title: Text(entry.value),
                          onChanged: (value) => update(() {
                            value == true
                                ? selectedTypes.add(entry.key)
                                : selectedTypes.remove(entry.key);
                          }),
                        ),
                    const SizedBox(height: 8),
                    const Text('选择资源类别（热搜榜不区分类别）'),
                    for (final entry in leaderboardKinds.entries)
                      OreCheckboxListTile(
                        key: ValueKey('export-rank-kind-${entry.key}'),
                        value: selectedKinds.contains(entry.key),
                        dense: true,
                        title: Text(entry.value),
                        onChanged: (value) => update(() {
                          value == true
                              ? selectedKinds.add(entry.key)
                              : selectedKinds.remove(entry.key);
                        }),
                      ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed:
                      selectedTypes.isEmpty ||
                          (selectedKinds.isEmpty &&
                              selectedTypes.any((type) => type != 'hot_search'))
                      ? null
                      : () => Navigator.pop(ctx, (
                          types: {...selectedTypes},
                          kinds: {...selectedKinds},
                        )),
                  child: const Text('导出CSV'),
                ),
              ],
            ),
          ),
        );
    if (!mounted || selection == null) return;

    setState(() {
      _exportingRanks = true;
      _exportProgress = '正在获取排行榜…';
    });
    McDevApi? api;
    try {
      api = await _openApi();
      final rows = await fetchLeaderboardExportRows(
        api: api,
        types: selection.types,
        kinds: selection.kinds,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() => _exportProgress = '正在获取排行榜 $completed/$total');
          }
        },
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        showOreToast(context, const Text('所选排行榜暂无数据'));
        return;
      }
      setState(() => _exportProgress = '正在保存CSV…');
      final fileName =
          'leaderboards_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      final path = await (widget.csvSaver ?? csv_file_saver.saveCsvToFile)(
        fileName: fileName,
        content: buildLeaderboardCsv(rows),
      );
      if (!mounted) return;
      showOreToast(
        context,
        Text(path == null ? '已取消保存' : '已导出 ${rows.length} 条排行榜数据：$path'),
        duration: const Duration(seconds: 6),
      );
    } catch (error) {
      if (mounted) {
        showOreToast(
          context,
          Text('导出排行榜失败：$error'),
          duration: const Duration(seconds: 6),
        );
      }
    } finally {
      api?.close();
      if (mounted) {
        setState(() {
          _exportingRanks = false;
          _exportProgress = null;
        });
      }
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
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pixelAsset(iconAsset, targetHeight: targetHeight),
          const SizedBox(width: 6),
          text,
        ],
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
    final diffText = diff == 0 ? '0' : '${isUp ? '+' : ''}${_formatInt(diff)}';
    final diffColor = diff == 0
        ? (theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurface)
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

  Widget _rankingControls() => OreStrip(
    key: _rankHeader,
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
                  '排行榜',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OreButton(
                key: const ValueKey('export-rank-csv'),
                size: OreButtonSize.sm,
                onPressed: _rankLoading || _exportingRanks
                    ? null
                    : _exportRanks,
                child: Text(_exportProgress ?? '导出CSV'),
              ),
              OreIconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新排行榜',
                onPressed: _rankLoading ? null : _loadRanking,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in leaderboardTypes.entries)
                if (_canAdvancedRanks != false ||
                    !['pe_hot', 'hot_search'].contains(entry.key))
                  OreButton(
                    key: ValueKey('rank-type-${entry.key}'),
                    size: OreButtonSize.sm,
                    variant: _rankType == entry.key
                        ? OreButtonVariant.primary
                        : OreButtonVariant.secondary,
                    onPressed: () => _selectRank(type: entry.key),
                    child: Text(entry.value),
                  ),
            ],
          ),
          if (_rankType != 'hot_search') ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in leaderboardKinds.entries)
                  OreButton(
                    key: ValueKey('rank-kind-${entry.key}'),
                    size: OreButtonSize.sm,
                    variant: _kind == entry.key
                        ? OreButtonVariant.primary
                        : OreButtonVariant.secondary,
                    onPressed: () => _selectRank(kind: entry.key),
                    child: Text(entry.value),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _rankTile(LeaderboardEntry entry) {
    final colors = OreTheme.of(context).colors;
    final change = entry.change;
    final movement = entry.isNew
        ? '新上榜'
        : change == null || change == 0
        ? ''
        : '${change < 0 ? '↑' : '↓'} ${change.abs()}';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: .3)),
        ),
      ),
      child: Semantics(
        button: entry.hasResourceDetails,
        hint: entry.hasResourceDetails ? '查看资源详情' : null,
        child: OreListTile(
          key: ValueKey('rank-entry-${entry.type}-${entry.rank}'),
          onTap: entry.hasResourceDetails
              ? () => showOreDialog<void>(
                  context: context,
                  builder: (_) => LeaderboardResourceDialog(
                    entry: entry,
                    apiFactory: widget.apiFactory,
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          title: Row(
            children: [
              SizedBox(
                width: 38,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${entry.rank}',
                    maxLines: 1,
                    softWrap: false,
                    style: _numberStyle(Theme.of(context).textTheme.titleLarge)
                        .copyWith(
                          color: entry.rank <= 3
                              ? colors.success
                              : colors.textMuted,
                        ),
                  ),
                ),
              ),
              if (entry.icon?.isNotEmpty == true) ...[
                Image.network(
                  entry.icon!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(child: OreLoadingIndicator(size: 20)),
                        ),
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.extension_outlined),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.author.isNotEmpty || entry.metric.isNotEmpty)
                      Text(
                        [
                          entry.author,
                          entry.metric,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (movement.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  movement,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: change != null && change > 0
                        ? colors.danger
                        : colors.success,
                  ),
                ),
              ],
              if (entry.hasResourceDetails) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCards(OverviewStats stats, double width) {
    final columns = width >= 1200
        ? 4
        : width >= 650
        ? 2
        : 1;
    final tiles = [
      _buildPairCard(
        context,
        title: '本月钻石收益',
        mainValue: _formatInt(stats.thisMonthDiamond),
        subtitleLabel: '上月整月',
        subtitleValue: _formatInt(stats.lastMonthDiamond),
        diff: stats.thisMonthDiamond - stats.lastMonthDiamond,
        iconAsset: _diamondAsset,
      ),
      _buildPairCard(
        context,
        title: '昨日钻石收益',
        mainValue: _formatInt(stats.yesterdayDiamond),
        subtitleLabel: '14天日均',
        subtitleValue: _formatInt(stats.days14AverageDiamond),
        diff: stats.yesterdayDiamond - stats.days14AverageDiamond,
        iconAsset: _diamondAsset,
      ),
      _buildPairCard(
        context,
        title: '本月资源下载数',
        mainValue: _formatInt(stats.thisMonthDownload),
        subtitleLabel: '上月整月',
        subtitleValue: _formatInt(stats.lastMonthDownload),
        diff: stats.thisMonthDownload - stats.lastMonthDownload,
        iconAsset: _downloadAsset,
      ),
      _buildPairCard(
        context,
        title: '昨日资源下载数',
        mainValue: _formatInt(stats.yesterdayDownload),
        subtitleLabel: '14天日均',
        subtitleValue: _formatInt(stats.days14AverageDownload),
        diff: stats.yesterdayDownload - stats.days14AverageDownload,
        iconAsset: _downloadAsset,
      ),
    ];
    return Wrap(
      children: [
        for (final tile in tiles) SizedBox(width: width / columns, child: tile),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context), ranking = _ranking, stats = _stats;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final rankColumns = constraints.maxWidth >= 1400 * scale
            ? 3
            : constraints.maxWidth >= 850 * scale
            ? 2
            : 1;
        return Scrollbar(
          controller: _scroll,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: OreStrip(
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
                              Text(
                                _updatedAt == null
                                    ? '尚未更新'
                                    : '最近更新 ${_dateTimeFormat.format(_updatedAt!)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        OreIconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '刷新首页',
                          onPressed: _loading || _rankLoading
                              ? null
                              : () {
                                  _canAdvancedRanks = null;
                                  _loadOverview();
                                  _loadRanking();
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _loading && stats == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: OreLoadingIndicator()),
                      )
                    : _error != null
                    ? _buildError(theme)
                    : stats == null
                    ? const SizedBox.shrink()
                    : _statCards(stats, constraints.maxWidth),
              ),
              SliverToBoxAdapter(child: _rankingControls()),
              if (_rankLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: OreLoadingIndicator()),
                  ),
                )
              else if (_rankError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          _rankError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        const SizedBox(height: 12),
                        OreButton(
                          onPressed: _loadRanking,
                          child: const Text('重试排行榜'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (ranking == null || ranking.items.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('暂无排行数据')),
                  ),
                )
              else ...[
                SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _rankTile(ranking.items[index]),
                    childCount: ranking.items.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: rankColumns,
                    mainAxisExtent: 94 * scale,
                    crossAxisSpacing: 12,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_rankStart + 1}–${_rankStart + ranking.items.length} / ${ranking.total}',
                        ),
                        OreButton(
                          size: OreButtonSize.sm,
                          onPressed: _rankStart > 0
                              ? () => _rankPage(-50)
                              : null,
                          child: const Text('上一页'),
                        ),
                        OreButton(
                          size: OreButtonSize.sm,
                          onPressed:
                              _rankStart + ranking.items.length < ranking.total
                              ? () => _rankPage(50)
                              : null,
                          child: const Text('下一页'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  void _rankPage(int delta) {
    _selectRank(start: max(0, _rankStart + delta));
    final context = _rankHeader.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
      );
    }
  }
}
