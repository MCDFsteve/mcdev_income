part of 'cli.dart';

double _ratio(dynamic value, String name) {
  final result = double.tryParse('$value');
  if (result == null || !result.isFinite || result < 0 || result > 1) {
    throw CliFailure('invalid_ratio', '$name 应为 0 到 1 的数值');
  }
  return result;
}

extension _IncomeCommands on McdevCli {
  (DateTime, DateTime) _dates() {
    final now = DateTime.now();
    final start = has('from')
        ? parseDate(str('from')!)
        : DateTime(now.year, now.month, 1);
    final end = has('to')
        ? parseDate(str('to')!)
        : DateTime(now.year, now.month, now.day);
    if (start.isAfter(end)) throw CliFailure('invalid_range', '开始日期不能晚于结束日期');
    return (start, end);
  }

  Map<String, dynamic> _mod(ModItem m) => {
    'id': m.id,
    'name': m.name,
    'price': m.price,
    'price_type': m.priceType,
    'status': m.status,
    'weak_offline': m.weakOffline,
    'release_at': m.releaseAt?.toIso8601String(),
  };
  Future<Object?> _income(String action) async {
    Map<String, dynamic>? preset;
    if (has('preset')) {
      preset = _presets().where((e) => e['id'] == str('preset')).firstOrNull;
      if (preset == null) throw CliFailure('not_found', '未找到收益预设');
    }
    final cat = has('category')
        ? modCategory
        : preset?['category']?.toString() ?? modCategory;
    final client = await api(forCategory: cat);
    var mods = await client.fetchMods(
      onlyPriced: flag('priced'),
      onlyPublished: flag('published'),
    );
    if (action == 'mods list') {
      final query = str('query')?.toLowerCase() ?? '';
      return {
        'category': cat,
        'items': mods
            .where(
              (m) =>
                  m.id.contains(query) || m.name.toLowerCase().contains(query),
            )
            .map(_mod)
            .toList(),
      };
    }
    final ids = has('id')
        ? many('id').toSet()
        : preset?['scope'] != null && preset?['scope'] != 'all'
        ? (preset!['modIds'] as List).cast<String>().toSet()
        : null;
    if (ids != null) {
      final missing = ids.difference(mods.map((m) => m.id).toSet());
      if (missing.isNotEmpty) {
        throw CliFailure(
          'unknown_mod',
          '部分 Mod 编号不存在于此账号/类别',
          details: {'ids': missing.toList()},
        );
      }
      mods = mods.where((m) => ids.contains(m.id)).toList();
    }
    final (start, end) = _dates();
    final platform = cat == 'java' ? 'pc' : 'pe';
    final downloads = <String, int>{};
    // The platform limits download statistics batches; mirror the GUI's batches.
    for (var i = 0; i < mods.length; i += 10) {
      final batch = mods.skip(i).take(10).map((m) => m.id).toList();
      downloads.addAll(
        await (flag('total')
            ? client.fetchSalesTotals
            : client.fetchSalesIncrements)(
          itemIds: batch,
          startDate: start,
          endDate: end,
          platform: platform,
          category: platform,
        ),
      );
    }
    final dateData = {
      'from': DateFormat('yyyy-MM-dd').format(start),
      'to': DateFormat('yyyy-MM-dd').format(end),
      'category': cat,
    };
    if (action == 'mods sales') {
      return {
        ...dateData,
        'total': flag('total'),
        'items': [
          for (final m in mods)
            {'id': m.id, 'name': m.name, 'downloads': downloads[m.id] ?? 0},
        ],
      };
    }
    final internal = _ratio(
      str('internal') ?? preset?['defaultInternalRatio'] ?? 1,
      'internal',
    );
    final netease = _ratio(
      str('netease') ?? preset?['defaultNeteaseRatio'] ?? 1,
      'netease',
    );
    final tax = _ratio(str('tax') ?? preset?['taxRate'] ?? 0.16, 'tax');
    final rows = <Map<String, dynamic>>[];
    for (final m in mods) {
      progress('查询收益 ${rows.length + 1}/${mods.length}：${m.name}');
      final summary = await client.fetchIncomeWithRetry(
        m,
        IncomeDateRange(start: start, end: end),
      );
      final inside = has('internal')
          ? internal
          : _ratio(preset?['internalRatios']?[m.id] ?? internal, 'internal');
      final outside = has('netease')
          ? netease
          : _ratio(preset?['neteaseRatios']?[m.id] ?? netease, 'netease');
      rows.add({
        'id': m.id,
        'name': m.name,
        'diamonds': summary.totalDiamonds,
        'points': summary.totalPoints,
        'orders': summary.orderCount,
        'downloads': downloads[m.id] ?? 0,
        'refund_pending': summary.refundPendingCount,
        'refunded': summary.refundedCount,
        'refund_other': summary.refundOtherCount,
        'internal_ratio': inside,
        'netease_ratio': outside,
        'tax': tax,
        'income_yuan': summary.error == null
            ? summary.totalDiamonds / 100 * inside * outside * (1 - tax)
            : null,
        'release_at': m.releaseAt?.toIso8601String(),
        'error': summary.error,
      });
    }
    final sort = str('sort') == 'release'
        ? 'release_at'
        : str('sort') ?? 'diamonds';
    rows.sort((a, b) {
      final comparison = sort == 'release_at'
          ? '${a[sort] ?? ''}'.compareTo('${b[sort] ?? ''}')
          : (a[sort] as num).compareTo(b[sort] as num);
      return flag('asc') ? comparison : -comparison;
    });
    if (has('csv')) {
      const keys = [
        'id',
        'name',
        'diamonds',
        'points',
        'orders',
        'downloads',
        'refund_pending',
        'refunded',
        'refund_other',
        'internal_ratio',
        'netease_ratio',
        'tax',
        'income_yuan',
        'release_at',
        'error',
      ];
      final file = File(str('csv')!);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '\ufeff${keys.map(csvCell).join(',')}\r\n${rows.map((r) => keys.map((k) => csvCell(r[k])).join(',')).join('\r\n')}\r\n',
        flush: true,
      );
    }
    final result = {
      ...dateData,
      'items': rows,
      'partial': rows.any((r) => r['error'] != null),
      'totals': {
        for (final key in [
          'diamonds',
          'points',
          'orders',
          'downloads',
          'refund_pending',
          'refunded',
          'refund_other',
          'income_yuan',
        ])
          key: rows.fold<num>(0, (n, r) => n + ((r[key] as num?) ?? 0)),
      },
      if (has('csv')) 'csv': File(str('csv')!).absolute.path,
    };
    if (result['partial'] == true) {
      throw CliFailure(
        'partial_income',
        '部分作品收益查询失败，结果和 CSV 保留错误项，请勿将合计视为完整收益',
        exitCode: 4,
        details: result,
      );
    }
    return result;
  }
}
