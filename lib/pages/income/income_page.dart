part of mcdev_income_app;

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
  String? _downloadError;

  int _totalDiamonds = 0;
  int _totalPoints = 0;
  int _totalDownloads = 0;
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
  final TextEditingController _taxRateController = TextEditingController(
    text: '0.2',
  );
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
          presets.add(
            IncomePreset.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无预设')));
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
                            _presets = _presets
                                .where((p) => p.id != preset.id)
                                .toList();
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
      _defaultInternalRatioController.text = _formatRatio(
        preset.defaultInternalRatio,
      );
      _defaultNeteaseRatioController.text = _formatRatio(
        preset.defaultNeteaseRatio,
      );
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
      final mods = await api.fetchMods(onlyPriced: false, onlyPublished: false);
      if (!mounted) {
        return mods;
      }
      final availableIds = mods.map((mod) => mod.id).toSet();
      setState(() {
        _mods = mods;
        _modsCategory = _category;
        _modsLoading = false;
        _modsError = mods.isEmpty ? '未获取到任何 Mod，请确认账号权限与类别。' : null;
        _selectedModIds = _selectedModIds.where(availableIds.contains).toSet();
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

  String _summarySortLabel() {
    switch (_summarySortKey) {
      case _SummarySortKey.diamonds:
        return '钻石';
      case _SummarySortKey.downloads:
        return '新增下载';
      case _SummarySortKey.releaseTime:
        return '上架时间';
    }
  }

  String _csvEscape(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final escaped = normalized.replaceAll('"', '""');
    final needsQuote =
        escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n');
    if (needsQuote) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _buildIncomeCsv() {
    final exportTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final range = _range;
    final rangeText = range == null
        ? '未选择'
        : '${_dateFormat.format(range.start)} ~ ${_dateFormat.format(range.end)}';
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
    final summaries = _sortedSummaries(_summaries);

    final rows = <List<String>>[
      ['导出时间', exportTime],
      ['类别', _categoryLabel(_category)],
      ['时间范围', rangeText],
      ['统计范围', _scopeLabel()],
      ['排序字段', _summarySortLabel()],
      ['排序方向', _summarySortAscending ? '升序' : '降序'],
      ['默认内部分成', _formatNumber(defaultInternalParse.value)],
      ['默认网易分成', _formatNumber(defaultNeteaseParse.value)],
      ['税率', _formatNumber(taxParse.value)],
      [],
      [
        '序号',
        'ModID',
        'Mod名称',
        '钻石',
        '绿宝石',
        '订单数',
        '新增下载量',
        '退款中',
        '已退款',
        '其他退款',
        '上架日期',
        '内部分成输入',
        '内部分成生效值',
        '内部分成来源',
        '内部分成错误',
        '网易分成输入',
        '网易分成生效值',
        '网易分成来源',
        '网易分成错误',
        '税率',
        '税前分成',
        '税后分成',
        '分成计算错误',
        '收益接口错误',
      ],
    ];

    double shareTotal = 0;
    for (var i = 0; i < summaries.length; i += 1) {
      final summary = summaries[i];
      final internalRaw =
          _internalRatioTextByModId[summary.itemId]?.trim() ?? '';
      final neteaseRaw = _neteaseRatioTextByModId[summary.itemId]?.trim() ?? '';
      final internalParse = _parseRate(
        internalRaw,
        fieldName: '内部分成',
        defaultValue: defaultInternalParse.value,
        invalidValue: 0,
      );
      final neteaseParse = _parseRate(
        neteaseRaw,
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
      final gross =
          summary.totalDiamonds.toDouble() /
          100 *
          internalParse.value *
          neteaseParse.value;
      final net = gross * (1 - taxParse.value);
      shareTotal += net;
      final calcError = errorFields.isEmpty
          ? ''
          : '参数错误: ${errorFields.join('、')}';

      rows.add([
        '${i + 1}',
        summary.itemId,
        summary.itemName,
        summary.totalDiamonds.toString(),
        summary.totalPoints.toString(),
        summary.orderCount.toString(),
        summary.downloadCount.toString(),
        summary.refundPendingCount.toString(),
        summary.refundedCount.toString(),
        summary.refundOtherCount.toString(),
        summary.releaseAt == null ? '' : _dateFormat.format(summary.releaseAt!),
        internalRaw,
        _formatNumber(internalParse.value),
        internalParse.isDefault ? '默认' : '自定义',
        internalParse.error ?? '',
        neteaseRaw,
        _formatNumber(neteaseParse.value),
        neteaseParse.isDefault ? '默认' : '自定义',
        neteaseParse.error ?? '',
        _formatNumber(taxParse.value),
        _formatNumber(gross),
        _formatNumber(net),
        calcError,
        summary.error ?? '',
      ]);
    }

    rows.add([]);
    rows.add([
      '汇总',
      '',
      '',
      _totalDiamonds.toString(),
      _totalPoints.toString(),
      '',
      _totalDownloads.toString(),
      _refundPendingOrders.toString(),
      _refundedOrders.toString(),
      _refundOtherOrders.toString(),
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      _formatNumber(taxParse.value),
      '',
      _formatNumber(shareTotal),
      '',
      _downloadError ?? '',
    ]);

    final buffer = StringBuffer('\ufeff');
    for (final row in rows) {
      if (row.isEmpty) {
        buffer.writeln();
        continue;
      }
      buffer.writeln(row.map(_csvEscape).join(','));
    }
    return buffer.toString();
  }

  Future<void> _exportSummariesCsv() async {
    if (_summaries.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无可导出的查询结果')));
      return;
    }

    final csv = _buildIncomeCsv();
    final fileName =
        'income_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    String? savedPath;
    String? saveError;

    try {
      savedPath = await csv_file_saver.saveCsvToFile(
        fileName: fileName,
        content: csv,
      );
    } catch (error) {
      saveError = error.toString();
    }

    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) {
      return;
    }

    final tips = <String>[];
    if (savedPath != null && savedPath.isNotEmpty) {
      tips.add('CSV已导出: $savedPath');
    } else {
      tips.add('未写入本地文件');
    }
    tips.add('CSV已复制到剪贴板');
    if (saveError != null && saveError!.isNotEmpty) {
      tips.add('保存失败: $saveError');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tips.join('；')),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String _analysisCategory(_Category category) {
    return category == _Category.pe ? 'pe' : 'pc';
  }

  Future<Map<String, int>> _fetchDownloadsInBatches({
    required McDevApi api,
    required List<String> itemIds,
    required DateTime startDate,
    required DateTime endDate,
    required String analysisCategory,
  }) async {
    if (itemIds.isEmpty) {
      return {};
    }
    const batchSize = 10;
    final result = <String, int>{};
    for (var i = 0; i < itemIds.length; i += batchSize) {
      if (!mounted) {
        return result;
      }
      final batch = itemIds.sublist(i, min(i + batchSize, itemIds.length));
      final batchResult = await api.fetchSalesIncrements(
        itemIds: batch,
        startDate: startDate,
        endDate: endDate,
        platform: analysisCategory,
        category: analysisCategory,
      );
      result.addAll(batchResult);
    }
    return result;
  }

  List<IncomeSummary> _sortedSummaries(List<IncomeSummary> input) {
    final list = List<IncomeSummary>.from(input);
    list.sort((a, b) {
      switch (_summarySortKey) {
        case _SummarySortKey.diamonds:
          final cmp = a.totalDiamonds.compareTo(b.totalDiamonds);
          return _summarySortAscending ? cmp : -cmp;
        case _SummarySortKey.downloads:
          final cmp = a.downloadCount.compareTo(b.downloadCount);
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
        targetMods = mods
            .where((mod) => _selectedModIds.contains(mod.id))
            .toList();
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
      _downloadError = null;
      _summaries = [];
      _totalDiamonds = 0;
      _totalPoints = 0;
      _totalDownloads = 0;
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
      int downloads = 0;
      int diamondPriced = 0;
      int emeraldPriced = 0;
      int otherPriced = 0;
      int refundPending = 0;
      int refunded = 0;
      int refundOther = 0;
      int processed = 0;
      final modById = {for (final mod in targetMods) mod.id: mod};
      final analysisCategory = _analysisCategory(_category);
      var downloadById = <String, int>{};
      String? downloadErrorText;
      try {
        downloadById = await _fetchDownloadsInBatches(
          api: api,
          itemIds: targetMods.map((mod) => mod.id).toList(),
          startDate: range.start,
          endDate: range.end,
          analysisCategory: analysisCategory,
        );
      } catch (error) {
        downloadErrorText = error.toString();
        if (kDebugMode) {
          debugPrint('fetch downloads failed: $error');
        }
      }

      for (var i = 0; i < targetMods.length; i += batchSize) {
        final batch = targetMods.sublist(
          i,
          min(i + batchSize, targetMods.length),
        );
        final results = await Future.wait(
          batch.map((mod) => api.fetchIncomeWithRetry(mod, range)),
        );
        if (!mounted) {
          return;
        }
        processed += results.length;
        for (final rawSummary in results) {
          final summary = rawSummary.copyWith(
            downloadCount: downloadById[rawSummary.itemId] ?? 0,
          );
          final includeInDetails =
              summary.error == null || downloadById.containsKey(summary.itemId);
          if (includeInDetails) {
            summaries.add(summary);
          }
          downloads += summary.downloadCount;

          if (summary.error == null) {
            diamonds += summary.totalDiamonds;
            points += summary.totalPoints;
            refundPending += summary.refundPendingCount;
            refunded += summary.refundedCount;
            refundOther += summary.refundOtherCount;
            final sourceMod = modById[summary.itemId];
            if ((sourceMod?.price ?? 0) > 0) {
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
        }

        setState(() {
          _processed = processed;
          _summaries = List.of(summaries);
          _totalDiamonds = diamonds;
          _totalPoints = points;
          _totalDownloads = downloads;
          _downloadError = downloadErrorText;
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
    return buildIncomePageView(context);
  }
}
