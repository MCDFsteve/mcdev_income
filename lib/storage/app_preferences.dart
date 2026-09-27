import 'package:shared_preferences/shared_preferences.dart';
import '../core/preferences.dart';
import 'desktop_preferences_stub.dart'
    if (dart.library.io) 'file_preferences.dart'
    as desktop;

/// GUI and CLI share desktop state; mobile/web retain their platform store.
class AppPreferences implements PreferenceStore {
  AppPreferences(this.prefs);
  final SharedPreferences prefs;
  static Future<PreferenceStore> getInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final seed = <String, Object>{
      for (final key in prefs.getKeys())
        if (key.startsWith('login_') ||
            key.startsWith('resource_draft_v1:') ||
            key == 'theme_mode' ||
            key == 'income_presets_v1')
          key: prefs.get(key)!,
    };
    return await desktop.openDesktopPreferences(seed) ?? AppPreferences(prefs);
  }

  @override
  String? getString(String key) => prefs.getString(key);
  @override
  int? getInt(String key) => prefs.getInt(key);
  @override
  Set<String> getKeys() => prefs.getKeys();
  @override
  Future<bool> setString(String key, String value) =>
      prefs.setString(key, value);
  @override
  Future<bool> setInt(String key, int value) => prefs.setInt(key, value);
  @override
  Future<bool> remove(String key) => prefs.remove(key);
  @override
  Future<void> apply(Map<String, Object?> changes) async {
    for (final e in changes.entries) {
      if (e.value == null) {
        await prefs.remove(e.key);
      } else if (e.value is int) {
        await prefs.setInt(e.key, e.value as int);
      } else {
        await prefs.setString(e.key, e.value as String);
      }
    }
  }
}
