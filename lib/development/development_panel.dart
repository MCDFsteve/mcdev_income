import 'package:file_picker/file_picker.dart';
import '../core/preferences.dart';
import 'launch_tabs.dart';
import '../storage/app_preferences.dart';
import '../ui/ore_material.dart';
import 'development_storage.dart';
import 'launcher_service.dart';
import 'log_dialog.dart';
import 'project_icon.dart';
import 'version_dialog.dart';

class DevelopmentEnvironmentPanel extends StatefulWidget {
  const DevelopmentEnvironmentPanel({
    super.key,
    required this.storage,
    this.onActivity,
    this.launcherFactory,
    this.sessionLauncherFactory,
    this.preferences,
    this.cookieProvider,
    this.onLogin,
    this.storageSection,
    this.statusSection,
  });
  final DevelopmentStorage storage;
  final Future<String> Function()? cookieProvider;
  final Future<void> Function()? onLogin;
  final ValueChanged<bool>? onActivity;
  final Future<DevelopmentLauncher> Function()? launcherFactory;
  final Future<DevelopmentLauncher> Function(String id)? sessionLauncherFactory;
  final PreferenceStore? preferences;
  final Widget? storageSection;
  final Widget? statusSection;
  @override
  State<DevelopmentEnvironmentPanel> createState() =>
      _DevelopmentEnvironmentPanelState();
}

class _DevelopmentEnvironmentPanelState
    extends State<DevelopmentEnvironmentPanel> {
  DevelopmentTabsStore? _store;
  final _launchers = <String, DevelopmentLauncher>{};
  final _closing = <String>{};
  final _tabScroll = ScrollController();
  bool _adding = false;
  bool _loading = true;
  bool _activity = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<DevelopmentLauncher> _open(String id) async {
    if (widget.sessionLauncherFactory != null) {
      return widget.sessionLauncherFactory!(id);
    }
    if (widget.launcherFactory != null) return widget.launcherFactory!();
    return openDevelopmentLauncher(
      widget.storage,
      _store!.preferences!,
      cookieProvider: widget.cookieProvider,
      sessionId: id,
    );
  }

  Future<void> _load() async {
    try {
      final preferences =
          widget.preferences ??
          (widget.launcherFactory != null ||
                  widget.sessionLauncherFactory != null
              ? null
              : await AppPreferences.getInstance());
      final store = DevelopmentTabsStore(preferences, widget.storage.paths.root)
        ..load();
      _store = store;
      for (final tab in store.tabs) {
        final launcher = await _open(tab.id);
        if (!mounted) {
          launcher.dispose();
          return;
        }
        _launchers[tab.id] = launcher;
        launcher.addListener(_onChanged);
      }
      if (mounted) _onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged() {
    if (!mounted) return;
    final active = _launchers.values.any((item) => item.busy || item.running);
    if (active != _activity) {
      _activity = active;
      widget.onActivity?.call(active);
    }
    setState(() {});
  }

  Future<void> _save() async {
    try {
      await _store!.save();
    } catch (e) {
      if (mounted) setState(() => _error = '无法保存测试标签：$e');
    }
  }

  Future<void> _select(String id) async {
    if (_store!.activeId == id) return;
    setState(() => _store!.activeId = id);
    final launcher = _launchers[id]!;
    await _save();
    if (!mounted || _launchers[id] != launcher) return;
    if (!launcher.busy && !launcher.running) {
      try {
        await launcher.refresh();
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    final previous = _store!.activeId;
    final tab = _store!.add();
    try {
      final launcher = await _open(tab.id);
      if (!mounted) {
        launcher.dispose();
        return;
      }
      _launchers[tab.id] = launcher;
      launcher.addListener(_onChanged);
      await _save();
    } catch (e) {
      _store!.remove(tab.id);
      _store!.activeId = previous;
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _adding = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabScroll.hasClients) {
        _tabScroll.animateTo(
          _tabScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _remove(String id) async {
    if (_adding || _store!.tabs.length <= 1 || _closing.contains(id)) return;
    final launcher = _launchers[id]!;
    if (launcher.running) {
      final confirmed = await showOreDialog<bool>(
        context: context,
        builder: (context) => OreAlertDialog(
          title: const Text('退出游戏并关闭标签？'),
          content: Text(
            '“${launcher.tabTitle}”仍在运行。请先在游戏中保存；关闭标签会请求房主及此页的局域网玩家窗口退出，已有存档会保留。',
          ),
          actions: [
            OreButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('保留标签'),
            ),
            OreButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出并关闭标签'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _closing.add(id));
      try {
        await launcher.stopGame();
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _closing.remove(id));
      }
    }
    if (!mounted) return;
    if (launcher.running || launcher.busy) {
      setState(() => _error = '此标签仍在处理任务，请等待任务结束后再关闭。');
      return;
    }
    if (!_store!.remove(id)) return;
    launcher.removeListener(_onChanged);
    _launchers.remove(id);
    // Dispose after its child is unmounted and has detached its listeners.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => launcher.dispose());
    await _save();
    _onChanged();
  }

  Widget _tabs() {
    final theme = OreTheme.of(context);
    return SizedBox(
      key: const ValueKey('development-test-tabs'),
      height: 44,
      child: Row(
        children: [
          Flexible(
            child: SingleChildScrollView(
              controller: _tabScroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in _store!.tabs)
                    if (_launchers[tab.id] case final launcher?)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Stack(
                            children: [
                              Semantics(
                                button: true,
                                selected: _store!.activeId == tab.id,
                                inMutuallyExclusiveGroup: true,
                                child: OreTooltip(
                                  message: launcher.tabTitle,
                                  child: OreButton(
                                    key: ValueKey('development-tab-${tab.id}'),
                                    size: OreButtonSize.sm,
                                    variant: _store!.activeId == tab.id
                                        ? OreButtonVariant.primary
                                        : OreButtonVariant.secondary,
                                    forcePressed: _store!.activeId == tab.id,
                                    forcePressedKeepsColor: true,
                                    onPressed: () => _select(tab.id),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 190,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (launcher.running ||
                                              launcher.busy) ...[
                                            Icon(
                                              launcher.running
                                                  ? Icons.play_arrow
                                                  : Icons.hourglass_top,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Flexible(
                                            child: Text(
                                              launcher.tabTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_store!.activeId == tab.id)
                                Positioned(
                                  key: ValueKey(
                                    'development-tab-indicator-${tab.id}',
                                  ),
                                  left: 0,
                                  right: 0,
                                  bottom: theme.borderWidth,
                                  height:
                                      theme.borderWidth *
                                      OreTokens.choiceIndicatorHeightUnits,
                                  child: IgnorePointer(
                                    child: Align(
                                      alignment: Alignment.center,
                                      child: FractionallySizedBox(
                                        widthFactor: OreTokens
                                            .choiceIndicatorWidthFactor,
                                        heightFactor: 1,
                                        child: ColoredBox(
                                          color: theme.colors.textInverse,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          OreTooltip(
                            message: _store!.tabs.length == 1
                                ? '至少保留一个测试标签'
                                : '关闭测试标签',
                            child: Semantics(
                              label: '关闭测试标签',
                              button: true,
                              enabled:
                                  !_adding &&
                                  _store!.tabs.length > 1 &&
                                  !_closing.contains(tab.id) &&
                                  (!launcher.busy || launcher.running),
                              child: OreButton(
                                key: ValueKey(
                                  'development-close-tab-${tab.id}',
                                ),
                                size: OreButtonSize.sm,
                                width: OreTokens.controlHeightSm,
                                contentPadding: EdgeInsets.zero,
                                variant: _store!.activeId == tab.id
                                    ? OreButtonVariant.primary
                                    : OreButtonVariant.secondary,
                                forcePressed: _store!.activeId == tab.id,
                                forcePressedKeepsColor: true,
                                onPressed:
                                    _adding ||
                                        _store!.tabs.length <= 1 ||
                                        _closing.contains(tab.id) ||
                                        (launcher.busy && !launcher.running)
                                    ? null
                                    : () => _remove(tab.id),
                                child: const Icon(Icons.close, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                ],
              ),
            ),
          ),
          OreTooltip(
            message: '新建测试标签',
            child: Semantics(
              label: '新建测试标签',
              button: true,
              enabled: !_adding,
              child: OreButton(
                key: const ValueKey('development-add-tab'),
                size: OreButtonSize.sm,
                width: OreTokens.controlHeightSm,
                contentPadding: EdgeInsets.zero,
                onPressed: _adding ? null : _add,
                child: const Icon(Icons.add, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final launcher in _launchers.values) {
      launcher.removeListener(_onChanged);
      launcher.dispose();
    }
    _tabScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (_loading || store == null || _launchers.isEmpty) {
      return Center(
        child: _error == null ? const OreLoadingIndicator() : Text(_error!),
      );
    }
    final visible = store.tabs
        .where((tab) => _launchers.containsKey(tab.id))
        .toList();
    final index = visible.indexWhere((tab) => tab.id == store.activeId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = IndexedStack(
          index: index < 0 ? 0 : index,
          sizing: StackFit.expand,
          children: [
            for (final tab in visible)
              _DevelopmentSessionPanel(
                key: ValueKey(tab.id),
                storage: widget.storage,
                launcher: _launchers[tab.id]!,
                tab: tab,
                onStateChanged: _save,
                onLogin: widget.onLogin,
                storageSection: widget.storageSection,
                statusSection: widget.statusSection,
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tabs(),
            if (_error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  OreIconButton(
                    tooltip: '关闭提示',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (constraints.hasBoundedHeight)
              Expanded(child: content)
            else
              SizedBox(height: 720, child: content),
          ],
        );
      },
    );
  }
}

class _DevelopmentSessionPanel extends StatefulWidget {
  const _DevelopmentSessionPanel({
    super.key,
    required this.storage,
    required this.launcher,
    required this.tab,
    required this.onStateChanged,
    this.onLogin,
    this.storageSection,
    this.statusSection,
  });
  final DevelopmentStorage storage;
  final DevelopmentLauncher launcher;
  final DevelopmentTab tab;
  final VoidCallback onStateChanged;
  final Future<void> Function()? onLogin;
  final Widget? storageSection;
  final Widget? statusSection;
  @override
  State<_DevelopmentSessionPanel> createState() =>
      _DevelopmentSessionPanelState();
}

class _DevelopmentSessionPanelState extends State<_DevelopmentSessionPanel> {
  DevelopmentLauncher get _launcher => widget.launcher;
  String? _error;
  late final TextEditingController _world;
  late final TextEditingController _seed;
  bool _savingWorldMode = false;
  late bool _creative;
  late bool _menuOnly;
  bool _picking = false;
  final _environmentScroll = ScrollController();
  final _projectScroll = ScrollController();
  final _compactProjectScroll = ScrollController();
  final _launchScroll = ScrollController();
  final _pageScroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _world = TextEditingController(text: widget.tab.worldName);
    _seed = TextEditingController(
      text: widget.tab.seed ?? _launcher.newWorldSeed,
    );
    _creative = widget.tab.creative;
    _menuOnly = widget.tab.menuOnly;
    _world.addListener(_saveOptions);
    _seed.addListener(_saveOptions);
  }

  void _saveOptions() {
    widget.tab.worldName = _world.text;
    widget.tab.seed = _seed.text;
    widget.tab.creative = _creative;
    widget.tab.menuOnly = _menuOnly;
    widget.onStateChanged();
  }

  @override
  void dispose() {
    _world.removeListener(_saveOptions);
    _seed.removeListener(_saveOptions);
    _world.dispose();
    _seed.dispose();
    _environmentScroll.dispose();
    _projectScroll.dispose();
    _compactProjectScroll.dispose();
    _launchScroll.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool mod, required bool archive}) async {
    setState(() => _picking = true);
    try {
      final path = archive
          ? (await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['mcpack', 'mcaddon', 'zip'],
            ))?.files.single.path
          : await FilePicker.platform.getDirectoryPath(
              dialogTitle: mod ? '选择模组项目或包目录' : '选择完整游戏版本目录',
            );
      if (path != null && mounted) {
        await (mod ? _launcher.importMods(path) : _launcher.importGame(path));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() => _error = null);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Widget _card(String title, List<Widget> children, {Widget? trailing}) =>
      OreCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: OreTheme.of(context).typography.choiceTitle,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  Widget _button(String text, VoidCallback? action, {bool primary = false}) =>
      OreButton(
        size: OreButtonSize.sm,
        variant: primary
            ? OreButtonVariant.primary
            : OreButtonVariant.secondary,
        onPressed: action,
        child: Text(text),
      );
  Widget _actions(List<Widget> buttons) =>
      Wrap(spacing: 8, runSpacing: 8, children: buttons);
  Widget _hint(String text) => Text(
    text,
    style: OreTheme.of(
      context,
    ).typography.caption.copyWith(color: OreTheme.of(context).colors.textMuted),
  );

  Widget _wineCard(DevelopmentLauncher launcher, bool blocked) =>
      _card('Wine 运行环境', [
        Text(
          launcher.runtimeReady
              ? 'Wine 11.0_1 · 启动补丁已就绪'
              : '按需下载 Wine 与启动补丁，约 185 MB。',
        ),
        const SizedBox(height: 10),
        _actions([
          _button(
            launcher.runtimeReady ? '检查运行环境' : '下载 Wine 与启动补丁',
            blocked
                ? null
                : launcher.runtimeReady
                ? () => _run(launcher.refresh)
                : () => _run(launcher.installRuntime),
            primary: !launcher.runtimeReady,
          ),
        ]),
      ]);

  Future<void> _showVersions({bool downloads = false}) => showOreDialog<void>(
    context: context,
    builder: (_) => DevelopmentVersionDialog(
      launcher: _launcher,
      downloads: downloads,
      onImport: () => _pick(mod: false, archive: false),
      onLogin: widget.onLogin,
    ),
  );

  Future<void> _showLogs() => showOreDialog<void>(
    context: context,
    builder: (_) => DevelopmentLogDialog(
      storage: widget.storage,
      preferredPath: _launcher.logPath,
    ),
  );

  Future<void> _showLanTest() async {
    final launcher = _launcher;
    final player = await showOreDialog<({String name, TestPlayerSkin skin})>(
      context: context,
      builder: (_) => _LanPlayerLaunchDialog(launcher: launcher),
    );
    if (player == null || !mounted) return;
    await _run(
      () => launcher.launchLanPlayer(name: player.name, skin: player.skin),
    );
  }

  Future<void> _showLanPlayers() => showOreDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: _launcher,
      builder: (context, _) {
        final players = _launcher.players;
        final connected = players
            .where(
              (player) => player.status == DevelopmentPlayerStatus.connected,
            )
            .length;
        return OreAlertDialog(
          key: const ValueKey('development-lan-players-dialog'),
          title: const Text('玩家列表'),
          maxWidth: 600,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_launcher.tabTitle),
              const SizedBox(height: 6),
              _hint('当前世界内 $connected 人'),
              if (players.isEmpty) ...[
                const SizedBox(height: 16),
                const Text('当前没有玩家。'),
              ],
              for (final player in players) ...[
                const SizedBox(height: 12),
                Row(
                  key: ValueKey('development-lan-player-${player.id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.name,
                            style: OreTheme.of(context).typography.label,
                          ),
                          const SizedBox(height: 4),
                          _hint(
                            [
                              if (player.host) '房主',
                              if (player.skin case final skin?)
                                skin == TestPlayerSkin.alex
                                    ? '艾利克斯（细手臂）'
                                    : '史蒂夫（粗手臂）'
                              else if (!player.host)
                                '局域网玩家',
                              switch (player.status) {
                                DevelopmentPlayerStatus.starting => '正在加入',
                                DevelopmentPlayerStatus.connected => '世界内',
                                DevelopmentPlayerStatus.disconnected => '已离开',
                                DevelopmentPlayerStatus.failed => '加入失败',
                              },
                            ].join(' · '),
                          ),
                          if (player.error case final error?) ...[
                            const SizedBox(height: 4),
                            Text(
                              error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!player.host && player.canStop)
                      OreIconButton(
                        key: ValueKey('development-stop-player-${player.id}'),
                        tooltip: '关闭 ${player.name} 的测试窗口',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            _run(() => _launcher.stopLanPlayer(player.id)),
                      ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            _button(
              '添加测试玩家',
              _launcher.lanAvailable
                  ? () {
                      Navigator.of(dialogContext).pop();
                      _showLanTest();
                    }
                  : null,
            ),
            _button('关闭', () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    ),
  );

  Widget _gameCard(DevelopmentLauncher launcher, bool blocked) =>
      _card('游戏版本', [
        Text('${launcher.games.length} 个已安装版本 · 可同时保留多个版本'),
        const SizedBox(height: 6),
        _hint(launcher.loggedIn ? '共用软件已登录的开发者账号' : '请先使用软件现有入口登录。'),
        const SizedBox(height: 10),
        _actions([
          _button('管理游戏版本', () => _showVersions()),
          _button('浏览可下载版本', () => _showVersions(downloads: true)),
        ]),
        const SizedBox(height: 8),
        _hint('支持官方清单中的稳定、预览、Beta、测试和其他版本。'),
      ]);

  String _projectSummary(ModProject project) {
    final behavior = project.packs
        .where((pack) => pack.type != 'resources')
        .length;
    final resources = project.packs.length - behavior;
    final versions = project.packs
        .map((pack) => pack.version.join('.'))
        .toSet();
    return [
      if (behavior > 0) '$behavior 个行为包',
      if (resources > 0) '$resources 个资源包',
      if (versions.length == 1) versions.single,
    ].join(' · ');
  }

  Future<void> _showProject(ModProject project) async {
    final launcher = _launcher;
    await showOreDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: launcher,
        builder: (context, _) => OreAlertDialog(
          title: Text(project.name),
          maxWidth: 680,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _hint('项目统一启用；测试前同步以下包的最新文件。'),
              for (final pack in project.packs) ...[
                const SizedBox(height: 16),
                Text(
                  pack.type == 'resources' ? '资源包' : '行为 / 脚本包',
                  style: OreTheme.of(context).typography.label,
                ),
                Text(
                  '${modDisplayName(pack.name)} · ${pack.version.join('.')}',
                ),
                const SizedBox(height: 6),
                OreSelectableText(pack.directory),
                const SizedBox(height: 6),
                _hint('UUID：${pack.uuid}'),
              ],
            ],
          ),
          actions: [
            _button(
              '移除项目',
              launcher.busy || launcher.running || _picking
                  ? null
                  : () async {
                      Navigator.of(dialogContext).pop();
                      await _run(() => launcher.removePacks(project.uuids));
                    },
            ),
            _button('关闭', () => Navigator.of(dialogContext).pop()),
          ],
        ),
      ),
    );
  }

  Widget _projectRow(
    ModProject project,
    DevelopmentLauncher launcher,
    bool blocked,
  ) {
    final selected = project.selection(launcher.selectedPacks);
    void toggle() =>
        _run(() => launcher.togglePacks(project.uuids, selected != true));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              checked: selected == true,
              enabled: !blocked,
              child: OreListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                leading: ExcludeFocus(
                  child: IgnorePointer(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OreCheckbox(
                          value: selected,
                          tristate: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: blocked ? null : (_) => toggle(),
                        ),
                        const SizedBox(width: 8),
                        ModProjectIcon(
                          key: ValueKey('project-icon-${project.id}'),
                          project: project,
                        ),
                      ],
                    ),
                  ),
                ),
                onTap: blocked ? null : toggle,
                title: Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_projectSummary(project)}${selected == null ? ' · 部分启用' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          OreIconButton(
            key: ValueKey('project-details-${project.id}'),
            icon: const Icon(Icons.info_outline),
            tooltip: '查看项目包详情',
            onPressed: () => _showProject(project),
          ),
        ],
      ),
    );
  }

  Widget _projectCard(
    DevelopmentLauncher launcher,
    bool blocked, {
    bool scroll = false,
  }) {
    final projects = launcher.sortedProjects;
    final selected = projects
        .where((project) => project.selection(launcher.selectedPacks) != false)
        .length;
    final rows = [
      for (final project in projects) _projectRow(project, launcher, blocked),
    ];
    return _card(
      '本地项目',
      [
        _actions([
          _button(
            '导入项目文件夹',
            blocked ? null : () => _pick(mod: true, archive: false),
          ),
          _button(
            '导入模组归档',
            blocked ? null : () => _pick(mod: true, archive: true),
          ),
        ]),
        const SizedBox(height: 8),
        _hint('勾选项目一起测试，文件夹项目保留在原位置。'),
        if (projects.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('尚未导入项目。'),
          ),
        if (scroll)
          Expanded(
            child: OreScrollbar(
              controller: _projectScroll,
              child: ListView(
                key: const PageStorageKey('development-projects'),
                controller: _projectScroll,
                padding: const EdgeInsets.only(right: 14),
                children: rows,
              ),
            ),
          )
        else
          ...rows,
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$selected / ${projects.length} 已选',
            style: OreTheme.of(context).typography.caption,
          ),
          const SizedBox(width: 8),
          OreIconButton(
            key: const ValueKey('development-project-sort'),
            icon: const Icon(Icons.sort),
            tooltip: '项目排序 · ${launcher.projectSortOrder.label}',
            onPressed: _showProjectSort,
          ),
        ],
      ),
    );
  }

  Future<void> _showProjectSort() async {
    var selected = _launcher.projectSortOrder;
    final result = await showOreDialog<ProjectSortOrder>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => OreAlertDialog(
          title: const Text('本地项目排序'),
          maxWidth: 420,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final order in ProjectSortOrder.values)
                Semantics(
                  inMutuallyExclusiveGroup: true,
                  child: OreCheckboxListTile(
                    key: ValueKey('project-sort-${order.name}'),
                    value: selected == order,
                    dense: true,
                    title: Text(order.label),
                    onChanged: (_) => setDialogState(() => selected = order),
                  ),
                ),
              const SizedBox(height: 8),
              _hint('启动时间按项目最近一次启动测试记录，未启动过的项目排在最后。'),
            ],
          ),
          actions: [
            _button('取消', () => Navigator.of(dialogContext).pop()),
            _button(
              '应用',
              () => Navigator.of(dialogContext).pop(selected),
              primary: true,
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      await _run(() => _launcher.chooseProjectSortOrder(result));
    }
  }

  Widget _testOptions(
    DevelopmentLauncher launcher,
    bool blocked,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      Widget field(String label, double width, Widget child, {String? hint}) {
        final control = SizedBox(
          width: (width * scale).clamp(0, constraints.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: OreTheme.of(context).typography.caption),
              const SizedBox(height: 4),
              child,
            ],
          ),
        );
        return hint == null
            ? control
            : OreTooltip(message: hint, child: control);
      }

      Widget toggle(
        String label,
        bool value,
        ValueChanged<bool?>? onChanged, {
        Key? key,
        String? hint,
      }) {
        final control = IntrinsicWidth(
          child: OreCheckboxListTile(
            key: key,
            value: value,
            title: Text(label),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            onChanged: onChanged,
          ),
        );
        return hint == null
            ? control
            : OreTooltip(message: hint, child: control);
      }

      final rendererHint = !launcher.rendererSwitchSupported
          ? '此版本使用 OpenGL；3.9 及以上可切换渲染器。'
          : _menuOnly
          ? '渲染器选择用于测试世界；主菜单沿用游戏默认渲染器。'
          : launcher.effectiveRenderer == GameRenderer.renderDragon
          ? !launcher.capabilities.requiresWine
                ? '使用 Windows 原生渲染龙，重启游戏后生效。'
                : launcher.renderDragonCompatibilitySupported
                ? '此版本使用 Metal 适配；首次启动下载约 18 MB 组件，重启游戏后生效。'
                : '渲染龙的 Wine 兼容性随版本而异；若无法启动，可切回 OpenGL。'
          : '按当前游戏版本保存，重启游戏后生效。';
      return Wrap(
        key: const ValueKey('development-test-options'),
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          field(
            '世界名称',
            210,
            OreTextField(
              key: const ValueKey('development-world-name'),
              controller: _world,
              enabled: !blocked && !_menuOnly,
              hintText: '测试世界名称',
            ),
          ),
          field(
            '游戏模式',
            140,
            OreChoiceButtons(
              items: const [Text('生存'), Text('创造')],
              size: OreButtonSize.sm,
              selectedIndex: _creative ? 1 : 0,
              onChanged: blocked || _menuOnly
                  ? null
                  : (index) {
                      setState(() => _creative = index == 1);
                      _saveOptions();
                    },
            ),
          ),
          field(
            '玩家皮肤',
            360,
            OreChoiceButtons(
              items: const [
                FittedBox(fit: BoxFit.scaleDown, child: Text('史蒂夫（粗手臂）')),
                FittedBox(fit: BoxFit.scaleDown, child: Text('艾利克斯（细手臂）')),
              ],
              size: OreButtonSize.sm,
              selectedIndex: launcher.playerSkin.index,
              onChanged: blocked || _menuOnly
                  ? null
                  : (index) => _run(
                      () => launcher.choosePlayerSkin(
                        TestPlayerSkin.values[index],
                      ),
                    ),
            ),
            hint: '用于测试世界，重启游戏后生效。',
          ),
          field(
            '渲染器',
            220,
            OreChoiceButtons(
              items: const [Text('OpenGL'), Text('渲染龙')],
              size: OreButtonSize.sm,
              selectedIndex: _menuOnly ? 0 : launcher.effectiveRenderer.index,
              onChanged:
                  blocked || !launcher.rendererSwitchSupported || _menuOnly
                  ? null
                  : (index) => _run(
                      () => launcher.chooseRenderer(GameRenderer.values[index]),
                    ),
            ),
            hint: rendererHint,
          ),
          toggle(
            '使用新存档',
            launcher.useNewWorld,
            blocked || _menuOnly
                ? null
                : (value) async {
                    setState(() => _savingWorldMode = true);
                    await _run(() => launcher.chooseNewWorld(value ?? false));
                    if (mounted) setState(() => _savingWorldMode = false);
                  },
            key: const ValueKey('development-new-world'),
            hint: '每次启动创建新存档，已有存档保留。',
          ),
          if (launcher.useNewWorld)
            field(
              '世界种子',
              210,
              OreTextField(
                key: const ValueKey('development-world-seed'),
                controller: _seed,
                enabled: !blocked && !_menuOnly,
                hintText: '世界种子（留空随机）',
              ),
            ),
          toggle(
            '仅打开游戏主菜单',
            _menuOnly,
            blocked
                ? null
                : (value) {
                    setState(() => _menuOnly = value ?? false);
                    _saveOptions();
                  },
          ),
          if (!_menuOnly &&
              launcher.effectiveRenderer == GameRenderer.renderDragon)
            toggle(
              '灵动视效（实验性）',
              launcher.vibrantVisuals && launcher.vibrantVisualsSupported,
              blocked || !launcher.vibrantVisualsSupported
                  ? null
                  : (value) => _run(
                      () => launcher.chooseVibrantVisuals(value ?? false),
                    ),
              hint: launcher.vibrantVisualsSupported
                  ? '光照、阴影与水面反射；重启生效。当前适配 3.10.0.420447，帧率取决于画质与场景。'
                  : '当前版本尚未适配灵动视效，请选择 3.10.0.420447 Haldra x64。',
            ),
          if (launcher.performanceOptimizationSupported)
            toggle(
              '图形性能优化',
              launcher.performanceOptimization,
              blocked
                  ? null
                  : (value) => _run(
                      () => launcher.choosePerformanceOptimization(
                        value ?? false,
                      ),
                    ),
              hint: '实验性补丁；关闭后重启即可回退。请保留原画质进行对比。',
            ),
          toggle(
            '限制 60 帧',
            launcher.limit60Fps,
            blocked
                ? null
                : (value) =>
                      _run(() => launcher.chooseFrameLimit(value ?? false)),
            hint: '关闭后不设帧率上限。重启游戏后生效。',
          ),
          toggle(
            '显示开发控制台',
            launcher.showDeveloperConsole,
            blocked
                ? null
                : (value) => _run(
                    () => launcher.chooseDeveloperConsole(value ?? false),
                  ),
            hint: '与游戏“调试”中的同名选项一致，默认关闭，重启游戏后生效。',
          ),
          toggle(
            '关闭我的伙伴',
            launcher.disableCompanion,
            blocked || _menuOnly
                ? null
                : (value) => _run(
                    () => launcher.chooseDisableCompanion(value ?? true),
                  ),
            key: const ValueKey('development-disable-companion'),
            hint: '默认勾选，关闭测试世界中的我的伙伴。重启游戏后生效。',
          ),
          if (launcher.capabilities.commandShiftFullscreen)
            toggle(
              'Shift + Command 切换全屏',
              launcher.fullscreenShortcut,
              blocked
                  ? null
                  : (value) => _run(
                      () => launcher.chooseFullscreenShortcut(value ?? false),
                    ),
              hint: '默认关闭，避免与 macOS 截图快捷键冲突。重启游戏后生效。',
            ),
        ],
      );
    },
  );

  Widget _testCard(DevelopmentLauncher launcher, bool blocked) {
    final noGame = launcher.selectedVersion == null;
    final label = launcher.running
        ? '游戏运行中'
        : launcher.busy
        ? '正在处理…'
        : noGame
        ? '安装游戏'
        : !launcher.runtimeReady
        ? '安装运行环境'
        : '启动测试';
    final launch = OreButton(
      key: const ValueKey('development-launch'),
      size: OreButtonSize.lg,
      variant: OreButtonVariant.primary,
      onPressed: blocked
          ? null
          : noGame
          ? () => _showVersions(downloads: true)
          : !launcher.runtimeReady
          ? () => _run(launcher.installRuntime)
          : () => _run(
              () => launcher.launchTest(
                worldName: _world.text,
                creative: _creative,
                menuOnly: _menuOnly,
                seed: _seed.text,
              ),
            ),
      child: Text(label),
    );
    final versions = OreDropdownButton<String>(
      key: const ValueKey('active-game-version'),
      value: launcher.selectedVersion,
      hint: const Text('选择已安装的游戏版本'),
      items: [
        for (final game in launcher.games)
          OreDropdownItem(
            value: game.version,
            child: Text('${game.version} · 已安装'),
          ),
      ],
      onChanged: blocked || launcher.games.isEmpty
          ? null
          : (version) => _run(() => launcher.chooseVersion(version)),
    );
    final selected = launcher.projects
        .where((project) => project.selection(launcher.selectedPacks) != false)
        .length;
    return _card('启动游戏', [
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 560) {
            return Row(
              children: [
                SizedBox(width: 220, child: launch),
                const SizedBox(width: 12),
                Expanded(child: versions),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [launch, const SizedBox(height: 10), versions],
          );
        },
      ),
      const SizedBox(height: 12),
      _testOptions(launcher, blocked),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OreTooltip(
            message: launcher.lanAvailable
                ? '在新窗口加入此标签的测试世界，可重复添加玩家。'
                : launcher.lanUnavailableReason,
            child: OreButton(
              key: const ValueKey('development-lan-test'),
              size: OreButtonSize.sm,
              onPressed: launcher.lanAvailable ? _showLanTest : null,
              child: const Text('局域网测试'),
            ),
          ),
          if (launcher.hasLanPlayers)
            OreButton(
              key: const ValueKey('development-lan-players'),
              size: OreButtonSize.sm,
              onPressed: _showLanPlayers,
              child: const Text('玩家列表'),
            ),
          _hint(
            _menuOnly
                ? '主菜单模式不创建或切换测试存档。'
                : '${launcher.useNewWorld ? '每次启动创建新存档，已有存档保留' : '继续上次测试存档'} · $selected 个项目',
          ),
          _button('查看日志', _showLogs),
          if (launcher.running) _button('退出测试', () => _run(launcher.stopGame)),
        ],
      ),
    ]);
  }

  Future<void> _showStatus() => showOreDialog<void>(
    context: context,
    builder: (dialogContext) => OreAlertDialog(
      title: const Text('运行详情'),
      content: ListenableBuilder(
        listenable: _launcher,
        builder: (context, _) {
          final launcher = _launcher;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?widget.statusSection,
              if (launcher.progress != null) ...[
                Text(launcher.progress!.message),
                if (launcher.progress!.total > 0)
                  Text(
                    '${launcher.progress!.completed} / ${launcher.progress!.total}',
                  ),
              ],
              if (launcher.error != null || _error != null)
                Text(
                  launcher.error ?? _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (launcher.notice != null) Text(launcher.notice!),
              if (!launcher.busy &&
                  launcher.notice == null &&
                  launcher.error == null &&
                  _error == null)
                const Text('开发环境就绪。'),
            ],
          );
        },
      ),
      actions: [_button('关闭', () => Navigator.of(dialogContext).pop())],
    ),
  );

  Widget _statusBar(DevelopmentLauncher launcher) {
    final progress = launcher.progress;
    final error = launcher.error ?? _error;
    final message =
        error ??
        (launcher.running
            ? '游戏正在运行，请在游戏内保存并退出。'
            : launcher.busy
            ? progress?.message ?? '正在处理…'
            : launcher.notice ?? '就绪');
    return SizedBox(
      key: const ValueKey('development-status'),
      height: 76,
      child: OreCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 6,
              child: Opacity(
                opacity: launcher.busy || launcher.running ? 1 : 0,
                child: OreProgressBar(
                  value: launcher.running
                      ? 1
                      : launcher.busy
                      ? progress?.fraction
                      : 0,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child:
                        widget.statusSection != null &&
                            !launcher.busy &&
                            error == null
                        ? SingleChildScrollView(child: widget.statusSection)
                        : Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OreTheme.of(context).typography.caption
                                .copyWith(
                                  color: error != null
                                      ? Theme.of(context).colorScheme.error
                                      : OreTheme.of(context).colors.textMuted,
                                ),
                          ),
                  ),
                  if (launcher.busy && progress?.message == '下载中')
                    _button('暂停下载', launcher.cancel),
                  OreIconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: '运行详情',
                    onPressed: _showStatus,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scroll(
    ScrollController controller,
    List<Widget> children, {
    Key? key,
  }) => OreScrollbar(
    controller: controller,
    child: ListView(
      key: key,
      controller: controller,
      padding: const EdgeInsets.only(right: 14),
      children: [
        for (final child in children)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final launcher = _launcher;
    return ListenableBuilder(
      listenable: launcher,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final blocked =
              launcher.busy || launcher.running || _picking || _savingWorldMode;
          final environment = [
            ?widget.storageSection,
            if (launcher.capabilities.requiresWine)
              _wineCard(launcher, blocked),
            _gameCard(launcher, blocked),
          ];
          // Launch controls come first. The status strip always reserves the
          // same space, so progress, notices and errors cannot resize the panes.
          final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
              .clamp(1.0, double.infinity);
          final desktop =
              constraints.hasBoundedHeight &&
              constraints.maxWidth >= 720 * textScale;
          if (desktop) {
            // Each desktop region owns its scrolling. Cap the launch card so
            // short windows still leave room for both independent panes.
            final bodyHeight = (constraints.maxHeight - 88).clamp(
              0.0,
              double.infinity,
            );
            final panes = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: (constraints.maxWidth * .34).clamp(
                    300 * textScale,
                    380 * textScale,
                  ),
                  child: _scroll(
                    _environmentScroll,
                    environment,
                    key: const PageStorageKey('development-environment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, paneConstraints) =>
                        paneConstraints.maxHeight >= 240 * textScale
                        ? _projectCard(launcher, blocked, scroll: true)
                        : _scroll(
                            _compactProjectScroll,
                            [_projectCard(launcher, blocked)],
                            key: const PageStorageKey(
                              'development-projects-compact',
                            ),
                          ),
                  ),
                ),
              ],
            );
            return Column(
              key: const ValueKey('development-desktop'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  key: const ValueKey('development-launch-region'),
                  constraints: BoxConstraints(maxHeight: bodyHeight * .55),
                  child: OreScrollbar(
                    controller: _launchScroll,
                    child: SingleChildScrollView(
                      key: const PageStorageKey('development-launch-controls'),
                      controller: _launchScroll,
                      padding: const EdgeInsets.only(right: 14),
                      child: _testCard(launcher, blocked),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: panes),
                const SizedBox(height: 12),
                _statusBar(launcher),
              ],
            );
          }
          final children = [
            _testCard(launcher, blocked),
            _projectCard(launcher, blocked),
            ...environment,
          ];
          if (constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _scroll(
                    _pageScroll,
                    children,
                    key: const ValueKey('development-single-column'),
                  ),
                ),
                const SizedBox(height: 8),
                _statusBar(launcher),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
              _statusBar(launcher),
            ],
          );
        },
      ),
    );
  }
}

class _LanPlayerLaunchDialog extends StatefulWidget {
  const _LanPlayerLaunchDialog({required this.launcher});
  final DevelopmentLauncher launcher;

  @override
  State<_LanPlayerLaunchDialog> createState() => _LanPlayerLaunchDialogState();
}

class _LanPlayerLaunchDialogState extends State<_LanPlayerLaunchDialog> {
  late final TextEditingController _name;
  late TestPlayerSkin _skin;
  String? _error;
  bool _submitted = false;

  bool _reservesName(DevelopmentPlayer player) =>
      player.host ||
      player.canStop ||
      player.status == DevelopmentPlayerStatus.connected ||
      player.status == DevelopmentPlayerStatus.starting;

  @override
  void initState() {
    super.initState();
    final names = widget.launcher.players
        .where(_reservesName)
        .map((player) => player.name)
        .toSet();
    _name = TextEditingController(text: suggestedDevelopmentPlayerName(names));
    _skin = widget.launcher.playerSkin;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted || !widget.launcher.lanAvailable) return;
    final error = validateDevelopmentPlayerName(_name.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final name = _name.text.trim();
    if (widget.launcher.players.any(
      (player) => player.name == name && _reservesName(player),
    )) {
      setState(() => _error = '这个玩家名字已经在当前世界使用，请换一个名字。');
      return;
    }
    setState(() => _submitted = true);
    Navigator.of(context).pop((name: name, skin: _skin));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.launcher,
    builder: (context, _) => OreAlertDialog(
      key: const ValueKey('development-lan-launch-dialog'),
      title: const Text('局域网测试'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('加入“${widget.launcher.tabTitle}”正在运行的测试世界。'),
          const SizedBox(height: 16),
          const Text('玩家名字'),
          const SizedBox(height: 6),
          OreTextField(
            key: const ValueKey('development-lan-player-name'),
            controller: _name,
            hintText: '输入玩家名字',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 6),
          Text(
            '最多 16 字节，中文通常最多 5 个字。',
            style: OreTheme.of(context).typography.caption.copyWith(
              color: OreTheme.of(context).colors.textMuted,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          const Text('皮肤类型'),
          const SizedBox(height: 6),
          OreChoiceButtons(
            key: const ValueKey('development-lan-player-skin'),
            items: const [Text('史蒂夫（粗手臂）'), Text('艾利克斯（细手臂）')],
            selectedIndex: _skin.index,
            onChanged: (index) =>
                setState(() => _skin = TestPlayerSkin.values[index]),
          ),
          const SizedBox(height: 16),
          Text(
            widget.launcher.lanAvailable
                ? '每次启动会打开一个独立的游戏窗口，并自动加入当前世界。'
                : widget.launcher.lanUnavailableReason,
            style: OreTheme.of(context).typography.caption.copyWith(
              color: OreTheme.of(context).colors.textMuted,
            ),
          ),
        ],
      ),
      actions: [
        OreButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        OreButton(
          key: const ValueKey('development-start-lan-test'),
          variant: OreButtonVariant.primary,
          onPressed: widget.launcher.lanAvailable && !_submitted
              ? _submit
              : null,
          child: const Text('启动局域网测试'),
        ),
      ],
    ),
  );
}
