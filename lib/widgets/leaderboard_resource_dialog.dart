part of '../main.dart';

class LeaderboardResourceDialog extends StatefulWidget {
  const LeaderboardResourceDialog({
    super.key,
    required this.entry,
    this.apiFactory,
  });

  final LeaderboardEntry entry;
  final McDevApi Function()? apiFactory;

  @override
  State<LeaderboardResourceDialog> createState() =>
      _LeaderboardResourceDialogState();
}

class _LeaderboardResourceDialogState extends State<LeaderboardResourceDialog> {
  final _galleryKey = GlobalKey();
  final _gallery = PageController();
  final _number = NumberFormat.decimalPattern();
  McDevApi? _api;
  McDevApi? _commentsApi;
  LeaderboardResourceDetail? _detail;
  LeaderboardResourceComments? _comments;
  String? _error;
  String? _commentsError;
  bool _loading = true;
  bool _commentsLoading = false;
  bool _showComments = false;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api?.close();
    _api = null;
    _commentsApi?.close();
    _commentsApi = null;
    _gallery.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool more = false}) async {
    if (_commentsLoading || widget.entry.isDesktop) return;
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });
    McDevApi? api;
    try {
      api = widget.apiFactory?.call() ?? McDevApi(cookie: '', category: 'pe');
      _commentsApi = api;
      final comments = await api.fetchLeaderboardResourceComments(
        widget.entry,
        length: more ? (_comments?.requestedLength ?? 0) + 20 : 20,
      );
      if (mounted) setState(() => _comments = comments);
    } catch (error) {
      if (mounted) {
        setState(
          () => _commentsError = error is McDevException
              ? error.message
              : '暂时无法加载评论，请重试',
        );
      }
    } finally {
      if (identical(_commentsApi, api)) {
        api?.close();
        _commentsApi = null;
      }
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  void _selectContent(int index) {
    setState(() => _showComments = index == 1);
    if (_showComments && _comments == null && _commentsError == null) {
      _loadComments();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    McDevApi? api;
    try {
      api = widget.apiFactory?.call() ?? McDevApi(cookie: '', category: 'pe');
      _api = api;
      final detail = await api.fetchLeaderboardResource(widget.entry);
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is McDevException
              ? error.message
              : '暂时无法加载资源详情，请重试',
        );
      }
    } finally {
      if (identical(_api, api)) {
        api?.close();
        _api = null;
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      showOreToast(context, const Text('组件码已复制'));
    }
  }

  Future<bool> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return true;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) showOreToast(context, const Text('无法打开链接'));
    } catch (_) {
      if (mounted) showOreToast(context, const Text('无法打开链接'));
    }
    return true;
  }

  Widget _image(String url, {double? size, String? label}) => Image.network(
    url,
    width: size,
    height: size,
    fit: size == null ? BoxFit.contain : BoxFit.cover,
    semanticLabel: label,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: OreLoadingIndicator(size: 20)),
    errorBuilder: (_, _, _) => Center(
      child: size == null
          ? const Text('展示图暂时无法加载')
          : const Icon(Icons.extension_outlined, size: 28),
    ),
  );

  Widget _images(List<String> urls) => Column(
    key: _galleryKey,
    mainAxisSize: MainAxisSize.min,
    children: [
      AspectRatio(
        aspectRatio: 16 / 10,
        child: PageView.builder(
          controller: _gallery,
          itemCount: urls.length,
          onPageChanged: (index) => setState(() => _imageIndex = index),
          itemBuilder: (context, index) =>
              _image(urls[index], label: '资源展示图 ${index + 1}'),
        ),
      ),
      if (urls.length > 1)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OreIconButton(
              tooltip: '上一张展示图',
              icon: const Icon(Icons.chevron_left),
              onPressed: _imageIndex == 0
                  ? null
                  : () => _gallery.previousPage(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                    ),
            ),
            Text(
              '${_imageIndex + 1} / ${urls.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            OreIconButton(
              tooltip: '下一张展示图',
              icon: const Icon(Icons.chevron_right),
              onPressed: _imageIndex == urls.length - 1
                  ? null
                  : () => _gallery.nextPage(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                    ),
            ),
          ],
        ),
    ],
  );

  Widget _facts(LeaderboardResourceDetail detail) {
    final fields = <String, String>{
      if (detail.downloads != null) '总下载': _number.format(detail.downloads),
      if (detail.likes != null) '点赞': _number.format(detail.likes),
      if (detail.rating != null) '评分': detail.rating!.toStringAsFixed(1),
      if (detail.ratingCount != null)
        '评分人数': _number.format(detail.ratingCount),
      if (detail.commentCount != null)
        '评论': _number.format(detail.commentCount),
      if (detail.priceLabel != null) '定价': detail.priceLabel!,
      if (detail.version.isNotEmpty) '版本': detail.version,
    };
    if (fields.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = (constraints.maxWidth / (125 * scale)).floor().clamp(
            2,
            6,
          );
          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final field in fields.entries)
                SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.key,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        field.value,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _componentCode(LeaderboardResourceDetail detail) =>
      detail.componentCode.isEmpty
      ? const SizedBox.shrink()
      : Row(
          children: [
            Expanded(child: Text('组件码  ${detail.componentCode}')),
            OreIconButton(
              tooltip: '复制组件码',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => _copyCode(detail.componentCode),
            ),
          ],
        );

  Widget _resourceId() => Text(
    '资源 ID  ${widget.entry.id}',
    style: Theme.of(context).textTheme.bodySmall,
  );

  Widget _contentTabs() => LayoutBuilder(
    builder: (context, constraints) => OreChoiceButtons(
      items: const [Text('资源介绍'), Text('评论与评分')],
      selectedIndex: _showComments ? 1 : 0,
      onChanged: _selectContent,
      size: OreButtonSize.sm,
      buttonWidth: constraints.maxWidth / 2,
    ),
  );

  Widget _ratingSummary(LeaderboardResourceDetail detail) {
    final rating = detail.rating;
    final count = detail.ratingCount;
    final hasRating = rating != null && rating > 0 && count != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasRating ? '${rating.toStringAsFixed(1)} / 5' : '暂无评分',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (count != null)
          Text(
            '${_number.format(count)} 人评分',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _comment(LeaderboardResourceComment comment) {
    final date = comment.publishedAt?.toLocal();
    return Padding(
      key: ValueKey('resource-comment-${comment.id}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                comment.author.isEmpty ? '玩家' : comment.author,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (comment.isPinned) const Text('置顶'),
              if (comment.isHot) const Text('热门'),
              if (comment.isDeveloper) const Text('开发者'),
              if (comment.rating case final double rating)
                if (rating > 0) Text('★ ${rating.toStringAsFixed(1)} 分'),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: 3),
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(date),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(comment.text.isEmpty ? '未填写评论内容' : comment.text),
          if (comment.likes != null || (comment.replyCount ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (comment.likes != null)
                  '${_number.format(comment.likes)} 人点赞',
                if ((comment.replyCount ?? 0) > 0)
                  '${_number.format(comment.replyCount)} 条回复',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          const OreDivider(),
        ],
      ),
    );
  }

  Widget _commentsContent(LeaderboardResourceDetail detail) {
    final comments = _comments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ratingSummary(detail),
        if (widget.entry.isDesktop)
          const Text('当前公开接口暂不提供端游评论与评分')
        else ...[
          if (comments != null) ...[
            Text(
              comments.total == null
                  ? '最新评论'
                  : '最新评论 · ${_number.format(comments.total)} 条主评论',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (comments.comments.isEmpty)
              const Text('暂无评论')
            else
              for (final comment in comments.comments) _comment(comment),
          ],
          if (_commentsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: OreLoadingIndicator(size: 24)),
            )
          else if (_commentsError != null) ...[
            Text(_commentsError!),
            const SizedBox(height: 8),
            OreButton(
              onPressed: () => _loadComments(more: comments != null),
              child: const Text('重试加载评论'),
            ),
          ] else if (comments?.hasMore == true)
            OreButton(
              onPressed: () => _loadComments(more: true),
              child: const Text('加载更多评论'),
            ),
        ],
      ],
    );
  }

  Widget _content(LeaderboardResourceDetail detail) =>
      _showComments ? _commentsContent(detail) : _introContent(detail);

  Widget _introContent(LeaderboardResourceDetail detail) {
    if (detail.description.isEmpty) return const Text('暂无资源介绍');
    if (detail.isDesktop) return Text(detail.description);
    return HtmlWidget(
      detail.description,
      onTapUrl: _openLink,
      onLoadingBuilder: (_, _, _) =>
          const Center(child: OreLoadingIndicator(size: 24)),
      onErrorBuilder: (_, _, _) => const Text('内容暂时无法加载'),
      customStylesBuilder: (element) => element.localName == 'img'
          ? {'max-width': '100%', 'height': 'auto'}
          : null,
    );
  }

  Widget _scrollPane({Key? key, required Widget child}) =>
      _LeaderboardDetailScrollPane(key: key, child: child);

  Widget _body(LeaderboardResourceDetail? detail) {
    if (_loading || _error != null || detail == null) {
      return _scrollPane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: OreLoadingIndicator()),
              )
            else if (_error != null) ...[
              Text(_error!),
              const SizedBox(height: 12),
              OreButton(onPressed: _load, child: const Text('重试')),
            ],
            const SizedBox(height: 12),
            _resourceId(),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth >= 720 &&
            constraints.maxHeight >= 250 * textScale &&
            detail.images.isNotEmpty) {
          return SizedBox(
            key: const ValueKey('resource-detail-columns'),
            height: min(400, constraints.maxHeight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: constraints.maxWidth * .38,
                  child: _scrollPane(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _images(detail.images),
                        const SizedBox(height: 8),
                        _componentCode(detail),
                        const SizedBox(height: 6),
                        _resourceId(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OreSelectionArea(child: _facts(detail)),
                      const OreDivider(),
                      const SizedBox(height: 12),
                      _contentTabs(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SizedBox(
                          key: ValueKey(
                            _showComments
                                ? 'resource-comments-scroll'
                                : 'resource-intro-scroll',
                          ),
                          width: double.infinity,
                          child: _scrollPane(child: _content(detail)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _contentTabs(),
            const SizedBox(height: 12),
            Flexible(
              child: _scrollPane(
                key: ValueKey(
                  _showComments
                      ? 'resource-comments-scroll'
                      : 'resource-intro-scroll',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_showComments) ...[
                      _facts(detail),
                      _componentCode(detail),
                      const SizedBox(height: 8),
                      const OreDivider(),
                      const SizedBox(height: 12),
                      if (detail.images.isNotEmpty) ...[
                        _images(detail.images),
                        const SizedBox(height: 12),
                      ],
                    ],
                    _content(detail),
                    const SizedBox(height: 16),
                    _resourceId(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final detail = _detail;
    final name = detail?.name.isNotEmpty == true ? detail!.name : entry.name;
    final author = detail?.author.isNotEmpty == true
        ? detail!.author
        : entry.author;
    final icon = detail?.iconUrl ?? entry.icon;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return OreDialog(
      maxWidth: wide ? 920 : 620,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: wide ? 580 : 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon?.isNotEmpty == true) ...[
                    SizedBox.square(
                      key: const ValueKey('resource-title-icon'),
                      dimension: wide ? 64 : 48,
                      child: _image(icon!, size: wide ? 64 : 48, label: '资源图标'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          namesRoute: true,
                          label: '资源详情',
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontSize: wide ? 22 : 18),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          [
                            entry.isDesktop ? '电脑版' : '手机版',
                            if (author.isNotEmpty) author,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (entry.rank > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${leaderboardTypes[entry.type]} #${entry.rank}${entry.metric.isEmpty ? '' : ' · ${entry.metric}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  OreIconButton(
                    tooltip: '关闭资源详情',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const OreDivider(),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 18),
                child: _body(detail),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Each responsive pane owns its controller so an outgoing layout cannot
/// remain attached to the incoming layout's scrollbar during a resize.
class _LeaderboardDetailScrollPane extends StatefulWidget {
  const _LeaderboardDetailScrollPane({super.key, required this.child});
  final Widget child;

  @override
  State<_LeaderboardDetailScrollPane> createState() =>
      _LeaderboardDetailScrollPaneState();
}

class _LeaderboardDetailScrollPaneState
    extends State<_LeaderboardDetailScrollPane> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    child: SingleChildScrollView(
      controller: _controller,
      padding: const EdgeInsets.only(right: 10),
      child: OreSelectionArea(child: widget.child),
    ),
  );
}
