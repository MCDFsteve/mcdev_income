import 'dart:convert';
import 'dart:math';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const McDevIncomeApp());
}

class McDevIncomeApp extends StatelessWidget {
  const McDevIncomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MC开发者收益助手',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['收益汇总', 'Mod 列表', '设置'];

  final _pages = const [
    IncomePage(),
    PlaceholderPage(
      title: 'Mod 列表',
      description: '占位：后续支持 Mod 维度管理与筛选。',
      icon: Icons.view_list,
    ),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (isWide) {
      return Scaffold(
        appBar: AppBar(title: Text(_titles[_index])),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.query_stats),
                  label: Text('收益'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.view_list),
                  label: Text('Mod'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text('设置'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(index: _index, children: _pages),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.query_stats), label: '收益'),
          BottomNavigationBarItem(icon: Icon(Icons.view_list), label: 'Mod'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangePickerPanel extends StatefulWidget {
  const _RangePickerPanel({
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_RangePickerPanel> createState() => _RangePickerPanelState();
}

class _RangePickerPanelState extends State<_RangePickerPanel> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  final _format = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.initialStart;
    _rangeEnd = widget.initialEnd;
  }

  void _onDateTapped(DateTime date) {
    if (_rangeStart == null || _rangeEnd != null) {
      setState(() {
        _rangeStart = date;
        _rangeEnd = null;
      });
      return;
    }
    var start = _rangeStart!;
    var end = date;
    if (end.isBefore(start)) {
      final temp = start;
      start = end;
      end = temp;
    }
    Navigator.of(context).pop(DateTimeRange(start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _rangeStart == null
        ? '未选'
        : _format.format(_rangeStart!);
    final endLabel = _rangeEnd == null ? '未选' : _format.format(_rangeEnd!);
    final initialDate = _rangeEnd ?? _rangeStart ?? DateTime.now();

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
                    '选择时间范围',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('开始: $startLabel')),
                Expanded(child: Text('结束: $endLabel')),
              ],
            ),
            const SizedBox(height: 8),
            CalendarDatePicker(
              initialDate: initialDate,
              firstDate: DateTime(2020, 1, 1),
              lastDate: DateTime(DateTime.now().year + 1, 12, 31),
              onDateChanged: _onDateTapped,
            ),
            const SizedBox(height: 4),
            Text('点击起止日期后自动查询', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class LoginCookieHelper {
  static final _cookieUrls = [
    WebUri('https://mc-launcher.webapp.163.com/'),
    WebUri('https://mcdev.webapp.163.com/'),
  ];

  static Future<Map<String, String>> readCookies() async {
    final manager = CookieManager.instance();
    final cookieMap = <String, String>{};

    for (final url in _cookieUrls) {
      final cookies = await manager.getCookies(url: url);
      for (final cookie in cookies) {
        final name = cookie.name;
        if (name.isEmpty) {
          continue;
        }
        cookieMap[name] = cookie.value;
      }
    }

    return cookieMap;
  }

  static Future<String> buildCookieHeader() async {
    final cookies = await readCookies();
    if (cookies.isEmpty) {
      return '';
    }
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkedAt = _checkedAt == null
        ? '未检查'
        : _timeFormat.format(_checkedAt!);
    final devItems = _developerProfile == null
        ? null
        : _buildDeveloperInfoItems(_developerProfile!);
    final nicknameItem =
        devItems == null ? null : _findItem(devItems, '昵称');
    final bioItem = devItems == null ? null : _findItem(devItems, '简介');
    final detailItems = devItems == null
        ? const <_InfoItem>[]
        : devItems.where((item) {
            return item.label != '昵称' && item.label != '简介';
          }).toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: NetworkImage(
                              _developerProfile!.avatarUrl!,
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
                    if (detailItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ...detailItems.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${item.label}: ${item.value}'),
                        );
                      }),
                    ],
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _devLoading ? null : _loadDeveloperProfile,
                        icon: const Icon(Icons.person_search),
                        label: Text(
                          _developerProfile == null ? '加载信息' : '刷新信息',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('说明', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '仅支持 WebView 登录，不会展示或手动输入 Cookie。',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录信息保存在 WebView 存储中，正常情况下重启应用仍可使用。',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '如提示未登录，请重新打开 WebView 登录并进入收益页面。',
                    style: theme.textTheme.bodySmall,
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

class IncomePage extends StatefulWidget {
  const IncomePage({super.key});

  @override
  State<IncomePage> createState() => _IncomePageState();
}

class _IncomePageState extends State<IncomePage> {
  final _dateFormat = DateFormat('yyyy-MM-dd');

  DateTimeRange? _range;
  _Category _category = _Category.pe;
  bool _loading = false;
  String? _error;

  int _totalDiamonds = 0;
  int _totalPoints = 0;
  int _processed = 0;
  int _totalMods = 0;
  int _diamondPricedMods = 0;
  int _emeraldPricedMods = 0;
  int _otherPricedMods = 0;
  List<IncomeSummary> _summaries = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _rangeLabel() {
    final range = _range;
    if (range == null) {
      return '未选择';
    }
    return '${_dateFormat.format(range.start)} ~ ${_dateFormat.format(range.end)}';
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initialStart =
        _range?.start ?? DateTime(now.year, now.month, now.day);
    final initialEnd = _range?.end ?? initialStart;
    final isWide = MediaQuery.of(context).size.width >= 900;

    DateTimeRange? picked;
    if (isWide) {
      picked = await showDialog<DateTimeRange>(
        context: context,
        builder: (context) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _RangePickerPanel(
                initialStart: initialStart,
                initialEnd: initialEnd,
              ),
            ),
          );
        },
      );
    } else {
      picked = await showModalBottomSheet<DateTimeRange>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _RangePickerPanel(
              initialStart: initialStart,
              initialEnd: initialEnd,
            ),
          );
        },
      );
    }

    if (picked != null) {
      setState(() {
        _range = picked;
      });
      if (!_loading) {
        final cookieHeader = await LoginCookieHelper.buildCookieHeader();
        if (cookieHeader.isNotEmpty) {
          await _runQuery();
        }
      }
    }
  }

  Future<void> _runQuery() async {
    final range = _range;

    final cookieHeader = await LoginCookieHelper.buildCookieHeader();
    if (cookieHeader.isEmpty) {
      setState(() => _error = '请先到“设置”里通过 WebView 登录。');
      return;
    }
    if (range == null) {
      setState(() => _error = '请选择时间范围。');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _summaries = [];
      _totalDiamonds = 0;
      _totalPoints = 0;
      _processed = 0;
      _totalMods = 0;
      _diamondPricedMods = 0;
      _emeraldPricedMods = 0;
      _otherPricedMods = 0;
    });

    final api = McDevApi(
      cookie: cookieHeader,
      category: _categoryValue(_category),
    );

    try {
      final mods = await api.fetchMods();
      if (!mounted) {
        return;
      }
      if (mods.isEmpty) {
        setState(() {
          _loading = false;
          _error = '未获取到任何 Mod，请确认账号权限与类别。';
        });
        return;
      }

      final isWide = MediaQuery.of(context).size.width >= 900;
      final batchSize = isWide ? 12 : 6;
      setState(() {
        _totalMods = mods.length;
      });

      final summaries = <IncomeSummary>[];
      int diamonds = 0;
      int points = 0;
      int diamondPriced = 0;
      int emeraldPriced = 0;
      int otherPriced = 0;
      int processed = 0;

      for (var i = 0; i < mods.length; i += batchSize) {
        final batch = mods.sublist(i, min(i + batchSize, mods.length));
        final results = await Future.wait(
          batch.map((mod) => api.fetchIncomeWithRetry(mod, range)),
        );
        if (!mounted) {
          return;
        }
        processed += results.length;
        for (final summary in results) {
          if (summary.error == null) {
            summaries.add(summary);
            diamonds += summary.totalDiamonds;
            points += summary.totalPoints;
            final kind = _priceKind(summary.priceType);
            switch (kind) {
              case _PriceKind.diamond:
                diamondPriced += 1;
                break;
              case _PriceKind.emerald:
                emeraldPriced += 1;
                break;
              case _PriceKind.other:
                otherPriced += 1;
                break;
            }
          }
        }

        setState(() {
          _processed = processed;
          _summaries = List.of(summaries);
          _totalDiamonds = diamonds;
          _totalPoints = points;
          _diamondPricedMods = diamondPriced;
          _emeraldPricedMods = emeraldPriced;
          _otherPricedMods = otherPriced;
        });
      }

      summaries.sort((a, b) => b.totalDiamonds.compareTo(a.totalDiamonds));

      setState(() {
        _summaries = summaries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类别', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            SegmentedButton<_Category>(
              segments: const [
                ButtonSegment(value: _Category.pe, label: Text('PE')),
                ButtonSegment(value: _Category.java, label: Text('Java')),
              ],
              selected: {_category},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                if (value.isNotEmpty) {
                  setState(() => _category = value.first);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '时间范围: ${_rangeLabel()}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: _loading ? null : _pickRange,
                  child: const Text('选择日期'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _runQuery,
                icon: const Icon(Icons.search),
                label: const Text('开始查询'),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('已处理 $_processed / $_totalMods'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            if (_summaries.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('汇总', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('总钻石: $_totalDiamonds'),
                      Text('总绿宝石: $_totalPoints'),
                      const SizedBox(height: 4),
                      Text('钻石定价 Mod: $_diamondPricedMods'),
                      Text('绿宝石定价 Mod: $_emeraldPricedMods'),
                      if (_otherPricedMods > 0)
                        Text('其他定价 Mod: $_otherPricedMods'),
                      const SizedBox(height: 8),
                      Text(
                        '提示: 查询时间会转换为 UTC 时间提交到接口。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('按 Mod 明细 (按钻石降序)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final summary = _summaries[index];
                  return ListTile(
                    title: Text(summary.itemName),
                    subtitle: Text(
                      '钻石 ${summary.totalDiamonds} · 绿宝石 ${summary.totalPoints} · 订单 ${summary.orderCount}',
                    ),
                    trailing: Text('#${index + 1}'),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _summaries.length,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _PriceKind { diamond, emerald, other }

_PriceKind _priceKind(String? raw) {
  if (raw == null || raw.isEmpty) {
    return _PriceKind.other;
  }
  final value = raw.toLowerCase();
  if (value.contains('diamond') || value.contains('钻石')) {
    return _PriceKind.diamond;
  }
  if (value.contains('emerald') ||
      value.contains('绿宝石') ||
      value.contains('point')) {
    return _PriceKind.emerald;
  }
  return _PriceKind.other;
}

enum _Category { pe, java }

String _categoryValue(_Category category) {
  switch (category) {
    case _Category.pe:
      return 'pe';
    case _Category.java:
      return 'java';
  }
}

class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key});

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String _status = '请在此页面登录，并进入收益页面后点击“完成登录”。';

  Future<void> _syncCookies() async {
    final cookieMap = await LoginCookieHelper.readCookies();
    if (!mounted) {
      return;
    }

    if (cookieMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未读取到 Cookie，请确认已登录并打开收益页面。')),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView 登录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
          TextButton(onPressed: _syncCookies, child: const Text('完成登录')),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialSettings: InAppWebViewSettings(
                sharedCookiesEnabled: true,
                incognito: false,
                cacheEnabled: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri('https://mcdev.webapp.163.com/'),
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (_, __) {
                setState(() {
                  _loading = true;
                });
              },
              onLoadStop: (_, __) {
                setState(() {
                  _loading = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class McDevApi {
  McDevApi({required this.cookie, required this.category, http.Client? client})
    : _client = client ?? http.Client();

  final String cookie;
  final String category;
  final http.Client _client;
  final Random _random = Random();

  void close() {
    _client.close();
  }

  Future<List<ModItem>> fetchMods() async {
    const span = 50;
    var start = 0;
    int? count;
    final items = <ModItem>[];

    while (true) {
      final uri = Uri.https(
        'mc-launcher.webapp.163.com',
        '/items/categories/$category/',
        {
          'is_third_party': 'false',
          'start': start.toString(),
          'span': span.toString(),
        },
      );
      final payload = await _getJson(uri);
      final data = payload['data'];
      List<dynamic> list = [];
      if (data is Map<String, dynamic>) {
        final rawList = data['item'];
        if (rawList is List) {
          list = rawList;
        }
        count ??= (data['count'] as num?)?.toInt();
      }

      for (final entry in list) {
        if (entry is Map<String, dynamic>) {
          final id = entry['item_id']?.toString();
          if (id == null || id.isEmpty) {
            continue;
          }
          final priceValue = entry['price'];
          int? price;
          if (priceValue is num) {
            price = priceValue.toInt();
          } else if (priceValue != null) {
            price = int.tryParse(priceValue.toString());
          }
          if (price != null && price <= 0) {
            continue;
          }
          final name = entry['item_name']?.toString() ?? id;
          final priceType = entry['price_type']?.toString();
          items.add(ModItem(id: id, name: name, priceType: priceType));
        }
      }

      if (count != null && items.length >= count) {
        break;
      }
      if (list.length < span) {
        break;
      }
      start += span;
    }

    return items;
  }

  Future<DeveloperProfile> fetchDeveloperProfile() async {
    Map<String, dynamic>? authorData;
    Map<String, dynamic>? userData;
    Object? authorError;
    Object? userError;

    try {
      final authorPayload = await _getJson(
        Uri.https('mc-launcher.webapp.163.com', '/users/author_info'),
      );
      final data = authorPayload['data'];
      if (data is Map<String, dynamic>) {
        authorData = data;
      } else if (authorPayload['status']?.toString() == 'ok') {
        authorData = const {};
      }
    } catch (error) {
      authorError = error;
    }

    try {
      final userPayload = await _getJson(
        Uri.https('mc-launcher.webapp.163.com', '/users/me'),
      );
      final data = userPayload['data'];
      if (data is Map<String, dynamic>) {
        userData = data;
      } else if (userPayload['status']?.toString() == 'ok') {
        userData = const {};
      }
    } catch (error) {
      userError = error;
    }

    if (authorData == null && userData == null) {
      if (authorError != null) {
        throw authorError;
      }
      if (userError != null) {
        throw userError;
      }
      throw McDevException(
        '未获取到开发者信息',
        Uri.https('mc-launcher.webapp.163.com', '/users/author_info'),
      );
    }

    final avatarUrl = authorData?['head_img']?.toString();
    final bio = authorData?['content']?.toString();
    final status = authorData?['status']?.toString();
    final updatedAt = authorData?['update_time']?.toString();

    return DeveloperProfile(
      avatarUrl: avatarUrl,
      bio: bio,
      status: status,
      updatedAt: updatedAt,
      authorRaw: authorData,
      userRaw: userData,
    );
  }

  Future<IncomeSummary> fetchIncome(ModItem mod, DateTimeRange range) async {
    final beginUtc = _startOfDay(range.start).toUtc().toIso8601String();
    final endUtc = _endOfDay(range.end).toUtc().toIso8601String();
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/items/categories/$category/${mod.id}/incomes/',
      {'begin_time': beginUtc, 'end_time': endUtc},
    );

    final payload = await _getJson(uri);
    final status = payload['status']?.toString();
    if (status != null && status != 'ok') {
      final message =
          payload['message']?.toString() ?? payload['msg']?.toString() ?? '';
      throw McDevException('收益接口状态异常: $status $message', uri);
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw McDevException('收益接口返回异常: data 非对象', uri);
    }

    final totalDiamonds = (data['total_diamonds'] as num?)?.toInt() ?? 0;
    final totalPoints = (data['total_points'] as num?)?.toInt() ?? 0;
    final count = (data['count'] as num?)?.toInt() ?? 0;

    return IncomeSummary(
      itemId: mod.id,
      itemName: mod.name,
      totalDiamonds: totalDiamonds,
      totalPoints: totalPoints,
      orderCount: count,
      priceType: mod.priceType,
    );
  }

  Future<IncomeSummary> fetchIncomeWithRetry(
    ModItem mod,
    DateTimeRange range,
  ) async {
    const maxRetries = 2;
    Object? lastError;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await fetchIncome(mod, range);
      } catch (error) {
        lastError = error;
        if (attempt >= maxRetries) {
          break;
        }
        final backoffMs = 400 * (1 << attempt) + _random.nextInt(200);
        await Future.delayed(Duration(milliseconds: backoffMs));
      }
    }

    return IncomeSummary(
      itemId: mod.id,
      itemName: mod.name,
      totalDiamonds: 0,
      totalPoints: 0,
      orderCount: 0,
      error: '重试失败: ${lastError.toString()}',
      priceType: mod.priceType,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: {
        'Cookie': cookie,
        'Accept': 'application/json',
        'Referer': 'https://mcdev.webapp.163.com/',
      },
    );
    if (response.statusCode != 200) {
      final snippet = response.body.length > 300
          ? response.body.substring(0, 300)
          : response.body;
      throw McDevException('请求失败: ${response.statusCode} $snippet', uri);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      final snippet = response.body.length > 300
          ? response.body.substring(0, 300)
          : response.body;
      throw McDevException('响应不是 JSON: $snippet', uri);
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw McDevException('响应不是 JSON 对象', uri);
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _endOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  }
}

class ModItem {
  ModItem({required this.id, required this.name, this.priceType});

  final String id;
  final String name;
  final String? priceType;
}

class IncomeSummary {
  IncomeSummary({
    required this.itemId,
    required this.itemName,
    required this.totalDiamonds,
    required this.totalPoints,
    required this.orderCount,
    this.error,
    this.priceType,
  });

  final String itemId;
  final String itemName;
  final int totalDiamonds;
  final int totalPoints;
  final int orderCount;
  final String? error;
  final String? priceType;
}

class DeveloperProfile {
  DeveloperProfile({
    this.avatarUrl,
    this.bio,
    this.status,
    this.updatedAt,
    this.authorRaw,
    this.userRaw,
  });

  final String? avatarUrl;
  final String? bio;
  final String? status;
  final String? updatedAt;
  final Map<String, dynamic>? authorRaw;
  final Map<String, dynamic>? userRaw;
}

class McDevException implements Exception {
  McDevException(this.message, this.uri);

  final String message;
  final Uri uri;

  @override
  String toString() => '$message (${uri.toString()})';
}
