part of mcdev_income_app;

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

_Category _categoryFromValue(String? raw) {
  if (raw == null) {
    return _Category.pe;
  }
  final value = raw.toLowerCase();
  if (value == 'java') {
    return _Category.java;
  }
  return _Category.pe;
}

DateTime? _parseModReleaseAt(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is num) {
    return _epochToDateTime(raw.toInt());
  }
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final numeric = num.tryParse(text);
    if (numeric != null) {
      return _epochToDateTime(numeric.toInt());
    }
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      return parsed.toLocal();
    }
  }
  return null;
}

DateTime? _epochToDateTime(int value) {
  if (value <= 0) {
    return null;
  }
  if (value < 1000000000000) {
    return DateTime.fromMillisecondsSinceEpoch(
      value * 1000,
      isUtc: true,
    ).toLocal();
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
}

class ModItem {
  ModItem({
    required this.id,
    required this.name,
    this.price,
    this.priceType,
    this.status,
    this.weakOffline,
    this.releaseAt,
  });

  final String id;
  final String name;
  final int? price;
  final String? priceType;
  final String? status;
  final bool? weakOffline;
  final DateTime? releaseAt;
}

class IncomeSummary {
  IncomeSummary({
    required this.itemId,
    required this.itemName,
    required this.totalDiamonds,
    required this.totalPoints,
    required this.orderCount,
    this.downloadCount = 0,
    this.refundPendingCount = 0,
    this.refundedCount = 0,
    this.refundOtherCount = 0,
    this.error,
    this.priceType,
    this.releaseAt,
  });

  final String itemId;
  final String itemName;
  final int totalDiamonds;
  final int totalPoints;
  final int orderCount;
  final int downloadCount;
  final int refundPendingCount;
  final int refundedCount;
  final int refundOtherCount;
  final String? error;
  final String? priceType;
  final DateTime? releaseAt;

  IncomeSummary copyWith({int? downloadCount}) {
    return IncomeSummary(
      itemId: itemId,
      itemName: itemName,
      totalDiamonds: totalDiamonds,
      totalPoints: totalPoints,
      orderCount: orderCount,
      downloadCount: downloadCount ?? this.downloadCount,
      refundPendingCount: refundPendingCount,
      refundedCount: refundedCount,
      refundOtherCount: refundOtherCount,
      error: error,
      priceType: priceType,
      releaseAt: releaseAt,
    );
  }
}

class OverviewStats {
  OverviewStats({
    required this.thisMonthDiamond,
    required this.lastMonthDiamond,
    required this.yesterdayDiamond,
    required this.days14AverageDiamond,
    required this.thisMonthDownload,
    required this.lastMonthDownload,
    required this.yesterdayDownload,
    required this.days14AverageDownload,
    required this.dayDiamondDiff,
    required this.dayDownloadDiff,
    required this.monthDiamondDiff,
    required this.monthDownloadDiff,
  });

  final int thisMonthDiamond;
  final int lastMonthDiamond;
  final int yesterdayDiamond;
  final int days14AverageDiamond;
  final int thisMonthDownload;
  final int lastMonthDownload;
  final int yesterdayDownload;
  final int days14AverageDownload;
  final int dayDiamondDiff;
  final int dayDownloadDiff;
  final int monthDiamondDiff;
  final int monthDownloadDiff;

  static int _parseInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  factory OverviewStats.fromJson(Map<String, dynamic> data) {
    return OverviewStats(
      thisMonthDiamond: _parseInt(data['this_month_diamond']),
      lastMonthDiamond: _parseInt(data['last_month_diamond']),
      yesterdayDiamond: _parseInt(data['yesterday_diamond']),
      days14AverageDiamond: _parseInt(data['days_14_average_diamond']),
      thisMonthDownload: _parseInt(data['this_month_download']),
      lastMonthDownload: _parseInt(data['last_month_download']),
      yesterdayDownload: _parseInt(data['yesterday_download']),
      days14AverageDownload: _parseInt(data['days_14_average_download']),
      dayDiamondDiff: _parseInt(data['day_diamond_diff']),
      dayDownloadDiff: _parseInt(data['day_download_diff']),
      monthDiamondDiff: _parseInt(data['month_diamond_diff']),
      monthDownloadDiff: _parseInt(data['month_download_diff']),
    );
  }
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
