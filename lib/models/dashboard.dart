part of '../core.dart';

const leaderboardTypes = {
  'pe_hot': '手游热门飙升',
  'hot_search': '热搜榜',
  'pe_download': '手游免费榜',
  'pe_sell': '手游畅销榜',
  'pc_download': '端游下载榜',
  'pc_like': '端游点赞榜',
};
const leaderboardKinds = {
  'mods': '模组',
  'maps': '地图',
  'textures': '材质光影',
  'multiplayer': '联机大厅',
};
int leaderboardFirstType(String type, String kind) {
  if (type == 'hot_search') return 0;
  final values = type.startsWith('pe_') ? [2, 1, 3, 6] : [3, 5, 4, 11];
  final index = leaderboardKinds.keys.toList().indexOf(kind);
  if (index < 0) throw ArgumentError.value(kind, 'kind');
  return values[index];
}

class LeaderboardEntry {
  LeaderboardEntry(this.raw, {required this.type, required int fallbackRank})
    : rank =
          int.tryParse('${raw['score_rank'] ?? raw['rank']}') ?? fallbackRank;
  final Map<String, dynamic> raw;
  final String type;
  final int rank;
  String get name =>
      '${raw['res_name'] ?? raw['item_name'] ?? raw['content'] ?? '未命名'}';
  String get id => '${raw['iid'] ?? raw['item_id'] ?? ''}';
  String? get icon => raw['icon_url'] as String?;
  String get author => '${raw['developer_name'] ?? ''}';
  String get metric {
    if (type == 'hot_search') {
      final value = num.tryParse('${raw['hot_search_value']}');
      return value == null ? '—' : '搜索指数 ${(100 * value).toStringAsFixed(1)}';
    }
    if (type == 'pe_hot' && raw['star_adjusted'] != null) {
      final star = num.tryParse('${raw['star_adjusted']}') ?? 0;
      return star > 0 ? '评分 ${star.toStringAsFixed(1)}' : '';
    }
    final value = raw['rank_metric_value'];
    return value == null
        ? ''
        : '${{'pe_download': '七天下载', 'pe_sell': '周钻石收入', 'pc_download': '七天下载', 'pc_like': '七天点赞'}[type]} $value';
  }

  // Both APIs use a positive change for falling down the rankings.
  int? get change {
    final direct = int.tryParse('${raw['rank_change']}');
    if (direct != null) return direct;
    final last = int.tryParse('${raw['last_rank']}');
    return last == null || last < 1 ? null : rank - last;
  }

  bool get isNew => raw['last_rank'] == -1 || raw['last_rank'] == '-1';
}

class LeaderboardPage {
  const LeaderboardPage({required this.items, required this.total});
  final List<LeaderboardEntry> items;
  final int total;
}

const mailboxTypes = {
  '': '全部邮件',
  'system_notice': '公告',
  'review_notice': '审核通知',
  'important_notice': '重要通知',
  'income_notice': '收益通知',
  'issue_feedback': '反馈',
  'notify': '其他通知',
};

class MailItem {
  MailItem(this.raw);
  final Map<String, dynamic> raw;
  String get id => '${raw['_id'] ?? raw['id'] ?? ''}';
  String get title => '${raw['title'] ?? '未命名邮件'}';
  String get type => '${raw['mail_type'] ?? ''}';
  String get typeLabel => mailboxTypes[type] ?? '通知';
  bool get isRead =>
      raw['have_read'] == true ||
      raw['have_read'] == 'true' ||
      raw['have_read'] == 1;
  DateTime? get time => _parseModReleaseAt(raw['time']);
  String get detail => '${raw['detail'] ?? ''}';
  MailItem asRead() => MailItem({...raw, 'have_read': true});
}

class MailPageData {
  const MailPageData({
    required this.items,
    required this.total,
    required this.unread,
  });
  final List<MailItem> items;
  final int total, unread;
}
