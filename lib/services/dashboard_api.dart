part of '../core.dart';

extension DashboardApi on McDevApi {
  Future<LeaderboardPage> fetchLeaderboard({
    String type = 'pe_hot',
    String kind = 'mods',
    int start = 0,
    int span = 50,
  }) async {
    if (!leaderboardTypes.containsKey(type) ||
        !leaderboardKinds.containsKey(kind) ||
        start < 0 ||
        span < 1 ||
        span > 100) {
      throw ArgumentError('无效的排行榜参数');
    }
    final path = ['pe_hot', 'hot_search'].contains(type)
        ? '/square/us_rank_list/'
        : '/square/rank_list/';
    final uri = Uri.https('mc-launcher.webapp.163.com', path, {
      'type': type,
      'first_type': '${leaderboardFirstType(type, kind)}',
      'start': '$start',
      'span': '$span',
    });
    final result = await _getJson(uri);
    final data = result['data'];
    if (data is! Map || data['data'] is! List) {
      throw McDevException('排行榜响应格式异常', uri);
    }
    final rows = ResourceOptions.maps(data['data']);
    return LeaderboardPage(
      items: [
        for (var i = 0; i < rows.length; i++)
          LeaderboardEntry(rows[i], type: type, fallbackRank: start + i + 1),
      ],
      total: int.tryParse('${data['count']}') ?? rows.length,
    );
  }

  Future<int> fetchUnreadMailCount() async {
    final uri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/mailbox/unread/count',
    );
    final response = await _getJson(uri);
    final data = response['data'];
    final count = data is Map ? int.tryParse('${data['count']}') : null;
    if (count == null || count < 0) throw McDevException('未读邮件数量格式异常', uri);
    return count;
  }

  Future<MailPageData> fetchMail({
    int start = 0,
    int span = 30,
    String type = '',
    bool? haveRead,
    String? query,
  }) async {
    if (!mailboxTypes.containsKey(type) ||
        start < 0 ||
        span < 1 ||
        span > 100) {
      throw ArgumentError('无效的邮件筛选参数');
    }
    final uri = Uri.https('mc-launcher.webapp.163.com', '/mailbox/', {
      'start': '$start',
      'span': '$span',
      if (type.isNotEmpty) 'mail_type': type,
      if (haveRead != null) 'have_read': '$haveRead',
      if (query?.trim().isNotEmpty == true) 'title': query!.trim(),
    });
    final response = await _getJson(uri);
    final data = response['data'];
    if (data is! Map || data['mail'] is! List) {
      throw McDevException('邮件列表响应格式异常', uri);
    }
    return MailPageData(
      items: ResourceOptions.maps(data['mail']).map(MailItem.new).toList(),
      total: int.tryParse('${data['count']}') ?? 0,
      unread: int.tryParse('${data['unread_count']}') ?? 0,
    );
  }

  /// Like the website, opening a detail marks that specific message as read.
  Future<MailItem> fetchMailDetail(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id');
    }
    final uri = Uri.https('mc-launcher.webapp.163.com', '/mailbox/$id');
    final response = await _getJson(uri);
    final data = response['data'];
    if (data is! Map || !data.containsKey('detail')) {
      throw McDevException('邮件正文响应格式异常', uri);
    }
    return MailItem({
      '_id': id,
      ...Map<String, dynamic>.from(data),
      'have_read': true,
    });
  }
}
