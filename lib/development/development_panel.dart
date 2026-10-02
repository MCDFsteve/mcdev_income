import 'package:file_picker/file_picker.dart';
import '../storage/app_preferences.dart';
import '../ui/ore_material.dart';
import 'development_storage.dart';
import 'launcher_service.dart';
import 'log_dialog.dart';
import 'version_dialog.dart';

class DevelopmentEnvironmentPanel extends StatefulWidget {
  const DevelopmentEnvironmentPanel({
    super.key,
    required this.storage,
    this.onActivity,
    this.launcherFactory,
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
  final Widget? storageSection;
  final Widget? statusSection;
  @override
  State<DevelopmentEnvironmentPanel> createState() =>
      _DevelopmentEnvironmentPanelState();
}

class _DevelopmentEnvironmentPanelState
    extends State<DevelopmentEnvironmentPanel> {
  DevelopmentLauncher? _launcher;
  String? _error;
  final _world = TextEditingController(text: '模组测试');
  bool _creative = true;
  bool _menuOnly = false;
  bool _activity = false;
  bool _picking = false;
  final _environmentScroll = ScrollController();
  final _projectScroll = ScrollController();
  final _compactProjectScroll = ScrollController();
  final _pageScroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final launcher = await (widget.launcherFactory?.call() ?? _open());
      if (!mounted) {
        launcher.dispose();
        return;
      }
      launcher.addListener(_onChanged);
      setState(() => _launcher = launcher);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<DevelopmentLauncher> _open() async => openDevelopmentLauncher(
    widget.storage,
    await AppPreferences.getInstance(),
    cookieProvider: widget.cookieProvider,
  );
  void _onChanged() {
    final active = _launcher!.busy || _launcher!.running;
    if (active != _activity) {
      _activity = active;
      widget.onActivity?.call(active);
    }
  }

  @override
  void dispose() {
    _launcher?.removeListener(_onChanged);
    _launcher?.dispose();
    _world.dispose();
    _environmentScroll.dispose();
    _projectScroll.dispose();
    _compactProjectScroll.dispose();
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
        await (mod ? _launcher!.importMods(path) : _launcher!.importGame(path));
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
                : () => _run(launcher.installWine),
            primary: !launcher.runtimeReady,
          ),
        ]),
      ]);

  Future<void> _showVersions({bool downloads = false}) => showOreDialog<void>(
    context: context,
    builder: (_) => DevelopmentVersionDialog(
      launcher: _launcher!,
      downloads: downloads,
      onImport: () => _pick(mod: false, archive: false),
      onLogin: widget.onLogin,
    ),
  );

  Future<void> _showLogs() => showOreDialog<void>(
    context: context,
    builder: (_) => DevelopmentLogDialog(
      storage: widget.storage,
      preferredPath: _launcher?.logPath,
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
    final launcher = _launcher!;
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
                    child: OreCheckbox(
                      value: selected,
                      tristate: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: blocked ? null : (_) => toggle(),
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
    final projects = launcher.projects;
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
      trailing: Text(
        '$selected / ${projects.length} 已选',
        style: OreTheme.of(context).typography.caption,
      ),
    );
  }

  Future<void> _showTestSettings() async {
    await showOreDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final blocked = _launcher!.busy || _launcher!.running || _picking;
          return OreAlertDialog(
            title: const Text('测试设置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OreTextField(
                    controller: _world,
                    enabled: !blocked,
                    hintText: '测试世界名称',
                  ),
                  const SizedBox(height: 12),
                  OreChoiceButtons(
                    items: const [Text('生存'), Text('创造')],
                    selectedIndex: _creative ? 1 : 0,
                    onChanged: blocked
                        ? null
                        : (value) => update(() => _creative = value == 1),
                  ),
                  const SizedBox(height: 8),
                  OreCheckboxListTile(
                    value: _menuOnly,
                    onChanged: blocked
                        ? null
                        : (value) => update(() => _menuOnly = value ?? false),
                    title: const Text('仅打开游戏主菜单'),
                  ),
                  const SizedBox(height: 8),
                  Text('渲染器', style: OreTheme.of(context).typography.label),
                  const SizedBox(height: 6),
                  OreChoiceButtons(
                    items: const [Text('OpenGL'), Text('渲染龙')],
                    selectedIndex: _menuOnly
                        ? 0
                        : _launcher!.effectiveRenderer.index,
                    onChanged:
                        blocked ||
                            !_launcher!.rendererSwitchSupported ||
                            _menuOnly
                        ? null
                        : (index) async {
                            try {
                              await _launcher!.chooseRenderer(
                                GameRenderer.values[index],
                              );
                              if (context.mounted) {
                                update(() {});
                              }
                            } catch (error) {
                              if (mounted) {
                                setState(() => _error = error.toString());
                              }
                            }
                          },
                  ),
                  _hint(
                    !_launcher!.rendererSwitchSupported
                        ? '此版本使用 OpenGL；3.9 及以上可切换渲染器。'
                        : _menuOnly
                        ? '渲染器选择用于测试世界；主菜单沿用游戏默认渲染器。'
                        : '按当前游戏版本保存，重启游戏后生效。',
                  ),
                  if (!_menuOnly &&
                      _launcher!.effectiveRenderer == GameRenderer.renderDragon)
                    _hint(
                      _launcher!.renderDragonCompatibilitySupported
                          ? '此版本使用 Metal 适配；首次启动下载约 18 MB 组件，保存在开发数据目录。'
                          : '渲染龙的 Wine 兼容性随版本而异；若无法启动，可切回 OpenGL。',
                    ),
                  if (!_menuOnly &&
                      _launcher!.effectiveRenderer ==
                          GameRenderer.renderDragon) ...[
                    const SizedBox(height: 8),
                    OreCheckboxListTile(
                      value:
                          _launcher!.vibrantVisuals &&
                          _launcher!.vibrantVisualsSupported,
                      onChanged: blocked || !_launcher!.vibrantVisualsSupported
                          ? null
                          : (value) async {
                              try {
                                await _launcher!.chooseVibrantVisuals(
                                  value ?? false,
                                );
                                if (context.mounted) update(() {});
                              } catch (error) {
                                if (mounted) {
                                  setState(() => _error = error.toString());
                                }
                              }
                            },
                      title: const Text('灵动视效（实验性）'),
                    ),
                    _hint(
                      _launcher!.vibrantVisualsSupported
                          ? '光照、阴影与水面反射；重启生效。当前适配 3.10.0.420447，帧率取决于画质与场景。'
                          : '当前版本尚未适配灵动视效，请选择 3.10.0.420447 Haldra x64。',
                    ),
                  ],
                  const SizedBox(height: 8),
                  OreCheckboxListTile(
                    value:
                        _launcher!.performanceOptimization &&
                        _launcher!.performanceOptimizationSupported,
                    onChanged:
                        blocked || !_launcher!.performanceOptimizationSupported
                        ? null
                        : (value) async {
                            try {
                              await _launcher!.choosePerformanceOptimization(
                                value ?? false,
                              );
                              if (context.mounted) {
                                update(() {});
                              }
                            } catch (error) {
                              if (mounted) {
                                setState(() => _error = error.toString());
                              }
                            }
                          },
                    title: const Text('图形性能优化'),
                  ),
                  _hint(
                    _launcher!.performanceOptimizationSupported
                        ? '实验性补丁；关闭后重启即可回退。请保留原画质进行对比。'
                        : '上传优化补丁目前适配 3.8.0.313229 的 OpenGL 路径。',
                  ),
                  const SizedBox(height: 8),
                  OreCheckboxListTile(
                    value: _launcher!.limit60Fps,
                    onChanged: blocked
                        ? null
                        : (value) async {
                            try {
                              await _launcher!.chooseFrameLimit(value ?? false);
                              if (context.mounted) {
                                update(() {});
                              }
                            } catch (error) {
                              if (mounted) {
                                setState(() => _error = error.toString());
                              }
                            }
                          },
                    title: const Text('限制 60 帧'),
                  ),
                  _hint('关闭后不设帧率上限，图形优化仍可启用。重启游戏后生效。'),
                  const SizedBox(height: 8),
                  _hint('重开同一个测试存档；请在游戏内保存并退出。'),
                ],
              ),
            ),
            actions: [_button('完成', () => Navigator.of(dialogContext).pop())],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

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
          ? () => _run(launcher.installWine)
          : () => _run(
              () => launcher.launchTest(
                worldName: _world.text,
                creative: _creative,
                menuOnly: _menuOnly,
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
                Expanded(child: versions),
                const SizedBox(width: 12),
                SizedBox(width: 220, child: launch),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [versions, const SizedBox(height: 10), launch],
          );
        },
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _hint(
            _menuOnly
                ? '仅打开主菜单'
                : '${_world.text} · ${_creative ? '创造' : '生存'} · $selected 个项目',
          ),
          _button('测试设置', blocked ? null : _showTestSettings),
          _button('管理版本', () => _showVersions()),
          if (launcher.running) _button('退出测试', () => _run(launcher.stopGame)),
          _button('查看日志', _showLogs),
        ],
      ),
    ]);
  }

  Future<void> _showStatus() => showOreDialog<void>(
    context: context,
    builder: (dialogContext) => OreAlertDialog(
      title: const Text('运行详情'),
      content: ListenableBuilder(
        listenable: _launcher!,
        builder: (context, _) {
          final launcher = _launcher!;
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
    if (launcher == null) {
      return Center(
        child: _error == null
            ? const OreLoadingIndicator()
            : Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
      );
    }
    return ListenableBuilder(
      listenable: launcher,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final blocked = launcher.busy || launcher.running || _picking;
          final environment = [
            ?widget.storageSection,
            _wineCard(launcher, blocked),
            _gameCard(launcher, blocked),
          ];
          // Launch controls come first. The status strip always reserves the
          // same space, so progress, notices and errors cannot resize the panes.
          final desktop =
              constraints.hasBoundedHeight &&
              constraints.maxWidth >= 720 &&
              constraints.maxHeight >= 380 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          if (desktop) {
            return Column(
              key: const ValueKey('development-desktop'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _testCard(launcher, blocked),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth * .34).clamp(300, 380),
                        child: _scroll(
                          _environmentScroll,
                          environment,
                          key: const PageStorageKey('development-environment'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: constraints.maxHeight >= 520
                            ? _projectCard(launcher, blocked, scroll: true)
                            : _scroll(
                                _compactProjectScroll,
                                [_projectCard(launcher, blocked)],
                                key: const PageStorageKey(
                                  'development-projects-compact',
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
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
