part of '../main.dart';

class ResourceReviewPage extends StatefulWidget {
  const ResourceReviewPage({super.key, required this.item, this.apiFactory});
  final ResourceItem item;
  final McDevApi Function()? apiFactory;
  @override
  State<ResourceReviewPage> createState() => _ResourceReviewPageState();
}

class _ResourceReviewPageState extends State<ResourceReviewPage> {
  final _notes = TextEditingController();
  final _scroll = ScrollController();
  McDevApi? _api;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _feedback = [];
  ResourceItem? _detail;
  bool _canConflict = false;
  int _conflict = 0;
  Set<int> _conflictTypes = {0};

  bool get _canSubmit =>
      _detail?.status == 'init' &&
      ['pe', 'comp'].contains(widget.item.category) &&
      !(widget.item.category == 'comp' && _detail?.raw['sync_pc_flag'] == true);

  String _feedbackHtml(Map<String, dynamic> entry) =>
      ['rich_feedback', 'feedback', 'content']
          .map((key) => entry[key]?.toString() ?? '')
          .firstWhere((text) => text.isNotEmpty, orElse: () => '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    _scroll.dispose();
    _api?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cookie = widget.apiFactory == null
          ? await LoginCookieHelper.buildCookieHeader()
          : '';
      if (cookie.isEmpty && widget.apiFactory == null) throw StateError('请先登录');
      _api?.close();
      final api =
          widget.apiFactory?.call() ??
          McDevApi(cookie: cookie, category: widget.item.category);
      _api = api;
      final detail = await api.fetchResourceDetail(
        resourceCategory: widget.item.category,
        itemId: widget.item.id,
      );
      final feedback = await api.fetchResourceFeedbacks(
        resourceCategory: widget.item.category,
        itemId: widget.item.id,
      );
      final profile = await api.fetchDeveloperProfile();
      if (mounted) {
        setState(() {
          _detail = detail;
          _feedback = feedback;
          _canConflict =
              profile.userRaw?['can_set_conflict_notify'] == true &&
              detail.raw['pri_type'] == 2;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _chooseConflictTypes() async {
    final selected = {..._conflictTypes};
    final result = await showOreDialog<Set<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => ResourceDialog(
          title: const Text('冲突检测范围'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: resourceConflictTypes.entries
                .map(
                  (entry) => OreButton(
                    size: OreButtonSize.sm,
                    variant: selected.contains(entry.key)
                        ? OreButtonVariant.primary
                        : OreButtonVariant.secondary,
                    onPressed: () => update(() {
                      if (entry.key == 0) {
                        selected
                          ..clear()
                          ..add(0);
                      } else {
                        selected.remove(0);
                        selected.contains(entry.key)
                            ? selected.remove(entry.key)
                            : selected.add(entry.key);
                      }
                    }),
                    child: Text(entry.value),
                  ),
                )
                .toList(),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, selected),
              child: const Text('应用范围'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) setState(() => _conflictTypes = result);
  }

  Future<bool> _confirm(String title, String content) async =>
      await showOreDialog<bool>(
        context: context,
        builder: (ctx) => ResourceDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认提交'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _submit() async {
    if (_submitting || _api == null || !_canSubmit) return;
    if (_notes.text.trim().length > 500) {
      setState(() => _error = '审核备注不能超过 500 字');
      _scroll.jumpTo(0);
      return;
    }
    if (!await _confirm(
      '提交审核',
      '将“${widget.item.name}”提交平台审核。提交后可在审核状态允许时撤销。',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var result = await _api!.submitResourceReview(
        resourceCategory: widget.item.category,
        itemId: widget.item.id,
        notes: _notes.text,
        conflictNotify: _canConflict ? _conflict : null,
        conflictTypes: _canConflict && _conflict != 0
            ? _conflictTypes.toList()
            : null,
      );
      if (!mounted) return;
      if (result['data']?['need_check_apply'] == true) {
        final count = result['data']?['queue_length'];
        final settings = await _api!.fetchPlatformSettings(
          'async_wait_queue_setting',
        );
        if (!mounted) return;
        final message =
            settings['queue_too_long_notify']?.toString().replaceAll(
              '{{queue_length}}',
              '$count',
            ) ??
            '当前审核队列有 $count 个资源，是否继续排队？';
        if (!await _confirm('确认审核排队', message)) return;
        result = await _api!.submitResourceReview(
          resourceCategory: widget.item.category,
          itemId: widget.item.id,
          notes: _notes.text,
          confirmQueue: true,
          conflictNotify: _canConflict ? _conflict : null,
          conflictTypes: _canConflict && _conflict != 0
              ? _conflictTypes.toList()
              : null,
        );
        if (result['data']?['need_check_apply'] == true) {
          throw StateError('平台仍要求确认排队，请刷新后重试');
        }
      }
      if (!mounted) return;
      showOreToast(context, Text('模组已提交审核'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '提交未完成，已保存的资源仍然保留。\n$e');
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _detail ?? widget.item;
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: buildOreAppBar(
          context,
          title: '审核与反馈',
          actions: [
            OutlinedButton(
              onPressed: _submitting ? null : () => Navigator.maybePop(context),
              child: const Text('返回'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: OreLoadingIndicator())
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  OreCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        OreSelectableText('资源编号：${item.id}'),
                        Text(
                          '状态：${resourceStatusLabels[item.status] ?? item.status ?? '未知'}',
                        ),
                        if (item.raw['queue_position'] != null)
                          Text('队列位置：${item.raw['queue_position']}'),
                        if (item.raw['apply_review_time'] != null)
                          Text('提交时间：${item.raw['apply_review_time']}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    OreCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _submitting ? null : _load,
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  OreCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '审核意见',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (_feedback.isEmpty ||
                            _feedback.every((f) => _feedbackHtml(f).isEmpty))
                          const Text('暂无审核意见'),
                        for (final feedback in _feedback) ...[
                          HtmlWidget(
                            _feedbackHtml(feedback),
                            onLoadingBuilder: (_, _, _) =>
                                const OreLoadingIndicator(),
                            onTapUrl: (_) async => false,
                          ),
                          if (feedback['pack_error_code'] != null &&
                              feedback['pack_error_code'] != 0)
                            Text('打包错误码：${feedback['pack_error_code']}'),
                        ],
                      ],
                    ),
                  ),
                  if (item.raw['ori_weak_offline_reason'] != null)
                    OreCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('下架反馈'),
                          const SizedBox(height: 12),
                          HtmlWidget(
                            item.raw['ori_weak_offline_reason'].toString(),
                            onLoadingBuilder: (_, _, _) =>
                                const OreLoadingIndicator(),
                            onTapUrl: (_) async => false,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_canSubmit)
                    OreCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '提交审核',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notes,
                            enabled: !_submitting,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: '审核备注（最多 500 字，填写玩法、测试方法等）',
                            ),
                          ),
                          if (_canConflict) ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                              value: _conflict,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '资源冲突通知',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('不接收报告'),
                                ),
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('接收本账号模组冲突报告'),
                                ),
                                DropdownMenuItem(
                                  value: 2,
                                  child: Text('接收全平台冲突报告'),
                                ),
                              ],
                              onChanged: _submitting
                                  ? null
                                  : (v) => setState(() => _conflict = v!),
                            ),
                            if (_conflict != 0) ...[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _submitting
                                    ? null
                                    : _chooseConflictTypes,
                                child: Text(
                                  _conflictTypes.contains(0)
                                      ? '检测范围：全部'
                                      : '检测范围：${_conflictTypes.length} 项',
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            child: Text(_submitting ? '提交中…' : '提交审核'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
