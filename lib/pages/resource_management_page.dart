part of '../main.dart';

class ResourceManagementPage extends StatefulWidget {
  const ResourceManagementPage({super.key, this.apiFactory});
  final McDevApi Function()? apiFactory;
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
  final _scroll = ScrollController();
  final _search = TextEditingController();
  String _category = 'pe';
  String _status = '';
  bool _loading = false;
  String? _working;
  String? _error;
  List<ResourceItem> _items = [];
  int _total = 0;
  int _start = 0;
  int _generation = 0;
  Map<String, dynamic> _permissions = {};
  static const _span = 30;

  ResourceCategory get _currentCategory =>
      _categories.firstWhere((c) => c.value == _category);

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<McDevApi> _api() async {
    if (widget.apiFactory != null) return widget.apiFactory!();
    final cookie = await LoginCookieHelper.buildCookieHeader();
    if (cookie.isEmpty) throw StateError('请先到“设置”里登录');
    return McDevApi(cookie: cookie, category: _category);
  }

  Future<void> _loadResources({int start = 0}) async {
    final generation = ++_generation;
    final category = _category, query = _search.text, status = _status;
    setState(() {
      _loading = true;
      _error = null;
    });
    McDevApi? api;
    try {
      api = await _api();
      final page = await api.fetchResources(
        resourceCategory: category,
        start: start,
        span: _span,
        keyword: query,
        status: status,
      );
      if (_permissions.isEmpty) {
        try {
          _permissions = (await api.fetchDeveloperProfile()).userRaw ?? {};
        } catch (_) {
          /* Common list operations remain available. */
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _start = start;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    } finally {
      api?.close();
    }
  }

  Future<void> _openEditor([ResourceItem? item]) async {
    var category = _currentCategory;
    var edited = item;
    if (item?.category == 'comp' && item?.raw['sync_pc_flag'] == true) {
      final peId = item!.raw['relate_item_id']?.toString();
      if (peId == null || peId.isEmpty) {
        setState(() => _error = '该作品由 PE 同步生成，但平台未返回关联编号，请前往 PE 资源查找');
        return;
      }
      category = _categories.first;
      edited = ResourceItem.fromJson('pe', {
        'item_id': peId,
        'item_name': item.name,
      });
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResourceEditorPage(
          category: category,
          item: edited,
          apiFactory: widget.apiFactory,
        ),
      ),
    );
    if (changed == true && mounted) await _loadResources(start: _start);
  }

  Future<void> _review(ResourceItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ResourceReviewPage(item: item, apiFactory: widget.apiFactory),
      ),
    );
    if (changed == true && mounted) await _loadResources(start: _start);
  }

  Future<void> _detail(ResourceItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ResourceDetailPage(item: item, apiFactory: widget.apiFactory),
      ),
    );
  }

  Future<bool> _confirm(String title, String message) async =>
      await showOreDialog<bool>(
        context: context,
        builder: (ctx) => ResourceDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ) ==
      true;

  Future<String?> _prompt(
    String title,
    String label, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showOreDialog<String>(
      context: context,
      builder: (ctx) => ResourceDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // The route may still be animating; let its text field detach first.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  Future<Map<String, dynamic>?> _pricePayload(ResourceItem item) async {
    McDevApi? api;
    setState(() => _working = item.id);
    try {
      api = await _api();
      final detail = await api.fetchResourceDetail(
        resourceCategory: item.category,
        itemId: item.id,
      );
      final settings = ResourcePriceSettings(
        await api.fetchPlatformSettings('item_price_setting'),
        useRank: _permissions['use_price_rank'] == true,
        hasChannel: _permissions['can_office_channel'] == true,
      );
      final options = await api.fetchResourceOptions();
      if (!mounted) return null;
      return await showOreDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => ResourcePriceDialog(
          item: detail,
          settings: settings,
          options: options,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return null;
    } finally {
      api?.close();
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _runAction(
    ResourceItem item,
    String action,
    String label,
  ) async {
    if (_working != null) return;
    if (action == 'apply_review') {
      await _review(item);
      return;
    }
    Map<String, dynamic> payload = {};
    if (action == 'urgent-admin' || action == 'exempt_review') {
      final reason = await _prompt(
        label,
        action == 'urgent-admin' ? '加急原因' : '弱下架原因',
      );
      if (reason == null || reason.isEmpty) return;
      payload = action == 'urgent-admin'
          ? {'reason': reason}
          : {
              'type': 'weak_offline',
              'weak_offline_reason': reason,
              if (item.raw['sync_pc_flag'] == true) 'op_platform': 'all',
            };
    } else if (action == 'change_price') {
      final pricePayload = await _pricePayload(item);
      if (pricePayload == null) return;
      payload = pricePayload;
    } else if (action == 'appoint_online') {
      final time = await showOreDialog<String>(
        context: context,
        builder: (_) => const ResourceScheduleDialog(),
      );
      if (time == null) return;
      payload = {'appoint_online_time': time};
    } else if (action == 'cancel_appoint') {
      action = 'appoint_online';
      payload = {'appoint_online_time': null};
    } else if (action == 'self_test_without_check') {
      action = 'self-test-apply';
      payload = {'self_test_pass_check': true};
    } else if (action == 'self-test-apply') {
      payload = {'self_test_pass_check': false, 'is_check_apply': false};
    }
    if (!mounted ||
        !await _confirm(
          label,
          '${item.name}\n资源编号：${item.id}${action == 'delete' ? '\n删除后无法通过本软件恢复。' : ''}',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _working = item.id);
    McDevApi? api;
    try {
      api = await _api();
      Map<String, dynamic> result;
      if (action == 'delete') {
        result = await api.deleteResource(
          resourceCategory: item.category,
          itemId: item.id,
        );
      } else if (['urgent-admin', 'change_price', 'remind'].contains(action)) {
        result = await api.resourcePostAction(
          resourceCategory: item.category,
          itemId: item.id,
          action: action,
          payload: payload,
        );
      } else {
        result = await api.changeResourceStatus(
          resourceCategory: item.category,
          itemId: item.id,
          action: action,
          payload: payload,
        );
      }
      if (!mounted) return;
      if (result['data']?['need_check_apply'] == true) {
        if (!await _confirm(
          '处理队列较长',
          '当前有 ${result['data']?['queue_length']} 个资源排队，是否继续？',
        )) {
          return;
        }
        result = await api.changeResourceStatus(
          resourceCategory: item.category,
          itemId: item.id,
          action: action,
          payload: {...payload, 'is_check_apply': true},
        );
        if (result['data']?['need_check_apply'] == true) {
          throw StateError('平台仍要求确认，请刷新后重试');
        }
      }
      if (!mounted) return;
      showOreToast(context, Text('$label 已完成'));
      if (['urgent-admin', 'exempt_review'].contains(action)) _permissions = {};
      await _loadResources(start: action == 'delete' ? 0 : _start);
    } catch (e) {
      if (mounted) {
        showOreToast(context, Text(e.toString()));
      }
    } finally {
      api?.close();
      if (mounted) setState(() => _working = null);
    }
  }

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: min(170, constraints.maxWidth),
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                items: _categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.value,
                        child: Text(c.label),
                      ),
                    )
                    .toList(),
                onChanged: _loading || _working != null
                    ? null
                    : (v) {
                        setState(() => _category = v!);
                        _loadResources();
                      },
              ),
            ),
            SizedBox(
              width: min(170, constraints.maxWidth),
              child: DropdownButton<String>(
                value: _status,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('所有状态')),
                  ...resourceStatusLabels.entries.map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ),
                ],
                onChanged: _loading || _working != null
                    ? null
                    : (v) {
                        setState(() => _status = v!);
                        _loadResources();
                      },
              ),
            ),
            SizedBox(
              width: min(420, constraints.maxWidth),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: '搜索作品名称 / ID',
                      ),
                      onSubmitted: _loading ? null : (_) => _loadResources(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _loading ? null : _loadResources,
                    child: const Text('搜索'),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed:
                  _loading ||
                      _working != null ||
                      !['pe', 'comp'].contains(_category)
                  ? null
                  : _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('新建作品'),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _loadResources(start: _start),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _card(ResourceItem item) {
    final supported = ['pe', 'comp'].contains(item.category);
    final canEdit =
        supported && ['init', 'reject', 'online'].contains(item.status);
    final synced = item.category == 'comp' && item.raw['sync_pc_flag'] == true;
    final actions = resourceActions(item, permissions: _permissions);
    final status = resourceStatusLabels[item.status] ?? item.status ?? '未知';
    return OreCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (actions.isNotEmpty)
                SizedBox(
                  width: 140,
                  child: DropdownButton<String>(
                    value: null,
                    hint: const Text('作品操作'),
                    isExpanded: true,
                    onChanged: _working != null
                        ? null
                        : (value) {
                            if (value == null) return;
                            final label = actions
                                .firstWhere((a) => a.$1 == value)
                                .$2;
                            _runAction(item, value, label);
                          },
                    items: actions
                        .map(
                          (a) =>
                              DropdownMenuItem(value: a.$1, child: Text(a.$2)),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('ID：${item.id}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            '$status${item.weakOffline == true ? ' · 弱下架' : ''}  ·  ${item.price == null || item.price == 0 ? '免费' : '${item.price} ${item.priceType == 'point' ? '绿宝石' : '钻石'}'}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _working == null ? () => _detail(item) : null,
                child: const Text('详情'),
              ),
              if (canEdit)
                OutlinedButton(
                  onPressed: _working == null ? () => _openEditor(item) : null,
                  child: Text(
                    synced
                        ? '前往 PE 同步编辑'
                        : item.status == 'online'
                        ? '更新'
                        : '编辑',
                  ),
                ),
              OutlinedButton(
                onPressed: _working == null ? () => _review(item) : null,
                child: Text(
                  supported && !synced && item.status == 'init'
                      ? '提交审核'
                      : '审核与反馈',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        _toolbar(),
        if (_working != null) const OreProgressBar(),
        Expanded(
          child: _loading
              ? const Center(child: OreLoadingIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loadResources,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
              ? const Center(child: Text('暂无符合条件的作品'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final contentWidth = constraints.maxWidth - spacing * 2;
                    final columns = ((contentWidth + spacing) / (360 + spacing))
                        .floor()
                        .clamp(1, 3);
                    final cardWidth =
                        (contentWidth - spacing * (columns - 1)) / columns;
                    return Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: Padding(
                          padding: const EdgeInsets.all(spacing),
                          child: SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.start,
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                for (final item in _items)
                                  SizedBox(
                                    width: cardWidth,
                                    child: _card(item),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _loading || _start == 0
                    ? null
                    : () => _loadResources(start: max(0, _start - _span)),
                child: const Text('上一页'),
              ),
              Text('第 ${_start ~/ _span + 1} 页 · 共 $_total 个作品'),
              OutlinedButton(
                onPressed: _loading || _start + _span >= _total
                    ? null
                    : () => _loadResources(start: _start + _span),
                child: const Text('下一页'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ResourceDetailPage extends StatefulWidget {
  const ResourceDetailPage({super.key, required this.item, this.apiFactory});
  final ResourceItem item;
  final McDevApi Function()? apiFactory;
  @override
  State<ResourceDetailPage> createState() => _ResourceDetailPageState();
}

class _ResourceDetailPageState extends State<ResourceDetailPage> {
  final _scroll = ScrollController();
  ResourceItem? _detail;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    McDevApi? api;
    try {
      final cookie = widget.apiFactory == null
          ? await LoginCookieHelper.buildCookieHeader()
          : '';
      api =
          widget.apiFactory?.call() ??
          McDevApi(cookie: cookie, category: widget.item.category);
      final detail = await api.fetchResourceDetail(
        resourceCategory: widget.item.category,
        itemId: widget.item.id,
      );
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      api?.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: buildOreAppBar(
      context,
      title: widget.item.name,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('返回'),
        ),
      ],
    ),
    body: _detail == null
        ? Center(
            child: _error == null ? const OreLoadingIndicator() : Text(_error!),
          )
        : ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            children: [
              OreSelectableText('资源编号：${_detail!.id}'),
              const SizedBox(height: 8),
              Text(
                '状态：${resourceStatusLabels[_detail!.status] ?? _detail!.status}',
              ),
              const SizedBox(height: 16),
              for (final res in ResourceOptions.maps(_detail!.raw['res']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '资源文件：${res['res_name']}\n适用版本：${res['mc_version']}',
                  ),
                ),
              for (final channel in ResourceOptions.maps(
                _detail!.raw['channel'],
              ))
                if (channel['channel_url'] is String &&
                    (channel['channel_url'] as String).startsWith('https://'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Image.network(
                      channel['channel_url'],
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text('图片预览暂不可用'),
                    ),
                  ),
              HtmlWidget(
                _detail!.raw['info']?.toString() ?? '',
                onLoadingBuilder: (_, _, _) => const OreLoadingIndicator(),
                onTapUrl: (_) async => false,
              ),
              const SizedBox(height: 16),
              const Text('更新日志'),
              for (final log
                  in (_detail!.raw['change_log'] is List
                      ? _detail!.raw['change_log'] as List
                      : [_detail!.raw['change_log']].where((e) => e != null)))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    log is Map
                        ? '${log['time'] ?? log['create_time'] ?? ''}\n${log['content'] ?? log['change_log'] ?? log}'
                        : '$log',
                  ),
                ),
            ],
          ),
  );
}
