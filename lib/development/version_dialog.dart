import '../ui/ore_material.dart';
import 'launcher_service.dart';
import 'mcs_api.dart';

/// Installed versions and the complete official download catalog are separate
/// views. Installing another version does not change the active game.
class DevelopmentVersionDialog extends StatefulWidget {
  const DevelopmentVersionDialog({
    super.key,
    required this.launcher,
    required this.onImport,
    this.onLogin,
    this.downloads = false,
  });
  final DevelopmentLauncher launcher;
  final Future<void> Function() onImport;
  final Future<void> Function()? onLogin;
  final bool downloads;
  @override
  State<DevelopmentVersionDialog> createState() =>
      _DevelopmentVersionDialogState();
}

class _DevelopmentVersionDialogState extends State<DevelopmentVersionDialog> {
  late int _tab = widget.downloads ? 1 : 0;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _architecture = 'x64';
  String _channel = 'all';
  String? _error;
  bool get _blocked => widget.launcher.busy || widget.launcher.running;

  @override
  void initState() {
    super.initState();
    if (widget.launcher.catalog == null &&
        widget.launcher.loggedIn &&
        !_blocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(widget.launcher.queryVersions);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Widget _button(String label, VoidCallback? action, {bool primary = false}) =>
      OreButton(
        size: OreButtonSize.sm,
        variant: primary
            ? OreButtonVariant.primary
            : OreButtonVariant.secondary,
        onPressed: action,
        child: Text(label),
      );

  String _label(
    String version,
    GameArchitecture architecture,
    List<GameChannel> channels,
    GameClientType clientType,
  ) => [
    if (architecture != GameArchitecture.unknown) architecture.label,
    if (clientType == GameClientType.haldra) '渲染龙客户端',
    channels.isEmpty
        ? '其他版本'
        : channels.map((channel) => channel.label).join(' / '),
    if (version == widget.launcher.selectedVersion) '当前使用',
  ].join(' · ');

  Widget _installedRow(LocalGame game) {
    final package = widget.launcher.availableGames
        .where((package) => package.version == game.version)
        .firstOrNull;
    return _row(
      game.version,
      _label(
        game.version,
        package?.architecture ?? game.architecture,
        package?.channels ?? game.channels,
        package?.clientType ?? game.clientType,
      ),
      installed: true,
    );
  }

  Widget _row(String version, String subtitle, {required bool installed}) =>
      OreListTile(
        dense: true,
        title: Text(version),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: _button(
          installed
              ? version == widget.launcher.selectedVersion
                    ? '当前使用'
                    : '使用此版本'
              : '安装',
          _blocked ||
                  (installed && version == widget.launcher.selectedVersion) ||
                  (!installed && !widget.launcher.loggedIn)
              ? null
              : () => _run(() async {
                  if (installed) {
                    await widget.launcher.chooseVersion(version);
                    if (mounted && widget.launcher.error == null) {
                      Navigator.of(context).pop();
                    }
                  } else {
                    await widget.launcher.installVersion(version);
                  }
                }),
          primary: !installed,
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.launcher,
    builder: (context, _) {
      final launcher = widget.launcher;
      final query = _search.text.trim().toLowerCase();
      final versions = launcher.availableGames
          .where(
            (package) =>
                package.version.contains(query) &&
                (_architecture == 'all' ||
                    package.architecture.name == _architecture) &&
                (_channel == 'all' ||
                    (_channel == 'other'
                        ? package.channels.isEmpty
                        : package.channels.any(
                            (channel) => channel.name == _channel,
                          ))),
          )
          .toList();
      final local = launcher.games
          .where((game) => game.version.contains(query))
          .toList();
      final error = _error ?? launcher.error;
      return OreDialog(
        maxWidth: 800,
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height * .82).clamp(300, 700),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '游戏版本管理',
                  style: OreTheme.of(context).typography.choiceTitle,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OreChoiceButtons(
                      items: [
                        Text('已安装 (${launcher.games.length})'),
                        Text('可下载 (${launcher.availableGames.length})'),
                      ],
                      selectedIndex: _tab,
                      onChanged: (value) => setState(() => _tab = value),
                    ),
                    _button(
                      '刷新清单',
                      _blocked || !launcher.loggedIn
                          ? null
                          : () => _run(launcher.queryVersions),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OreTextField(
                  controller: _search,
                  hintText: '搜索版本号',
                  onChanged: (_) => setState(() {}),
                ),
                if (_tab == 1) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OreDropdownButton<String>(
                          key: const ValueKey('version-architecture-filter'),
                          size: OreButtonSize.sm,
                          value: _architecture,
                          items: const [
                            OreDropdownItem(value: 'all', child: Text('全部架构')),
                            OreDropdownItem(value: 'x64', child: Text('x64')),
                            OreDropdownItem(value: 'x86', child: Text('x86')),
                          ],
                          onChanged: (value) =>
                              setState(() => _architecture = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OreDropdownButton<String>(
                          key: const ValueKey('version-channel-filter'),
                          size: OreButtonSize.sm,
                          value: _channel,
                          items: [
                            const OreDropdownItem(
                              value: 'all',
                              child: Text('全部渠道'),
                            ),
                            for (final channel in GameChannel.values)
                              OreDropdownItem(
                                value: channel.name,
                                child: Text(channel.label),
                              ),
                            const OreDropdownItem(
                              value: 'other',
                              child: Text('其他版本'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _channel = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '当前筛选：${versions.length} 个版本',
                    style: OreTheme.of(context).typography.caption,
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: OreScrollbar(
                    controller: _scroll,
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.only(right: 14),
                      children: [
                        if (_tab == 0)
                          for (final game in local) _installedRow(game),
                        if (_tab == 1)
                          for (final package in versions)
                            _row(
                              package.version,
                              [
                                _label(
                                  package.version,
                                  package.architecture,
                                  package.channels,
                                  package.clientType,
                                ),
                                if (package.size > 0)
                                  '清单大小 ${(package.size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                                if (launcher.games.any(
                                  (game) => game.version == package.version,
                                ))
                                  '已安装',
                              ].join(' · '),
                              installed: launcher.games.any(
                                (game) => game.version == package.version,
                              ),
                            ),
                        if ((_tab == 0 && local.isEmpty) ||
                            (_tab == 1 && versions.isEmpty))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              _tab == 0
                                  ? '没有匹配的已安装版本。'
                                  : launcher.catalog == null
                                  ? launcher.busy
                                        ? '正在读取官方版本清单…'
                                        : '登录后刷新官方清单，查看可下载版本。'
                                  : '没有符合筛选条件的版本。',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 64,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (launcher.busy && !launcher.running)
                          Text(launcher.progress?.message ?? '正在处理…'),
                        if (error != null)
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (launcher.notice != null) Text(launcher.notice!),
                        Text(
                          '多个版本独立安装；安装新版本后，在启动区选择要使用的版本。',
                          style: OreTheme.of(context).typography.caption,
                        ),
                        if ((launcher.catalog?.skippedEntries ?? 0) > 0)
                          Text(
                            '${launcher.catalog!.skippedEntries} 个下载描述无效的条目已略过。',
                          ),
                      ],
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (!launcher.loggedIn && widget.onLogin != null)
                      _button(
                        '前往登录',
                        _blocked
                            ? null
                            : () => _run(() async {
                                await widget.onLogin!();
                                await launcher.refresh();
                                if (launcher.loggedIn) {
                                  await launcher.queryVersions();
                                }
                              }),
                      ),
                    _button(
                      '导入已有游戏',
                      _blocked
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              widget.onImport();
                            },
                    ),
                    _button('关闭', () => Navigator.of(context).pop()),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
