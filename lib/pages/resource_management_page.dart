part of mcdev_income_app;

class ResourceManagementPage extends StatefulWidget {
  const ResourceManagementPage({super.key});

  @override
  State<ResourceManagementPage> createState() => _ResourceManagementPageState();
}

class _ResourceManagementPageState extends State<ResourceManagementPage> {
  static const _categories = [
    ResourceCategory(value: 'pe', label: 'PE 资源', uploadLabel: '上传 PE 资源'),
    ResourceCategory(value: 'comp', label: 'PC 模组', uploadLabel: '上传 PC 模组'),
    ResourceCategory(value: 'multi', label: '网络游戏', uploadLabel: '上传网络游戏'),
    ResourceCategory(
      value: 'pe_multi',
      label: 'PE 网络游戏',
      uploadLabel: '上传 PE 网络游戏',
    ),
  ];

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  String _category = _categories.first.value;
  bool _loading = false;
  String? _error;
  List<ResourceItem> _items = [];
  int _total = 0;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  ResourceCategory get _currentCategory => _categories.firstWhere(
    (category) => category.value == _category,
    orElse: () => _categories.first,
  );

  Future<void> _loadResources() async {
    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '请先到“设置”里登录。';
        _items = [];
        _total = 0;
      });
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final api = McDevApi(cookie: cookieHeader, category: _category);
    try {
      final page = await api.fetchResources(
        resourceCategory: _category,
        keyword: _searchController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items = page.items;
        _total = page.total;
        _updatedAt = DateTime.now();
        _loading = false;
        _error = page.items.isEmpty ? '暂无资源。' : null;
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

  List<ResourceItem> _filteredItems() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }
    return _items.where((item) {
      return item.name.toLowerCase().contains(query) ||
          item.id.toLowerCase().contains(query) ||
          (item.status ?? '').toLowerCase().contains(query);
    }).toList();
  }

  String _statusLabel(ResourceItem item) {
    final raw = item.status?.trim();
    if (raw == null || raw.isEmpty) {
      return item.weakOffline == true ? '弱下架' : '未知';
    }
    final value = raw.toLowerCase();
    if (value.contains('online')) {
      return item.weakOffline == true ? '弱下架' : '已上架';
    }
    if (value.contains('offline')) {
      return '已下架';
    }
    if (value.contains('review') || value.contains('audit')) {
      return '审核中';
    }
    return raw;
  }

  String _priceLabel(ResourceItem item) {
    final price = item.price;
    if (price == null || price <= 0) {
      return '免费';
    }
    final text = NumberFormat.decimalPattern().format(price);
    switch (_priceKind(item.priceType)) {
      case _PriceKind.diamond:
        return '$text 钻石';
      case _PriceKind.emerald:
        return '$text 绿宝石';
      case _PriceKind.other:
        return text;
    }
  }

  Future<void> _openEditor({ResourceItem? item}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            ResourceEditorPage(category: _currentCategory, item: item),
      ),
    );
    if (changed == true) {
      await _loadResources();
    }
  }

  Future<void> _runAction(
    ResourceItem item,
    String action,
    String label,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text('${item.name}\nID: ${item.id}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    final api = McDevApi(cookie: cookieHeader, category: _category);
    try {
      if (action == 'delete') {
        await api.deleteResource(
          resourceCategory: item.category,
          itemId: item.id,
        );
      } else {
        await api.changeResourceStatus(
          resourceCategory: item.category,
          itemId: item.id,
          action: action,
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label 已提交')));
      await _loadResources();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      api.close();
    }
  }

  Widget _buildToolbar(BuildContext context) {
    final categoryButtonWidth = OreTokens.controlHeightMd * 3.4;
    final actionButtonWidth = OreTokens.controlHeightMd * 3.2;
    return OreStrip(
      tone: OreStripTone.dark,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: _categories
                  .map(
                    (category) => ButtonSegment(
                      value: category.value,
                      label: Text(category.label),
                    ),
                  )
                  .toList(),
              selected: {_category},
              buttonWidth: categoryButtonWidth,
              onSelectionChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _category = value.first;
                        _items = [];
                        _total = 0;
                      });
                      _loadResources();
                    },
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadResources,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
              width: actionButtonWidth,
            ),
            ElevatedButton.icon(
              onPressed: _loading ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新建'),
              width: actionButtonWidth,
            ),
            Text('显示 ${_filteredItems().length} / $_total'),
            if (_updatedAt != null) Text(_dateFormat.format(_updatedAt!)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return OreStrip(
      tone: OreStripTone.dark,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
            ),
            labelText: '搜索名称、ID 或状态',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) => _loadResources(),
          onChanged: (_) => setState(() {}),
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
              onPressed: _loading ? null : _loadResources,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceCard(ResourceItem item, ThemeData theme) {
    final statusLabel = _statusLabel(item);
    final updated = item.updatedAt == null
        ? '更新时间未知'
        : _dateFormat.format(item.updatedAt!);
    return OreCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.iconUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: Image.network(
                    item.iconUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 48, height: 48),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('ID: ${item.id}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _openEditor(item: item);
                      break;
                    case 'apply_review':
                      _runAction(item, 'apply_review', '提交审核');
                      break;
                    case 'online':
                      _runAction(item, 'online', '上架');
                      break;
                    case 'offline':
                      _runAction(item, 'offline', '下架');
                      break;
                    case 'delete':
                      _runAction(item, 'delete', '删除资源');
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'apply_review', child: Text('提交审核')),
                  PopupMenuItem(value: 'online', child: Text('上架')),
                  PopupMenuItem(value: 'offline', child: Text('下架')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text('状态: $statusLabel', style: theme.textTheme.bodySmall),
              Text(
                '价格: ${_priceLabel(item)}',
                style: theme.textTheme.bodySmall,
              ),
              Text(updated, style: theme.textTheme.bodySmall),
            ],
          ),
          if (item.brief != null && item.brief!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.brief!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1000;
    final filtered = _filteredItems();
    return SafeArea(
      child: Column(
        children: [
          _buildToolbar(context),
          _buildSearch(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildError(theme)
                : filtered.isEmpty
                ? const Center(child: Text('暂无资源'))
                : Scrollbar(
                    controller: _scrollController,
                    child: GridView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isWide ? 2 : 1,
                        mainAxisSpacing: 0,
                        crossAxisSpacing: 0,
                        mainAxisExtent: isWide ? 178 : 204,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _buildResourceCard(filtered[index], theme),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ResourceEditorPage extends StatefulWidget {
  const ResourceEditorPage({super.key, required this.category, this.item});

  final ResourceCategory category;
  final ResourceItem? item;

  @override
  State<ResourceEditorPage> createState() => _ResourceEditorPageState();
}

class _ResourceEditorPageState extends State<ResourceEditorPage> {
  final _scrollController = ScrollController();
  final _jsonController = TextEditingController();
  final _nameController = TextEditingController();
  final _briefController = TextEditingController();
  final _infoController = TextEditingController();
  final _priceController = TextEditingController();
  final _priceTypeController = TextEditingController();
  final _priTypeController = TextEditingController();
  final _subTypeController = TextEditingController();
  final _updateSummaryController = TextEditingController();
  final _changeLogController = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _raw = {};

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _jsonController.dispose();
    _nameController.dispose();
    _briefController.dispose();
    _infoController.dispose();
    _priceController.dispose();
    _priceTypeController.dispose();
    _priTypeController.dispose();
    _subTypeController.dispose();
    _updateSummaryController.dispose();
    _changeLogController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_isNew) {
      _setRaw(_defaultPayload());
      return;
    }
    setState(() => _loading = true);
    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    final api = McDevApi(cookie: cookieHeader, category: widget.category.value);
    try {
      final detail = await api.fetchResourceDetail(
        resourceCategory: widget.category.value,
        itemId: widget.item!.id,
      );
      if (!mounted) {
        return;
      }
      _setRaw(detail.raw);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setRaw(widget.item!.raw);
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } finally {
      api.close();
    }
  }

  Map<String, dynamic> _defaultPayload() {
    return {
      'item_name': '',
      'price_type': 'free',
      'price': 0,
      'brief': '',
      'info': '',
      'pri_type': '',
      'sub_type': '',
      'res': [],
      'channel': [],
      'charge_type': '',
      'charge_desc': '',
      'current_change_log': '',
      'update_summary': '',
    };
  }

  String _prettyJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  String _stringValue(List<String> keys) {
    for (final key in keys) {
      final value = _raw[key];
      if (value == null) {
        continue;
      }
      final text = value.toString();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  void _setRaw(Map<String, dynamic> raw) {
    _raw = Map<String, dynamic>.from(raw);
    _nameController.text = _stringValue(['item_name', 'name', 'title']);
    _briefController.text = _stringValue(['brief', 'description', 'desc']);
    _infoController.text = _stringValue(['info', 'detail']);
    _priceController.text = _stringValue(['price']);
    _priceTypeController.text = _stringValue(['price_type']);
    _priTypeController.text = _stringValue(['pri_type']);
    _subTypeController.text = _stringValue(['sub_type']);
    _updateSummaryController.text = _stringValue(['update_summary']);
    _changeLogController.text = _stringValue(['current_change_log']);
    _jsonController.text = _prettyJson(_raw);
  }

  void _setIfPresentOrNotEmpty(
    Map<String, dynamic> map,
    String key,
    String value,
  ) {
    if (map.containsKey(key) || value.trim().isNotEmpty) {
      map[key] = value.trim();
    }
  }

  Map<String, dynamic>? _buildPayload() {
    dynamic decoded;
    try {
      decoded = jsonDecode(_jsonController.text);
    } catch (error) {
      setState(() => _error = '原始 JSON 无法解析: $error');
      return null;
    }
    if (decoded is! Map) {
      setState(() => _error = '原始 JSON 顶层必须是对象');
      return null;
    }
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    _setIfPresentOrNotEmpty(map, 'item_name', _nameController.text);
    _setIfPresentOrNotEmpty(map, 'name', _nameController.text);
    _setIfPresentOrNotEmpty(map, 'brief', _briefController.text);
    _setIfPresentOrNotEmpty(map, 'description', _briefController.text);
    _setIfPresentOrNotEmpty(map, 'info', _infoController.text);
    _setIfPresentOrNotEmpty(map, 'price_type', _priceTypeController.text);
    _setIfPresentOrNotEmpty(map, 'pri_type', _priTypeController.text);
    _setIfPresentOrNotEmpty(map, 'sub_type', _subTypeController.text);
    _setIfPresentOrNotEmpty(
      map,
      'update_summary',
      _updateSummaryController.text,
    );
    _setIfPresentOrNotEmpty(
      map,
      'current_change_log',
      _changeLogController.text,
    );
    final priceText = _priceController.text.trim();
    if (map.containsKey('price') || priceText.isNotEmpty) {
      map['price'] = int.tryParse(priceText) ?? 0;
    }
    return map;
  }

  Future<void> _save() async {
    final payload = _buildPayload();
    if (payload == null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    final api = McDevApi(cookie: cookieHeader, category: widget.category.value);
    try {
      await api.saveResource(
        resourceCategory: widget.category.value,
        itemId: widget.item?.id,
        payload: payload,
      );
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    } finally {
      api.close();
    }
  }

  Widget _buildField(
    TextEditingController controller, {
    required String label,
    IconData? icon,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _buildCommonFields(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final compactFields = <Widget>[
      _buildField(
        _nameController,
        label: '资源名称',
        icon: Icons.drive_file_rename_outline,
      ),
      _buildField(
        _priceController,
        label: '价格',
        icon: Icons.paid_outlined,
        keyboardType: TextInputType.number,
      ),
      _buildField(
        _priceTypeController,
        label: '定价类型',
        icon: Icons.diamond_outlined,
      ),
      _buildField(
        _priTypeController,
        label: '主类别',
        icon: Icons.category_outlined,
      ),
      _buildField(
        _subTypeController,
        label: '次类别',
        icon: Icons.account_tree_outlined,
      ),
    ];
    final longFields = <Widget>[
      _buildField(
        _briefController,
        label: '简介',
        icon: Icons.subject,
        maxLines: 3,
      ),
      _buildField(
        _infoController,
        label: '详情信息',
        icon: Icons.article_outlined,
        maxLines: 6,
      ),
      _buildField(
        _updateSummaryController,
        label: '更新纪要',
        icon: Icons.update,
        maxLines: 3,
      ),
      _buildField(
        _changeLogController,
        label: '更新日志',
        icon: Icons.history,
        maxLines: 3,
      ),
    ];
    return OreCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('常用字段', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 2 : 1,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 76,
            ),
            itemCount: compactFields.length,
            itemBuilder: (context, index) => compactFields[index],
          ),
          const SizedBox(height: 12),
          for (final field in longFields) ...[
            field,
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildJsonEditor(BuildContext context) {
    return OreCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('原始 Payload', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _jsonController,
            maxLines: 18,
            minLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              labelText: 'JSON',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew ? widget.category.uploadLabel : '编辑资源';
    final actionButtonWidth = OreTokens.controlHeightMd * 3.6;
    return Scaffold(
      appBar: buildOreAppBar(
        context,
        title: title,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: _scrollController,
                padding: EdgeInsets.zero,
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
                          Text(widget.category.label),
                          if (widget.item != null)
                            Text('ID: ${widget.item!.id}'),
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_saving ? '保存中' : '保存'),
                            width: actionButtonWidth,
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close),
                            label: const Text('取消'),
                            width: actionButtonWidth,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null)
                    OreStrip(
                      tone: OreStripTone.dark,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  _buildCommonFields(context),
                  _buildJsonEditor(context),
                ],
              ),
      ),
    );
  }
}
