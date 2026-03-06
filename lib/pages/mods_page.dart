part of mcdev_income_app;

class ModsPage extends StatefulWidget {
  const ModsPage({super.key});

  @override
  State<ModsPage> createState() => _ModsPageState();
}

class _ModsPageState extends State<ModsPage> {
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _numberFormat = NumberFormat.decimalPattern();
  final ScrollController _modsScrollController = ScrollController();
  _Category _category = _Category.pe;
  bool _loading = false;
  String? _error;
  List<ModItem> _mods = [];
  String _search = '';
  bool _salesLoading = false;
  String? _salesError;
  Map<String, int> _salesById = {};
  DateTime? _salesUpdatedAt;

  double _buttonWidthWithIcon(BuildContext context, String label) {
    final ore = OreTheme.of(context);
    final style = ore.typography.label;
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final padding = ore.borderWidth * OreTokens.buttonPadMdHUnits;
    final iconSize = 16.0;
    final gap = OreTokens.gapXs;
    final extra = OreTokens.gapSm * 2;
    return padding * 2 + iconSize + gap + painter.width + extra;
  }

  @override
  void initState() {
    super.initState();
    _loadMods();
  }

  @override
  void dispose() {
    _modsScrollController.dispose();
    super.dispose();
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
    final refreshButtonWidth = _buttonWidthWithIcon(context, '刷新');
    final actionButtonWidth =
        max(segmentButtonWidth, refreshButtonWidth);
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
                    width: actionButtonWidth,
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
                            controller: _modsScrollController,
                            child: GridView.builder(
                              controller: _modsScrollController,
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
