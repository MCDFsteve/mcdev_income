import 'dart:async';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../ui/ore_material.dart';
import 'development_logs.dart';
import 'development_storage.dart';
import 'log_format.dart';
import 'log_save_path.dart';

class DevelopmentLogDialog extends StatefulWidget {
  const DevelopmentLogDialog({
    super.key,
    required this.storage,
    this.preferredPath,
    this.store,
    this.savePath,
  });
  final DevelopmentStorage storage;
  final String? preferredPath;
  final DevelopmentLogStore? store;
  final Future<String?> Function(String fileName)? savePath;

  @override
  State<DevelopmentLogDialog> createState() => _DevelopmentLogDialogState();
}

class _DevelopmentLogDialogState extends State<DevelopmentLogDialog> {
  late final DevelopmentLogController _logs;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  DevelopmentLogLevel? _level;
  bool _follow = true;
  bool _exporting = false;
  bool _jumping = false;
  bool _userScrollActive = false;
  String? _message;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _logs = DevelopmentLogController(
      widget.store ?? openDevelopmentLogs(widget.storage.paths.logs),
      preferredPath: widget.preferredPath,
    )..addListener(_changed);
    unawaited(_logs.refresh());
    _timer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      unawaited(_logs.refresh());
    });
  }

  void _changed() {
    if (!mounted) return;
    final changed = _revision != _logs.revision;
    _revision = _logs.revision;
    setState(() {});
    if (changed && _follow) _jumpToLatest();
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_follow) return;
      _jumping = true;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      _jumping = false;
      // Wrapped, virtualized rows can change the estimated extent after a jump.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _follow && _scroll.hasClients) {
          _jumping = true;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
          _jumping = false;
        }
      });
    });
  }

  bool _userScrolled(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _userScrollActive = notification.direction != ScrollDirection.idle;
    }
    if (_follow &&
        !_jumping &&
        (_userScrollActive ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null)) &&
        notification.metrics.extentAfter > 16) {
      setState(() => _follow = false);
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logs.removeListener(_changed);
    _logs.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<DevelopmentLogEntry> get _visible => _logs.filter(_search.text, _level);
  String _text(List<DevelopmentLogEntry> entries) =>
      entries.map((line) => line.text).join('\n');

  Future<void> _copy(String text, String message) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) setState(() => _message = '复制失败：$e');
    }
  }

  Future<void> _export({required bool filtered}) async {
    final source = _logs.selectedPath;
    if (source == null || _exporting) return;
    // Freeze the selected source and filter result before showing the save panel.
    final text = _text(_visible);
    final filename = filtered
        ? '${p.basenameWithoutExtension(source)}-filtered.log'
        : p.basename(source);
    setState(() {
      _exporting = true;
      _message = null;
    });
    try {
      final destination =
          await (widget.savePath?.call(filename) ??
              chooseDevelopmentLogExport(filename, filtered: filtered));
      if (destination == null || destination.isEmpty) return;
      if (filtered) {
        await _logs.store.exportText(source, destination, text);
      } else {
        await _logs.store.exportOriginal(source, destination);
      }
      if (mounted) setState(() => _message = '已导出：$destination');
    } catch (e) {
      if (mounted) setState(() => _message = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _button(String label, VoidCallback? action) => OreButton(
    size: OreButtonSize.sm,
    variant: OreButtonVariant.secondary,
    onPressed: action,
    child: Text(label),
  );

  Color _levelColor(DevelopmentLogLevel level, bool dark, Color fallback) =>
      switch (level) {
        DevelopmentLogLevel.error =>
          dark ? const Color(0xffff8b8b) : const Color(0xffb42323),
        DevelopmentLogLevel.warning =>
          dark ? const Color(0xffffd782) : const Color(0xff885700),
        DevelopmentLogLevel.info =>
          dark ? const Color(0xffa3dca3) : const Color(0xff2f6b36),
        DevelopmentLogLevel.debug =>
          dark ? const Color(0xffc1b2ef) : const Color(0xff71469c),
        _ => fallback,
      };

  Color _tokenColor(LogToken token, DevelopmentLogEntry line, bool dark) {
    final muted = OreTheme.of(context).colors.textMuted;
    return switch (token.kind) {
      LogTokenKind.timestamp =>
        dark ? const Color(0xff92a9ba) : const Color(0xff526b7c),
      LogTokenKind.level => _levelColor(line.level, dark, muted),
      LogTokenKind.string =>
        dark ? const Color(0xffb6d798) : const Color(0xff4c6d27),
      LogTokenKind.path || LogTokenKind.key =>
        dark ? const Color(0xff8acbee) : const Color(0xff17638b),
      LogTokenKind.number =>
        dark ? const Color(0xffe9c28f) : const Color(0xff885723),
      LogTokenKind.keyword =>
        dark ? const Color(0xffcbb0f2) : const Color(0xff71469c),
      _ => _levelColor(
        line.level,
        dark,
        OreTheme.of(context).colors.textPrimary,
      ),
    };
  }

  Widget _line(DevelopmentLogEntry line) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ore = OreTheme.of(context);
    // A pathological single-line dump remains copyable/exportable in full.
    final display = line.text.length > 12000
        ? '${line.text.substring(0, 12000)} … [本行过长，复制可查看完整内容]'
        : line.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '${line.number}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontFamilyFallback: ['monospace'],
                fontSize: 11,
                height: 1.6,
                color: ore.colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (final token in highlightLogLine(display))
                    TextSpan(
                      text: token.text,
                      style: TextStyle(color: _tokenColor(token, line, dark)),
                    ),
                ],
              ),
              key: ValueKey('log-line-${line.number}'),
              style: TextStyle(
                fontFamily: 'Menlo',
                fontFamilyFallback: ['monospace', 'PingFang SC'],
                fontSize: 12,
                height: 1.5,
                color: ore.colors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            height: 24,
            child: OreIconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: '复制第 ${line.number} 行',
              onPressed: () => _copy(line.text, '已复制第 ${line.number} 行。'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final ore = OreTheme.of(context);
    return OreDialog(
      maxWidth: 1100,
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * .88).clamp(280, 760),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('游戏日志', style: ore.typography.choiceTitle),
                  ),
                  OreIconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: '打开日志目录',
                    onPressed: () async {
                      try {
                        await widget.storage.reveal(widget.storage.paths.logs);
                      } catch (e) {
                        if (mounted) setState(() => _message = '打开目录失败：$e');
                      }
                    },
                  ),
                  OreIconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭日志',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OreDropdownButton<String>(
                      key: const ValueKey('log-file'),
                      size: OreButtonSize.sm,
                      value: _logs.selectedPath,
                      hint: const Text('选择历史日志'),
                      items: [
                        for (final file in _logs.files)
                          OreDropdownItem(
                            value: file.path,
                            child: Text(
                              file.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _exporting ? null : _logs.select,
                    ),
                  ),
                  OreIconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新日志',
                    onPressed: () => _logs.refresh(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OreTextField(
                      controller: _search,
                      hintText: '筛选关键词（不区分大小写）',
                      onChanged: (_) {
                        setState(() {});
                        if (_follow) _jumpToLatest();
                      },
                      suffix: OreIconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: '清除日志关键词',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                          if (_follow) _jumpToLatest();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: OreDropdownButton<String>(
                      key: const ValueKey('log-level'),
                      size: OreButtonSize.sm,
                      value: _level?.name ?? 'all',
                      items: [
                        const OreDropdownItem(
                          value: 'all',
                          child: Text('全部级别'),
                        ),
                        for (final level in DevelopmentLogLevel.values)
                          OreDropdownItem(
                            value: level.name,
                            child: Text(level.label),
                          ),
                      ],
                      onChanged: (value) {
                        setState(
                          () => _level = DevelopmentLogLevel.values
                              .where((level) => level.name == value)
                              .firstOrNull,
                        );
                        if (_follow) _jumpToLatest();
                      },
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OreCheckbox(
                        key: const ValueKey('log-auto-scroll'),
                        value: _follow,
                        label: const Text('自动滚动'),
                        onChanged: (value) {
                          setState(() => _follow = value ?? false);
                          if (_follow) _jumpToLatest();
                        },
                      ),
                      OreIconButton(
                        icon: const Icon(Icons.vertical_align_bottom, size: 18),
                        tooltip: '跳到最新并开启自动滚动',
                        onPressed: () {
                          setState(() => _follow = true);
                          _jumpToLatest();
                        },
                      ),
                    ],
                  ),
                  Text(
                    '${visible.length} / ${_logs.entries.length} 行 · 实时更新',
                    style: ore.typography.caption,
                  ),
                ],
              ),
              if (_logs.tailOnly)
                Text(
                  '仅显示最近日志；关键词和级别筛选作用于已加载内容。导出原始日志可保留完整文件。',
                  style: ore.typography.caption,
                ),
              const SizedBox(height: 4),
              Expanded(
                child: OreCard(
                  color: ore.colors.surfaceDark,
                  padding: const EdgeInsets.all(6),
                  child: _logs.loading
                      ? const Center(child: OreLoadingIndicator())
                      : visible.isEmpty
                      ? Center(
                          child: Text(
                            _logs.selectedPath == null
                                ? '暂无游戏日志。启动测试后会在这里显示。'
                                : _logs.entries.isEmpty
                                ? '等待游戏输出日志…'
                                : '没有符合筛选条件的日志。',
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: _userScrolled,
                          child: OreScrollbar(
                            controller: _scroll,
                            child: OreSelectionArea(
                              child: ListView.builder(
                                key: const ValueKey('log-entries'),
                                controller: _scroll,
                                padding: const EdgeInsets.only(right: 14),
                                itemCount: visible.length,
                                itemBuilder: (context, index) =>
                                    _line(visible[index]),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _logs.error ?? _message ?? '向上滚动会暂停自动滚动；日志继续接收。可拖选文本或复制单行。',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ore.typography.caption.copyWith(
                      color: _logs.error == null
                          ? ore.colors.textMuted
                          : ore.colors.danger,
                    ),
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  _button(
                    '复制筛选结果',
                    visible.isEmpty
                        ? null
                        : () => _copy(
                            _text(visible),
                            '已复制 ${visible.length} 行筛选结果。',
                          ),
                  ),
                  _button(
                    '导出筛选结果',
                    visible.isEmpty || _exporting
                        ? null
                        : () => _export(filtered: true),
                  ),
                  _button(
                    '导出原始日志',
                    _logs.selectedPath == null || _exporting
                        ? null
                        : () => _export(filtered: false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
