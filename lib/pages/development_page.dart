part of '../main.dart';

class DevelopmentPage extends StatefulWidget {
  const DevelopmentPage({super.key, this.storageFactory});
  final Future<DevelopmentStorage> Function()? storageFactory;
  @override
  State<DevelopmentPage> createState() => _DevelopmentPageState();
}

enum _StorageAction { initialize, reuse, migrate }

class _DevelopmentPageState extends State<DevelopmentPage> {
  DevelopmentStorage? _storage;
  DevelopmentStorageStatus? _status;
  bool _busy = true;
  String? _error;
  String? _notice;
  StorageMigrationProgress? _progress;
  bool _environmentActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final storage =
          _storage ?? await (widget.storageFactory?.call() ?? _openStorage());
      // Keep recovery actions available even if inspection or setup fails.
      if (!mounted) return;
      setState(() => _storage = storage);
      var status = await storage.inspect();
      if (!status.initialized && !status.exists && status.problem == null) {
        // A missing, unconfigured default is the first-use case. An unavailable
        // saved location or an invalid existing directory requires user action.
        await storage.initialize();
        status = await storage.inspect();
      }
      if (mounted) {
        setState(() {
          _storage = storage;
          _status = status;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<DevelopmentStorage> _openStorage() async =>
      openDevelopmentStorage(await AppPreferences.getInstance());

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      final status = await _storage!.inspect();
      if (mounted) {
        setState(() {
          _status = status;
          _notice = success;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _choose(_StorageAction action) async {
    final root = await showOreDialog<String>(
      context: context,
      builder: (_) =>
          _DevelopmentPathDialog(action: action, current: _storage!.paths.root),
    );
    if (root == null || !mounted) return;
    await _run(() async {
      switch (action) {
        case _StorageAction.initialize:
          await _storage!.initialize(root: root);
        case _StorageAction.reuse:
          await _storage!.useExisting(root);
        case _StorageAction.migrate:
          await _storage!.migrateTo(
            root,
            onProgress: (value) {
              if (mounted) setState(() => _progress = value);
            },
          );
      }
    }, action == _StorageAction.migrate ? '迁移完成，旧目录已保留。' : '开发数据位置已保存。');
  }

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: _storage!.paths.root));
    if (mounted) setState(() => _notice = '路径已复制。');
  }

  Widget _message(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        color: error
            ? Theme.of(context).colorScheme.error
            : OreTheme.of(context).colors.textMuted,
      ),
    ),
  );

  Future<void> _manageStorage() async {
    final storage = _storage!;
    final ready = _status?.initialized == true;
    final blocked = _busy || _environmentActive;
    await showOreDialog<void>(
      context: context,
      builder: (dialogContext) {
        void choose(_StorageAction action) {
          Navigator.of(dialogContext).pop();
          _choose(action);
        }

        return OreAlertDialog(
          title: const Text('管理开发数据目录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OreSelectableText(storage.paths.root),
              const SizedBox(height: 12),
              const Text('游戏、存档、运行组件和日志统一存放在此目录。迁移会先复制并校验，成功后切换位置，原目录保留。'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in <_StorageAction, String>{
                    _StorageAction.initialize: '选择新目录',
                    _StorageAction.reuse: '使用已有目录',
                    if (ready) _StorageAction.migrate: '迁移数据',
                  }.entries)
                    OreButton(
                      size: OreButtonSize.sm,
                      variant: OreButtonVariant.secondary,
                      onPressed: blocked ? null : () => choose(entry.key),
                      child: Text(entry.value),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            OreButton(
              size: OreButtonSize.sm,
              variant: OreButtonVariant.secondary,
              onPressed: blocked
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      _copyPath();
                    },
              child: const Text('复制路径'),
            ),
            OreButton(
              size: OreButtonSize.sm,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _storageCard(DevelopmentStorage storage, bool ready, bool blocked) =>
      OreCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('开发数据目录', style: OreTheme.of(context).typography.choiceTitle),
            const SizedBox(height: 8),
            Text(
              storage.paths.root,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: OreTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 6),
            Text(
              ready ? '目录已就绪' : (_status?.problem ?? '使用默认位置，或选择其他磁盘。'),
              style: OreTheme.of(context).typography.caption.copyWith(
                color: _status?.problem != null
                    ? Theme.of(context).colorScheme.error
                    : OreTheme.of(context).colors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!ready)
                  OreButton(
                    size: OreButtonSize.sm,
                    onPressed: blocked
                        ? null
                        : () => _run(() => storage.initialize(), '开发目录已创建。'),
                    child: const Text('创建此目录'),
                  ),
                OreButton(
                  size: OreButtonSize.sm,
                  variant: OreButtonVariant.secondary,
                  onPressed: blocked ? null : _manageStorage,
                  child: const Text('管理目录'),
                ),
                if (ready)
                  OreButton(
                    size: OreButtonSize.sm,
                    variant: OreButtonVariant.secondary,
                    onPressed: blocked
                        ? null
                        : () => _run(
                            () => storage.reveal(storage.paths.root),
                            '已打开目录。',
                          ),
                    child: const Text('打开目录'),
                  ),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final storage = _storage;
    final ready = _status?.initialized == true;
    final blocked = _busy || _environmentActive;
    final messages = <Widget>[
      if (_busy)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OreProgressBar(value: _progress?.fraction),
              const SizedBox(height: 6),
              Text(_progress?.message ?? '正在读取开发环境…'),
            ],
          ),
        ),
      if (_error != null) _message(_error!, error: true),
      if (_notice != null) _message(_notice!),
    ];
    final storageCard = storage == null
        ? null
        : _storageCard(storage, ready, blocked);
    return Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '本机开发环境',
                  style: OreTheme.of(context).typography.choiceTitle,
                ),
              ),
              OreButton(
                size: OreButtonSize.sm,
                variant: OreButtonVariant.secondary,
                onPressed: blocked ? null : _load,
                child: const Text('刷新状态'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '安装环境与游戏 → 导入项目 → 启动测试',
            style: OreTheme.of(context).typography.caption.copyWith(
              color: OreTheme.of(context).colors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ready && storage != null
                ? DevelopmentEnvironmentPanel(
                    key: ValueKey(storage.paths.root),
                    storage: storage,
                    storageSection: storageCard,
                    statusSection: messages.isEmpty
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: messages,
                          ),
                    cookieProvider: () =>
                        LoginCookieHelper.buildCookieHeader(allowCache: false),
                    onLogin: () async {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                    onActivity: (active) {
                      if (mounted) setState(() => _environmentActive = active);
                    },
                  )
                : ListView(children: [?storageCard, ...messages]),
          ),
        ],
      ),
    );
  }
}

class _DevelopmentPathDialog extends StatefulWidget {
  const _DevelopmentPathDialog({required this.action, required this.current});
  final _StorageAction action;
  final String current;
  @override
  State<_DevelopmentPathDialog> createState() => _DevelopmentPathDialogState();
}

class _DevelopmentPathDialogState extends State<_DevelopmentPathDialog> {
  final _path = TextEditingController();
  bool _picking = false;
  String? _error;
  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择开发数据目录',
      );
      if (selected != null && mounted) setState(() => _path.text = selected);
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开目录选择器，可以直接输入路径。');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.action) {
      _StorageAction.initialize => '选择新目录',
      _StorageAction.reuse => '使用已有目录',
      _StorageAction.migrate => '迁移数据',
    };
    final description = switch (widget.action) {
      _StorageAction.initialize => '选择空文件夹。切换后原目录仍保留，可通过“使用已有目录”重新加载。',
      _StorageAction.reuse => '选择本应用之前创建的开发数据根目录，继续使用已有游戏和存档。',
      _StorageAction.migrate => '请先关闭游戏。复制并校验成功后切换位置，旧目录保留；新旧目录不能互相包含。',
    };
    return OreAlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 12),
          OreTextField(
            controller: _path,
            enabled: !_picking,
            hintText: '输入文件夹的完整路径',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          OreButton(
            variant: OreButtonVariant.secondary,
            onPressed: _picking ? null : _browse,
            child: Text(_picking ? '正在选择…' : '浏览文件夹'),
          ),
          const SizedBox(height: 12),
          const Text('当前目录'),
          OreSelectableText(widget.current),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        OreButton(
          variant: OreButtonVariant.secondary,
          onPressed: _picking ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        OreButton(
          onPressed: _picking || _path.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _path.text.trim()),
          child: Text(
            widget.action == _StorageAction.migrate ? '开始迁移' : '使用此目录',
          ),
        ),
      ],
    );
  }
}
