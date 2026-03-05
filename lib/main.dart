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

  static const _titles = [
    '收益汇总',
    'Mod 列表',
    '设置',
  ];

  final _pages = const [
    IncomePage(),
    PlaceholderPage(
      title: 'Mod 列表',
      description: '占位：后续支持 Mod 维度管理与筛选。',
      icon: Icons.view_list,
    ),
    PlaceholderPage(
      title: '设置',
      description: '占位：后续支持导出、缓存与高级选项。',
      icon: Icons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (isWide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index]),
        ),
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
              child: IndexedStack(
                index: _index,
                children: _pages,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
      ),
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.query_stats),
            label: '收益',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.view_list),
            label: 'Mod',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '设置',
          ),
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
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
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

class IncomePage extends StatefulWidget {
  const IncomePage({super.key});

  @override
  State<IncomePage> createState() => _IncomePageState();
}

class _IncomePageState extends State<IncomePage> {
  final _categoryController = TextEditingController(text: 'pe');
  final _dateFormat = DateFormat('yyyy-MM-dd');

  DateTimeRange? _range;
  bool _isThirdParty = false;
  bool _loading = false;
  String? _error;
  String _loginStatus = '未登录';
  int _cookieCount = 0;

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
    _refreshLoginStatus();
  }

  @override
  void dispose() {
    _categoryController.dispose();
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
    final initialStart = DateTime(now.year, now.month, now.day);
    final initialEnd = initialStart;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range ??
          DateTimeRange(
            start: initialStart,
            end: initialEnd,
          ),
    );
    if (picked != null) {
      setState(() {
        _range = picked;
      });
    }
  }

  Future<void> _openLoginWebView() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const LoginWebViewPage(),
      ),
    );
    if (!mounted) {
      return;
    }
    if (updated == true) {
      await _refreshLoginStatus();
      setState(() => _error = null);
    }
  }

  Future<void> _runQuery() async {
    final category = _categoryController.text.trim();
    final range = _range;

    final cookieHeader = await _loadCookieHeader();
    if (cookieHeader.isEmpty) {
      setState(() => _error = '请先通过 WebView 登录。');
      return;
    }
    if (category.isEmpty) {
      setState(() => _error = '请填写类别（如 pe / java）。');
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
      category: category,
      isThirdParty: _isThirdParty,
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

      const batchSize = 4;
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '登录状态: $_loginStatus',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loading ? null : _openLoginWebView,
                    icon: const Icon(Icons.login),
                    label: const Text('WebView 登录'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '登录信息保存在本机 WebView Cookie 中，不在界面暴露。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: '类别 (pe/java 等)',
                  hintText: '例如 pe',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('包含第三方 Mod'),
                value: _isThirdParty,
                onChanged: (value) => setState(() => _isThirdParty = value),
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
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              if (_summaries.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '汇总',
                          style: theme.textTheme.titleMedium,
                        ),
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
                Text(
                  '按 Mod 明细 (按钻石降序)',
                  style: theme.textTheme.titleMedium,
                ),
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

  Future<void> _refreshLoginStatus() async {
    final cookieHeader = await _loadCookieHeader();
    if (!mounted) {
      return;
    }
    setState(() {
      _cookieCount = cookieHeader.isEmpty ? 0 : cookieHeader.split(';').length;
      _loginStatus = _cookieCount > 0 ? '已登录 ($_cookieCount)' : '未登录';
    });
  }

  Future<String> _loadCookieHeader() async {
    final manager = CookieManager.instance();
    final cookieMap = <String, String>{};
    final urls = [
      WebUri('https://mc-launcher.webapp.163.com/'),
      WebUri('https://mcdev.webapp.163.com/'),
    ];

    for (final url in urls) {
      final cookies = await manager.getCookies(url: url);
      for (final cookie in cookies) {
        final name = cookie.name;
        if (name.isEmpty) {
          continue;
        }
        cookieMap[name] = cookie.value;
      }
    }

    if (cookieMap.isEmpty) {
      return '';
    }
    return cookieMap.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}

enum _PriceKind {
  diamond,
  emerald,
  other,
}

_PriceKind _priceKind(String? raw) {
  if (raw == null || raw.isEmpty) {
    return _PriceKind.other;
  }
  final value = raw.toLowerCase();
  if (value.contains('diamond') || value.contains('钻石')) {
    return _PriceKind.diamond;
  }
  if (value.contains('emerald') || value.contains('绿宝石') || value.contains('point')) {
    return _PriceKind.emerald;
  }
  return _PriceKind.other;
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
    final manager = CookieManager.instance();
    final cookieMap = <String, String>{};

    final urls = [
      WebUri('https://mc-launcher.webapp.163.com/'),
      WebUri('https://mcdev.webapp.163.com/'),
    ];

    for (final url in urls) {
      final cookies = await manager.getCookies(url: url);
      for (final cookie in cookies) {
        final name = cookie.name;
        if (name.isEmpty) {
          continue;
        }
        cookieMap[name] = cookie.value;
      }
    }

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
          TextButton(
            onPressed: _syncCookies,
            child: const Text('完成登录'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: Text(
              _status,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
  McDevApi({
    required this.cookie,
    required this.category,
    required this.isThirdParty,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String cookie;
  final String category;
  final bool isThirdParty;
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
          'is_third_party': isThirdParty ? 'true' : 'false',
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

  Future<IncomeSummary> fetchIncome(ModItem mod, DateTimeRange range) async {
    final beginUtc = _startOfDay(range.start).toUtc().toIso8601String();
    final endUtc = _endOfDay(range.end).toUtc().toIso8601String();
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/items/categories/$category/${mod.id}/incomes/',
      {
        'begin_time': beginUtc,
        'end_time': endUtc,
      },
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

class McDevException implements Exception {
  McDevException(this.message, this.uri);

  final String message;
  final Uri uri;

  @override
  String toString() => '$message (${uri.toString()})';
}
