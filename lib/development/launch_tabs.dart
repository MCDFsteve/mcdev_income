import 'dart:convert';
import 'dart:math';

import '../core/preferences.dart';

/// The first tab retains the existing Wine prefix and saved world. Additional
/// tabs have permanent IDs, so renaming a project cannot relocate its saves.
class DevelopmentTab {
  DevelopmentTab({
    required this.id,
    this.worldName = '模组测试',
    this.creative = true,
    this.menuOnly = false,
    this.seed,
  });

  final String id;
  String worldName;
  bool creative;
  bool menuOnly;
  String? seed;

  Map<String, Object> toJson() => {
    'id': id,
    'worldName': worldName,
    'creative': creative,
    'menuOnly': menuOnly,
    'seed': ?seed,
  };
}

class DevelopmentTabsStore {
  DevelopmentTabsStore(this.preferences, String root)
    : key = 'development_test_tabs_v1:$root';

  final PreferenceStore? preferences;
  final String key;
  final List<DevelopmentTab> tabs = [];
  String activeId = 'default';
  Future<void> _pending = Future.value();

  void load() {
    tabs.clear();
    final raw = preferences?.getString(key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['tabs'] is List) {
          final ids = <String>{};
          for (final item in decoded['tabs'] as List) {
            if (item is! Map) continue;
            final id = item['id'];
            if (id is! String ||
                !RegExp(r'^(default|[a-f0-9]{32})$').hasMatch(id) ||
                !ids.add(id)) {
              continue;
            }
            tabs.add(
              DevelopmentTab(
                id: id,
                worldName: item['worldName'] is String
                    ? item['worldName'] as String
                    : '模组测试',
                creative: item['creative'] != false,
                menuOnly: item['menuOnly'] == true,
                seed: item['seed'] is String ? item['seed'] as String : null,
              ),
            );
          }
          if (decoded['active'] is String) {
            activeId = decoded['active'] as String;
          }
        }
      } on FormatException {
        // An interrupted or obsolete preference must not hide the launch UI.
      }
    }
    if (tabs.isEmpty) tabs.add(DevelopmentTab(id: 'default'));
    if (!tabs.any((tab) => tab.id == activeId)) activeId = tabs.first.id;
  }

  DevelopmentTab add() {
    final random = Random.secure();
    String id;
    do {
      id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    } while (tabs.any((tab) => tab.id == id));
    final tab = DevelopmentTab(id: id);
    tabs.add(tab);
    activeId = id;
    return tab;
  }

  bool remove(String id) {
    if (tabs.length <= 1) return false;
    final index = tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return false;
    tabs.removeAt(index);
    if (activeId == id) {
      activeId = tabs[(index - 1).clamp(0, tabs.length - 1)].id;
    }
    return true;
  }

  Future<void> save() {
    final value = jsonEncode({
      'version': 1,
      'active': activeId,
      'tabs': tabs.map((tab) => tab.toJson()).toList(),
    });
    // Preserve UI edit order even when the desktop preference store is busy.
    final next = _pending.then((_) async {
      final saved = await preferences?.setString(key, value);
      if (saved == false) throw StateError('保存测试标签失败');
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
