part of mcdev_income_app;

final _sensitiveKeyPattern = RegExp(
  r'(token|secret|password|passwd|cookie|session|auth|sid|uid|email|phone|mobile)',
  caseSensitive: false,
);

class _InfoItem {
  const _InfoItem(this.label, this.value);

  final String label;
  final String value;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = false;
  String _statusText = '未登录';
  int _cookieCount = 0;
  DateTime? _checkedAt;

  bool _devLoading = false;
  String? _devError;
  DeveloperProfile? _developerProfile;

  final _timeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _refreshStatus().then((loggedIn) {
      if (loggedIn) {
        _loadDeveloperProfile();
      }
    });
  }

  Future<bool> _refreshStatus() async {
    setState(() => _loading = true);
    final cookies = await LoginCookieHelper.readCookies();
    if (!mounted) {
      return false;
    }
    final count = cookies.length;
    final loggedIn = count > 0;
    setState(() {
      _cookieCount = count;
      _statusText = loggedIn ? '已登录' : '未登录';
      _checkedAt = DateTime.now();
      _loading = false;
    });
    return loggedIn;
  }

  Future<void> _openLoginWebView() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const LoginWebViewPage()),
    );
    if (result == true) {
      await _refreshStatus();
      await _loadDeveloperProfile();
    }
  }

  Future<void> _openDeveloperDetails() async {
    if (_devLoading) {
      return;
    }
    if (_developerProfile == null) {
      await _loadDeveloperProfile();
    }
    if (!mounted) {
      return;
    }
    final profile = _developerProfile;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获取到开发者信息，请稍后重试。')),
      );
      return;
    }

    final detailItems = _buildDeveloperInfoItems(profile)
        .where((item) => item.label != '昵称' && item.label != '简介')
        .toList();

    if (detailItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无更多可显示的开发者信息。')),
      );
      return;
    }

    final isWide = MediaQuery.of(context).size.width >= 900;
    if (isWide) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '开发者更多信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: detailItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = detailItems[index];
                          return ListTile(
                            dense: true,
                            title: Text(item.label),
                            subtitle: Text(item.value),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '开发者更多信息',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: detailItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = detailItems[index];
                        return ListTile(
                          dense: true,
                          title: Text(item.label),
                          subtitle: Text(item.value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _loadDeveloperProfile() async {
    setState(() {
      _devLoading = true;
      _devError = null;
    });

    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _devLoading = false;
        _devError = '请先登录后再获取开发者信息。';
      });
      return;
    }

    final api = McDevApi(cookie: cookieHeader, category: 'pe');
    try {
      final profile = await api.fetchDeveloperProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _developerProfile = profile;
        _devLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _devLoading = false;
        _devError = error.toString();
      });
    } finally {
      api.close();
    }
  }

  List<_InfoItem> _buildDeveloperInfoItems(DeveloperProfile profile) {
    final items = <_InfoItem>[];
    final usedKeys = <String>{};

    final status = profile.status;
    if (status != null && status.isNotEmpty) {
      items.add(_InfoItem('作者状态', _mapAuthorStatus(status)));
    }

    final updatedAt = _formatIso(profile.updatedAt);
    if (updatedAt != null) {
      items.add(_InfoItem('资料更新时间', updatedAt));
    }

    final bio = profile.bio == null ? null : _stripHtml(profile.bio!);
    if (bio != null && bio.isNotEmpty) {
      items.add(_InfoItem('简介', bio));
    }

    final user = profile.userRaw;
    if (user != null) {
      final nickname = _pickStringEntry(user, [
        'nickname',
        'nick_name',
        'user_name',
        'username',
        'name',
        'display_name',
      ]);
      if (nickname != null) {
        items.add(_InfoItem('昵称', nickname.value));
        usedKeys.add(nickname.key);
      }

      final userId = _pickStringEntry(user, [
        'uid',
        'user_id',
        'id',
        'account_id',
      ]);
      if (userId != null) {
        items.add(_InfoItem('账号ID', userId.value));
        usedKeys.add(userId.key);
      }

      final realName =
          _pickStringEntry(user, ['real_name', 'realname', 'realName']);
      if (realName != null) {
        items.add(_InfoItem('真实姓名', realName.value));
        usedKeys.add(realName.key);
      }

      final isRealName = _pickStringEntry(user, ['is_unirealname']);
      if (isRealName != null) {
        items.add(_InfoItem('实名认证', _formatBool(isRealName.value)));
        usedKeys.add(isRealName.key);
      }

      final email = _pickStringEntry(user, ['email']);
      if (email != null) {
        items.add(_InfoItem('邮箱', _maskValue(email.key, email.value)));
        usedKeys.add(email.key);
      }

      final phone = _pickStringEntry(user, ['mobile', 'phone']);
      if (phone != null) {
        items.add(_InfoItem('手机号', _maskValue(phone.key, phone.value)));
        usedKeys.add(phone.key);
      }

      final qq = _pickStringEntry(user, ['qq']);
      if (qq != null) {
        items.add(_InfoItem('QQ', _maskValue(qq.key, qq.value)));
        usedKeys.add(qq.key);
      }

      final province = _pickStringEntry(user, ['province']);
      if (province != null) {
        items.add(_InfoItem('省份', province.value));
        usedKeys.add(province.key);
      }

      final city = _pickStringEntry(user, ['city']);
      if (city != null) {
        items.add(_InfoItem('城市', city.value));
        usedKeys.add(city.key);
      }

      final provider = _pickStringEntry(user, ['provider_name']);
      if (provider != null) {
        items.add(_InfoItem('签约主体', provider.value));
        usedKeys.add(provider.key);
      }

      final authority = _pickStringEntry(user, ['official_authority']);
      if (authority != null) {
        items.add(_InfoItem('官方资质', authority.value));
        usedKeys.add(authority.key);
      }

      final cardNo = _pickStringEntry(user, ['card_no', 'id_card', 'idcard']);
      if (cardNo != null) {
        items.add(_InfoItem('证件号', _maskValue(cardNo.key, cardNo.value)));
        usedKeys.add(cardNo.key);
      }

      final enterpriseApplying =
          _pickStringEntry(user, ['is_enterprise_applying']);
      if (enterpriseApplying != null) {
        items.add(
          _InfoItem('企业认证申请中', _formatBool(enterpriseApplying.value)),
        );
        usedKeys.add(enterpriseApplying.key);
      }

      final enterpriseExpired =
          _pickStringEntry(user, ['is_enterprise_expired']);
      if (enterpriseExpired != null) {
        items.add(
          _InfoItem('企业认证已过期', _formatBool(enterpriseExpired.value)),
        );
        usedKeys.add(enterpriseExpired.key);
      }

      final needEnterprise = _pickStringEntry(user, ['need_enterprise_apply']);
      if (needEnterprise != null) {
        items.add(_InfoItem('需要企业认证', _formatBool(needEnterprise.value)));
        usedKeys.add(needEnterprise.key);
      }

      final enterpriseDeadline =
          _pickStringEntry(user, ['enterprise_deadline']);
      if (enterpriseDeadline != null) {
        items.add(_InfoItem('企业认证到期', enterpriseDeadline.value));
        usedKeys.add(enterpriseDeadline.key);
      }
    }

    return items;
  }

  _InfoItem? _findItem(List<_InfoItem> items, String label) {
    for (final item in items) {
      if (item.label == label) {
        return item;
      }
    }
    return null;
  }

  String _mapAuthorStatus(String raw) {
    switch (raw.toLowerCase()) {
      case 'accept':
        return '已通过';
      case 'pending':
        return '审核中';
      case 'reject':
        return '未通过';
      default:
        return raw;
    }
  }

  String? _formatIso(String? iso) {
    if (iso == null || iso.isEmpty) {
      return null;
    }
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _stripHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  String _maskValue(String key, String value) {
    if (key.toLowerCase().contains('email')) {
      final parts = value.split('@');
      if (parts.length == 2) {
        final name = parts.first;
        final domain = parts.last;
        if (name.length <= 2) {
          return '${name.substring(0, 1)}***@$domain';
        }
        return '${name.substring(0, 2)}***@${domain}';
      }
    }
    if (key.toLowerCase().contains('qq')) {
      if (value.length >= 4) {
        return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
      }
    }
    if (key.toLowerCase().contains('phone') ||
        key.toLowerCase().contains('mobile')) {
      if (value.length >= 7) {
        return '${value.substring(0, 3)}****${value.substring(value.length - 2)}';
      }
    }
    if (key.toLowerCase().contains('card')) {
      if (value.length >= 8) {
        return '${value.substring(0, 4)}********${value.substring(value.length - 2)}';
      }
    }
    return value;
  }

  String _formatBool(String raw) {
    final text = raw.toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') {
      return '是';
    }
    if (text == '0' || text == 'false' || text == 'no') {
      return '否';
    }
    return raw;
  }

  MapEntry<String, String>? _pickStringEntry(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString();
      if (text.isNotEmpty) {
        return MapEntry(key, text);
      }
    }
    return null;
  }

  int _themeModeIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 0;
      case ThemeMode.dark:
        return 1;
      case ThemeMode.system:
        return 2;
    }
  }

  ThemeMode _themeModeFromIndex(int index) {
    switch (index) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  double _choiceButtonWidth(BuildContext context, List<String> labels) {
    final ore = OreTheme.of(context);
    final style = ore.typography.label;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
    );
    var maxWidth = 0.0;
    for (final label in labels) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      if (painter.width > maxWidth) {
        maxWidth = painter.width;
      }
    }
    final horizontalPadding =
        ore.borderWidth * OreTokens.buttonPadMdHUnits * 2;
    final extraGap = OreTokens.gapSm * 2;
    return maxWidth + horizontalPadding + extraGap;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ore = OreTheme.of(context);
    final themeNotifier = AppThemeController.of(context);
    final themeMode = themeNotifier.value;
    final themeLabels = const ['浅色模式', '深色模式', '跟随系统'];
    final themeIndex = _themeModeIndex(themeMode);
    final themeButtonWidth = _choiceButtonWidth(context, themeLabels);
    final actionButtonWidth = OreTokens.controlHeightMd * 5;
    final checkedAt = _checkedAt == null
        ? '未检查'
        : _timeFormat.format(_checkedAt!);
    final devItems = _developerProfile == null
        ? null
        : _buildDeveloperInfoItems(_developerProfile!);
    final nicknameItem =
        devItems == null ? null : _findItem(devItems, '昵称');
    final bioItem = devItems == null ? null : _findItem(devItems, '简介');

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题模式', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  OreChoiceButtons(
                    items:
                        themeLabels.map((label) => Text(label)).toList(),
                    selectedIndex: themeIndex,
                    onChanged: (value) {
                      final next = _themeModeFromIndex(value);
                      if (next == themeNotifier.value) {
                        return;
                      }
                      themeNotifier.value = next;
                      ThemeModeStore.save(next);
                    },
                    buttonWidth: themeButtonWidth,
                  ),
                ],
              ),
            ),
          ),
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('登录状态', style: theme.textTheme.titleMedium),
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('状态: $_statusText'),
                  Text('Cookie 数量: $_cookieCount'),
                  const SizedBox(height: 4),
                  Text('上次检查: $checkedAt', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _openLoginWebView,
                        icon: const Icon(Icons.login),
                        label: const Text('WebView 登录'),
                        width: actionButtonWidth,
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () async {
                                final loggedIn = await _refreshStatus();
                                if (loggedIn) {
                                  await _loadDeveloperProfile();
                                }
                              },
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新状态'),
                        width: actionButtonWidth,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          OreStrip(
            tone: OreStripTone.dark,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '开发者信息',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (_devLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_developerProfile == null && !_devLoading)
                    Text(
                      _statusText == '已登录'
                          ? '未加载到开发者信息，请点击“刷新信息”。'
                          : '请先登录后获取开发者信息。',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (_devError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _devError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (_developerProfile != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_developerProfile!.avatarUrl != null)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: ore.colors.border,
                                width: ore.borderWidth,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.zero,
                              child: Image.network(
                                _developerProfile!.avatarUrl!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        if (_developerProfile!.avatarUrl != null)
                          const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nicknameItem?.value ?? '昵称未获取',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                bioItem?.value ?? '暂无简介',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _devLoading ? null : _loadDeveloperProfile,
                        icon: const Icon(Icons.person_search),
                        label:
                            Text(_developerProfile == null ? '加载信息' : '刷新信息'),
                        width: actionButtonWidth,
                      ),
                      ElevatedButton.icon(
                        onPressed: _devLoading ? null : _openDeveloperDetails,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('查看更多'),
                        width: actionButtonWidth,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
