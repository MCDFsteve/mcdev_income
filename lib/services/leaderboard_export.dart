part of '../core.dart';

class LeaderboardExportRow {
  const LeaderboardExportRow({
    required this.type,
    required this.kind,
    required this.entry,
  });

  final String type;
  final String kind;
  final LeaderboardEntry entry;
}

/// Fetches every page for each selected leaderboard. The hot-search endpoint
/// does not use a resource kind, so it is requested only once.
Future<List<LeaderboardExportRow>> fetchLeaderboardExportRows({
  required McDevApi api,
  required Set<String> types,
  required Set<String> kinds,
  void Function(int completed, int total)? onProgress,
}) async {
  if (types.isEmpty ||
      types.any((type) => !leaderboardTypes.containsKey(type)) ||
      kinds.any((kind) => !leaderboardKinds.containsKey(kind)) ||
      (kinds.isEmpty && types.any((type) => type != 'hot_search'))) {
    throw ArgumentError('无效的排行榜导出范围');
  }

  final selections = <(String, String)>[
    for (final type in leaderboardTypes.keys)
      if (types.contains(type))
        if (type == 'hot_search')
          (type, 'mods')
        else
          for (final kind in leaderboardKinds.keys)
            if (kinds.contains(kind)) (type, kind),
  ];
  final rows = <LeaderboardExportRow>[];
  for (var index = 0; index < selections.length; index++) {
    final (type, kind) = selections[index];
    var start = 0;
    while (true) {
      final page = await api.fetchLeaderboard(
        type: type,
        kind: kind,
        start: start,
        span: 100,
      );
      if (page.items.isEmpty && start < page.total) {
        throw StateError('${leaderboardTypes[type]}在第 ${start + 1} 条后返回空页');
      }
      rows.addAll([
        for (final entry in page.items)
          LeaderboardExportRow(type: type, kind: kind, entry: entry),
      ]);
      start += page.items.length;
      if (page.items.isEmpty || start >= page.total) break;
    }
    onProgress?.call(index + 1, selections.length);
  }
  return rows;
}

String buildLeaderboardCsv(List<LeaderboardExportRow> rows) {
  final rawKeys = <String>{
    for (final row in rows) ...row.entry.raw.keys,
  }.toList()..sort();
  final output = StringBuffer('\ufeff');
  final header = <String>[
    '榜单',
    '类别',
    '排名',
    '资源ID',
    '名称',
    '开发者',
    '指标',
    '排名变化（正数为下降）',
    '新上榜',
    '图标URL',
    for (final key in rawKeys) '原始字段:$key',
  ];
  void writeRow(Iterable<Object?> cells) {
    output.write(cells.map(_leaderboardCsvCell).join(','));
    output.write('\r\n');
  }

  writeRow(header);
  for (final row in rows) {
    final entry = row.entry;
    writeRow([
      leaderboardTypes[row.type]!,
      row.type == 'hot_search' ? '全部' : leaderboardKinds[row.kind]!,
      entry.rank,
      entry.id,
      entry.name,
      entry.author,
      entry.metric,
      entry.change,
      entry.isNew ? '是' : '否',
      entry.icon ?? '',
      for (final key in rawKeys) entry.raw[key],
    ]);
  }
  return output.toString();
}

String _leaderboardCsvCell(Object? value) {
  final text = switch (value) {
    null => '',
    Map() || List() => jsonEncode(value),
    _ => value.toString(),
  };
  return '"${text.replaceAll('"', '""')}"';
}
