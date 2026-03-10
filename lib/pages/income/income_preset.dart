part of mcdev_income_app;

enum IncomeScope { all, multiple, single }

enum _SummarySortKey { diamonds, downloads, releaseTime }

class IncomePreset {
  IncomePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.scope,
    required this.modIds,
    required this.internalRatios,
    required this.neteaseRatios,
    required this.defaultInternalRatio,
    required this.defaultNeteaseRatio,
    required this.taxRate,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final _Category category;
  final IncomeScope scope;
  final List<String> modIds;
  final Map<String, double> internalRatios;
  final Map<String, double> neteaseRatios;
  final double defaultInternalRatio;
  final double defaultNeteaseRatio;
  final double taxRate;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': _categoryValue(category),
      'scope': scope.name,
      'modIds': modIds,
      'internalRatios': internalRatios,
      'neteaseRatios': neteaseRatios,
      'defaultInternalRatio': defaultInternalRatio,
      'defaultNeteaseRatio': defaultNeteaseRatio,
      'taxRate': taxRate,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static IncomePreset fromJson(Map<String, dynamic> json) {
    final rawCategory = json['category']?.toString();
    final rawScope = json['scope']?.toString();
    final modIds =
        (json['modIds'] as List?)?.map((entry) => entry.toString()).toList() ??
        <String>[];
    final internalRatios = _parseDoubleMap(json['internalRatios']);
    final neteaseRatios = _parseDoubleMap(json['neteaseRatios']);
    final defaultInternalRatio =
        _tryParseDouble(json['defaultInternalRatio']) ?? 1.0;
    final defaultNeteaseRatio =
        _tryParseDouble(json['defaultNeteaseRatio']) ?? 1.0;
    final taxRate = _tryParseDouble(json['taxRate']) ?? 0.2;
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');

    return IncomePreset(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名预设',
      category: _categoryFromValue(rawCategory),
      scope: IncomeScope.values.firstWhere(
        (scope) => scope.name == rawScope,
        orElse: () => IncomeScope.all,
      ),
      modIds: modIds,
      internalRatios: internalRatios,
      neteaseRatios: neteaseRatios,
      defaultInternalRatio: defaultInternalRatio,
      defaultNeteaseRatio: defaultNeteaseRatio,
      taxRate: taxRate,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

double? _tryParseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

Map<String, double> _parseDoubleMap(Object? raw) {
  final result = <String, double>{};
  if (raw is Map) {
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = _tryParseDouble(entry.value);
      if (value != null) {
        result[key] = value;
      }
    }
  }
  return result;
}
