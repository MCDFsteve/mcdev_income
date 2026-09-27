part of '../main.dart';

class MailboxPage extends StatefulWidget {
  const MailboxPage({super.key, this.apiFactory, this.onRead});
  final McDevApi Function()? apiFactory;
  final VoidCallback? onRead;
  @override
  State<MailboxPage> createState() => _MailboxPageState();
}

class _MailboxPageState extends State<MailboxPage> {
  final _search = TextEditingController();
  final _listScroll = ScrollController(), _detailScroll = ScrollController();
  String _type = '', _query = '';
  bool _unreadOnly = false, _loading = true, _detailLoading = false;
  String? _error, _detailError;
  MailPageData? _page;
  MailItem? _selected, _detail;
  int _start = 0, _listRequest = 0, _detailRequest = 0;
  static const _span = 30;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  Future<McDevApi> _openApi() async {
    if (widget.apiFactory != null) return widget.apiFactory!();
    final cookie = await LoginCookieHelper.buildCookieHeader();
    if (cookie.isEmpty) throw StateError('请先到“设置”里登录后查看邮件。');
    return McDevApi(cookie: cookie, category: 'pe');
  }

  Future<void> _load({bool reset = false}) async {
    final request = ++_listRequest;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _start = 0;
        _selected = null;
        _detail = null;
        _detailRequest++;
        _detailLoading = false;
      }
    });
    McDevApi? api;
    try {
      api = await _openApi();
      final page = await api.fetchMail(
        start: _start,
        span: _span,
        type: _type,
        haveRead: _unreadOnly ? false : null,
        query: _query,
      );
      if (!mounted || request != _listRequest) return;
      setState(() => _page = page);
      if (_listScroll.hasClients) _listScroll.jumpTo(0);
    } catch (error) {
      if (mounted && request == _listRequest) {
        setState(() => _error = error.toString());
      }
    } finally {
      api?.close();
      if (mounted && request == _listRequest) setState(() => _loading = false);
    }
  }

  Future<void> _read(MailItem mail) async {
    final request = ++_detailRequest;
    setState(() {
      _selected = mail;
      _detail = null;
      _detailLoading = true;
      _detailError = null;
    });
    McDevApi? api;
    try {
      api = await _openApi();
      final detail = await api.fetchMailDetail(mail.id);
      widget.onRead?.call();
      if (!mounted) return;
      final page = _page;
      if (page != null) {
        final wasUnread = page.items.any(
          (item) => item.id == mail.id && !item.isRead,
        );
        setState(
          () => _page = MailPageData(
            items: [
              for (final item in page.items)
                item.id == mail.id ? item.asRead() : item,
            ],
            total: page.total,
            unread: max(0, page.unread - (wasUnread ? 1 : 0)),
          ),
        );
      }
      if (request != _detailRequest) return;
      setState(() => _detail = MailItem({...mail.raw, ...detail.raw}));
      if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
    } catch (error) {
      if (mounted && request == _detailRequest) {
        setState(() => _detailError = error.toString());
      }
    } finally {
      api?.close();
      if (mounted && request == _detailRequest) {
        setState(() => _detailLoading = false);
      }
    }
  }

  String _time(MailItem mail) => mail.time == null
      ? ''
      : DateFormat('yyyy-MM-dd HH:mm').format(mail.time!);
  void _goBack(bool wide) {
    if (!wide && _selected != null) {
      setState(() {
        _selected = null;
        _detail = null;
        _detailRequest++;
        _detailLoading = false;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _failure(String error, VoidCallback retry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
          OreButton(onPressed: retry, child: const Text('重试')),
        ],
      ),
    ),
  );
  Widget _filters() => OreStrip(
    tone: OreStripTone.dark,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onSubmitted: (_) {
                    _query = _search.text.trim();
                    _load(reset: true);
                  },
                  decoration: const InputDecoration(hintText: '搜索邮件标题'),
                ),
              ),
              const SizedBox(width: 8),
              OreIconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索邮件',
                onPressed: () {
                  _query = _search.text.trim();
                  _load(reset: true);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _type,
                  isExpanded: true,
                  items: [
                    for (final entry in mailboxTypes.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _type = value;
                      _load(reset: true);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              OreButton(
                size: OreButtonSize.sm,
                variant: _unreadOnly
                    ? OreButtonVariant.primary
                    : OreButtonVariant.secondary,
                onPressed: () {
                  _unreadOnly = !_unreadOnly;
                  _load(reset: true);
                },
                child: const Text('只看未读'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _list() {
    final page = _page;
    return Column(
      children: [
        _filters(),
        Expanded(
          child: _loading
              ? const Center(child: OreLoadingIndicator())
              : _error != null
              ? _failure(_error!, () => _load())
              : page == null || page.items.isEmpty
              ? const Center(child: Text('暂无邮件'))
              : Scrollbar(
                  controller: _listScroll,
                  child: ListView.separated(
                    controller: _listScroll,
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const OreDivider(),
                    itemBuilder: (context, index) {
                      final mail = page.items[index];
                      return Semantics(
                        button: true,
                        label: '${mail.isRead ? '已读' : '未读'}邮件：${mail.title}',
                        child: OreListTile(
                          key: ValueKey('mail-${mail.id}'),
                          selected: _selected?.id == mail.id,
                          leading: Icon(
                            mail.isRead
                                ? Icons.drafts_outlined
                                : Icons.mark_email_unread_outlined,
                            size: 20,
                            color: mail.isRead
                                ? OreTheme.of(context).colors.textMuted
                                : OreTheme.of(context).colors.success,
                          ),
                          title: Text(
                            mail.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: mail.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${mail.typeLabel} · ${_time(mail)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _read(mail),
                        ),
                      );
                    },
                  ),
                ),
        ),
        if (!_loading && _error == null && page != null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '共 ${page.total} 封 · 第 ${_start ~/ _span + 1} 页',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                OreIconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一页邮件',
                  onPressed: _start > 0
                      ? () {
                          _start = max(0, _start - _span);
                          _load();
                        }
                      : null,
                ),
                OreIconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一页邮件',
                  onPressed: _start + (page.items.length) < page.total
                      ? () {
                          _start += _span;
                          _load();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<bool> _openLink(String value) async {
    final url = Uri.tryParse(value);
    if (url == null) return false;
    final resolved = Uri.parse('https://mcdev.webapp.163.com/').resolveUri(url);
    if (!['http', 'https'].contains(resolved.scheme)) return false;
    try {
      final opened = await launchUrl(
        resolved,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) showOreToast(context, const Text('无法打开链接'));
      return opened;
    } catch (_) {
      if (mounted) showOreToast(context, const Text('无法打开链接'));
      return false;
    }
  }

  Widget _body() {
    if (_selected == null) return const Center(child: Text('选择一封邮件查看内容'));
    if (_detailLoading) return const Center(child: OreLoadingIndicator());
    if (_detailError != null) {
      return _failure(_detailError!, () => _read(_selected!));
    }
    final mail = _detail;
    if (mail == null) return const SizedBox.shrink();
    final html = RegExp(r'<[a-zA-Z][^>]*>').hasMatch(mail.detail);
    final attachments = ResourceOptions.maps(
      mail.raw['extra_list'],
    ).where((item) => item['file_url']?.toString().isNotEmpty == true).toList();
    return Scrollbar(
      controller: _detailScroll,
      child: SingleChildScrollView(
        controller: _detailScroll,
        padding: const EdgeInsets.all(24),
        child: OreSelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mail.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '${mail.typeLabel} · ${_time(mail)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              const OreDivider(),
              const SizedBox(height: 16),
              if (html)
                HtmlWidget(
                  mail.detail,
                  onTapUrl: _openLink,
                  onLoadingBuilder: (_, _, _) =>
                      const Center(child: OreLoadingIndicator(size: 24)),
                  customStylesBuilder: (element) => element.localName == 'img'
                      ? {'max-width': '100%', 'height': 'auto'}
                      : null,
                )
              else
                Text(mail.detail.isEmpty ? '这封邮件没有正文。' : mail.detail),
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 24),
                const OreDivider(),
                const SizedBox(height: 12),
                const Text('附件'),
                for (final attachment in attachments)
                  OreListTile(
                    leading: const Icon(Icons.attach_file),
                    title: Text(
                      '${attachment['file_name'] ?? '下载附件'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _openLink('${attachment['file_url']}'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OreDialog(
      maxWidth: 1080,
      insetPadding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return PopScope(
            canPop: wide || _selected == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _goBack(wide);
            },
            child: SizedBox(
              width: 1080,
              height: min(800, MediaQuery.sizeOf(context).height * .9),
              child: Column(
                children: [
                  buildOreAppBar(
                    context,
                    title: '邮件',
                    actions: [
                      OreIconButton(
                        icon: const Icon(Icons.refresh),
                        color: Colors.white,
                        tooltip: '刷新邮件',
                        onPressed: _loading
                            ? null
                            : () {
                                _load();
                                widget.onRead?.call();
                              },
                      ),
                      OreIconButton(
                        icon: Icon(
                          !wide && _selected != null
                              ? Icons.arrow_back
                              : Icons.close,
                        ),
                        color: Colors.white,
                        tooltip: !wide && _selected != null ? '返回邮件列表' : '关闭邮件',
                        onPressed: () => _goBack(wide),
                      ),
                    ],
                  ),
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 360, child: _list()),
                              SizedBox(
                                width: 2,
                                child: ColoredBox(
                                  color: OreTheme.of(context).colors.border,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Expanded(child: _body()),
                            ],
                          )
                        : _selected == null
                        ? _list()
                        : _body(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
