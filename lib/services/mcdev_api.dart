part of mcdev_income_app;

class McDevApi {
  McDevApi({required this.cookie, required this.category, http.Client? client})
    : _client = client ?? http.Client();

  final String cookie;
  final String category;
  final http.Client _client;
  final Random _random = Random();
  static const int _refundStatusPending = 309;
  static const int _refundStatusDone = 310;

  void _logRefund(String message) {
    if (kDebugMode) {
      debugPrint('[refund] $message');
    }
  }

  void close() {
    _client.close();
  }

  bool _isPublishedStatus(String? status, dynamic weakOffline) {
    final value = status?.toLowerCase().trim() ?? '';
    final isOffline = value.contains('offline') ||
        value.contains('下架') ||
        value.contains('下线') ||
        value.contains('封禁') ||
        value.contains('违规') ||
        value.contains('驳回') ||
        value.contains('拒绝') ||
        value.contains('草稿') ||
        value.contains('待发布') ||
        value.contains('预发布');
    if (isOffline) {
      return false;
    }
    if (value.contains('online') ||
        value.contains('publish') ||
        value.contains('on_shelf') ||
        value.contains('onshelf') ||
        value.contains('已上架') ||
        value.contains('已上线') ||
        value.contains('上架') ||
        value.contains('上线') ||
        value.contains('审核') ||
        value.contains('待审') ||
        value.contains('审查') ||
        value.contains('审批') ||
        value.contains('更新') ||
        value.contains('提交') ||
        value.contains('发布中') ||
        value.contains('上架中') ||
        value.contains('上线中') ||
        value.contains('review') ||
        value.contains('pending') ||
        value.contains('audit') ||
        value.contains('updat')) {
      return true;
    }
    if (weakOffline is bool && weakOffline) {
      return true;
    }
    if (weakOffline is String && weakOffline.toLowerCase() == 'true') {
      return true;
    }
    return false;
  }

  String _formatDateId(DateTime value) {
    return DateFormat('yyyyMMdd').format(value);
  }

  Future<OverviewStats> fetchOverview() async {
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/data_analysis/overview/',
    );
    final payload = await _getJson(uri);
    final status = payload['status']?.toString();
    if (status != null && status != 'ok') {
      final message =
          payload['message']?.toString() ?? payload['msg']?.toString() ?? '';
      throw McDevException('概览接口状态异常: $status $message', uri);
    }
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw McDevException('概览接口返回异常: data 非对象', uri);
    }
    return OverviewStats.fromJson(data);
  }

  Future<List<ModItem>> fetchMods({
    bool onlyPriced = true,
    bool onlyPublished = false,
  }) async {
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
          final status = entry['status']?.toString();
          final weakOffline = entry['weak_offline'];
          final isPublished = _isPublishedStatus(status, weakOffline);
          if (onlyPublished && !isPublished) {
            continue;
          }
          if (onlyPriced && (price == null || price <= 0)) {
            continue;
          }
          final name = entry['item_name']?.toString() ?? id;
          final priceType = entry['price_type']?.toString();
          final releaseAt = _parseModReleaseAt(
            entry['online_time'] ??
                entry['shelf_time'] ??
                entry['publish_time'] ??
                entry['on_shelf_time'] ??
                entry['create_time'] ??
                entry['update_time'],
          );
          items.add(
            ModItem(
              id: id,
              name: name,
              price: price,
              priceType: priceType,
              status: status,
              weakOffline:
                  weakOffline is bool ? weakOffline : weakOffline == 'true',
              releaseAt: releaseAt,
            ),
          );
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

  Future<Map<String, int>> fetchSalesTotals({
    required List<String> itemIds,
    required DateTime startDate,
    required DateTime endDate,
    required String platform,
    required String category,
  }) async {
    if (itemIds.isEmpty) {
      return {};
    }
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/data_analysis/day_detail/',
      {
        'platform': platform,
        'category': category,
        'start_date': _formatDateId(startDate),
        'end_date': _formatDateId(endDate),
        'item_list_str': itemIds.join(','),
        'sort': 'dateid',
        'order': 'ASC',
        'start': '0',
        'span': '999999999',
        'is_need_us_rank_data': 'true',
      },
    );

    final payload = await _getJson(uri);
    final status = payload['status']?.toString();
    if (status != null && status != 'ok') {
      final message =
          payload['message']?.toString() ?? payload['msg']?.toString() ?? '';
      throw McDevException('统计接口状态异常: $status $message', uri);
    }
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw McDevException('统计接口返回异常: data 非对象', uri);
    }
    final list = data['data'];
    if (list is! List) {
      return {};
    }

      final salesById = <String, int>{};
      for (final entry in list) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final id = entry['iid']?.toString();
      if (id == null || id.isEmpty) {
        continue;
      }
      final salesRaw = entry['download_num'];
      int? sales;
      if (salesRaw is num) {
        sales = salesRaw.toInt();
      } else if (salesRaw != null) {
        sales = int.tryParse(salesRaw.toString());
      }
      if (sales == null) {
        continue;
      }
      final prev = salesById[id];
      if (prev == null || sales > prev) {
        salesById[id] = sales;
      }
    }
    return salesById;
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
    int refundPending = 0;
    int refunded = 0;
    int refundOther = 0;
    final orders = data['orders'];
    final ordersLength = orders is List ? orders.length : 0;
    if (orders is List) {
      for (final order in orders) {
        if (order is! Map<String, dynamic>) {
          continue;
        }
        final rawStatus = order['refund_status'];
        if (rawStatus == null) {
          continue;
        }
        final status = rawStatus.toString().trim();
        if (status.isEmpty) {
          continue;
        }
        if (status.contains('退款中')) {
          refundPending += 1;
        } else if (status.contains('已退款') || status.contains('退款成功')) {
          refunded += 1;
        } else {
          refundOther += 1;
        }
      }
    }
    _logRefund(
      'mod=${mod.id} name=${mod.name} count=$count orders=$ordersLength '
      'pendingByOrders=$refundPending refundedByOrders=$refunded otherByOrders=$refundOther',
    );
    final needsServerCounts = count > 0 &&
        (ordersLength < count ||
            (ordersLength > 0 && refundPending == 0 && refunded == 0));
    if (needsServerCounts) {
      try {
        final pendingCount = await _fetchRefundCount(
          mod,
          range,
          _refundStatusPending,
        );
        final refundedCount = await _fetchRefundCount(
          mod,
          range,
          _refundStatusDone,
        );
        _logRefund(
          'mod=${mod.id} serverCounts pending=$pendingCount refunded=$refundedCount',
        );
        if (pendingCount + refundedCount <= count) {
          refundPending = pendingCount;
          refunded = refundedCount;
          refundOther = 0;
          _logRefund('mod=${mod.id} useServerCounts');
        } else {
          _logRefund(
            'mod=${mod.id} ignoreServerCounts sum=${pendingCount + refundedCount} count=$count',
          );
        }
      } catch (error) {
        _logRefund('mod=${mod.id} serverCounts failed: $error');
        // Fall back to partial counts from orders list.
      }
    }

    return IncomeSummary(
      itemId: mod.id,
      itemName: mod.name,
      totalDiamonds: totalDiamonds,
      totalPoints: totalPoints,
      orderCount: count,
      refundPendingCount: refundPending,
      refundedCount: refunded,
      refundOtherCount: refundOther,
      priceType: mod.priceType,
      releaseAt: mod.releaseAt,
    );
  }

  Future<int> _fetchRefundCount(
    ModItem mod,
    DateTimeRange range,
    int refundStatus,
  ) async {
    final beginUtc = _startOfDay(range.start).toUtc().toIso8601String();
    final endUtc = _endOfDay(range.end).toUtc().toIso8601String();
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/items/categories/$category/${mod.id}/incomes/',
      {
        'begin_time': beginUtc,
        'end_time': endUtc,
        'refund_status': refundStatus.toString(),
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
    final count = (data['count'] as num?)?.toInt() ?? 0;
    final orders = data['orders'];
    final ordersLength = orders is List ? orders.length : 0;
    _logRefund(
      'mod=${mod.id} refundStatus=$refundStatus count=$count orders=$ordersLength',
    );
    return count;
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
      releaseAt: mod.releaseAt,
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
