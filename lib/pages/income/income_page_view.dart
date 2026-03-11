part of mcdev_income_app;

extension _IncomePageView on _IncomePageState {
  Widget buildIncomePageView(BuildContext context) {
    final theme = Theme.of(context);
    final ore = OreTheme.of(context);
    final segmentButtonWidth = OreTokens.controlHeightMd * 2.5;
    final modSelectButtonWidth = OreTokens.controlHeightMd * 3;
    final shareFieldRightPadding =
        ore.borderWidth * OreTokens.scrollbarWidthUnits + OreTokens.gapSm;
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
      defaultValue: 0.16,
      invalidValue: 0.16,
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
        final gross =
            summary.totalDiamonds.toDouble() /
            100 *
            internalParse.value *
            neteaseParse.value;
        final net = gross * (1 - taxParse.value);
        final error = errorFields.isEmpty
            ? null
            : '参数错误: ${errorFields.join('、')}';
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
              .where(
                (mod) =>
                    mod.name.toLowerCase().contains(searchText) ||
                    mod.id.toLowerCase().contains(searchText),
              )
              .toList();
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final isWide = !isMobile && MediaQuery.of(context).size.width >= 1000;

    const noPresetValue = '__none__';
    final selectedPresetValue =
        _presets.any((preset) => preset.id == _selectedPresetId)
        ? _selectedPresetId
        : noPresetValue;

    Widget buildSection(Widget child) {
      return OreStrip(
        tone: OreStripTone.dark,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
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
            Text('时间范围: ${_rangeLabel()}', style: theme.textTheme.bodyMedium),
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
                  onPressed: _selectedPresetId == null
                      ? null
                      : _updateSelectedPreset,
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
                      child: Text('选择 Mod', style: theme.textTheme.titleMedium),
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
                            _mods.isEmpty ? '暂无 Mod，请先登录并刷新列表' : '未找到匹配的 Mod',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      : ListView.separated(
                          itemCount: filteredMods.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final mod = filteredMods[index];
                            if (_scope == IncomeScope.multiple) {
                              final selected = _selectedModIds.contains(mod.id);
                              return CheckboxListTile(
                                value: selected,
                                dense: true,
                                title: Text(mod.name),
                                subtitle: Text(mod.id),
                                onChanged: (value) => _toggleMultiSelection(
                                  mod.id,
                                  value ?? false,
                                ),
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
              Padding(
                padding: EdgeInsets.only(right: shareFieldRightPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _defaultInternalRatioController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
              ),
              const SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.only(right: shareFieldRightPadding),
                child: TextField(
                  controller: _taxRateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '税收比例',
                    hintText: '默认 0.16',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: taxParse.isValid ? null : taxParse.error,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '分成=钻石/100×网易分成比例×内部分成比例×(1-税收比例)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text('未填写的 Mod 比例将使用上述默认值。', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      buildSection(
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _runQuery,
                icon: const Icon(Icons.search),
                label: Text('开始查询 (${_scopeLabel()})'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _loading || _exportingCsv || _summaries.isEmpty
                  ? null
                  : _exportSummariesCsv,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('导出CSV'),
            ),
          ],
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
                    '钻石 ${summary.totalDiamonds} · 绿宝石 ${summary.totalPoints} · 订单 ${summary.orderCount} · 新增下载 ${summary.downloadCount}'
                    '$refundInfo'
                    '${summary.releaseAt == null ? '' : ' · 上架 ${_dateFormat.format(summary.releaseAt!)}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (summary.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '收益数据异常: ${summary.error}',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: internalController,
                          keyboardType: const TextInputType.numberWithOptions(
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
                                _internalRatioTextByModId.remove(
                                  summary.itemId,
                                );
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
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: shareFieldRightPadding,
                          ),
                          child: TextField(
                            controller: neteaseController,
                            keyboardType: const TextInputType.numberWithOptions(
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
                                  _neteaseRatioTextByModId.remove(
                                    summary.itemId,
                                  );
                                } else {
                                  _neteaseRatioTextByModId[summary.itemId] =
                                      value;
                                }
                              });
                            },
                          ),
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
                Text('新增下载量: $_totalDownloads'),
                if (_downloadError != null)
                  Text(
                    '下载量接口异常: $_downloadError',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                Text('分成总计(税后): ${_formatNumber(shareTotal)}'),
                Text('退款中订单: $_refundPendingOrders'),
                Text('已退款订单: $_refundedOrders'),
                if (_refundOtherOrders > 0) Text('其他退款状态: $_refundOtherOrders'),
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
                if (_otherPricedMods > 0) Text('其他定价 Mod: $_otherPricedMods'),
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
              IconButton(
                tooltip: '导出CSV',
                onPressed: _loading || _exportingCsv
                    ? null
                    : _exportSummariesCsv,
                icon: const Icon(Icons.download_outlined),
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
                      value: _SummarySortKey.downloads,
                      child: Text('新增下载'),
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
            Container(
              width: OreTheme.of(context).borderWidth,
              color: OreTheme.of(context).colors.border,
            ),
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
                                  Text('新增下载量: $_totalDownloads'),
                                  if (_downloadError != null)
                                    Text(
                                      '下载量接口异常: $_downloadError',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
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
                                IconButton(
                                  tooltip: '导出CSV',
                                  onPressed: _loading || _exportingCsv
                                      ? null
                                      : _exportSummariesCsv,
                                  icon: const Icon(Icons.download_outlined),
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
                                        value: _SummarySortKey.downloads,
                                        child: Text('新增下载'),
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
          children: [...leftWidgets, ...rightWidgets],
        ),
      ),
    );
  }
}
