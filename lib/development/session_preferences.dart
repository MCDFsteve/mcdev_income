import '../core/preferences.dart';

String validateTestSessionId(String value) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'sessionId', 'Invalid test session ID');
  }
  return value;
}

/// The first tab retains the existing settings; new tabs have independent keys.
class TestSessionPreferences implements PreferenceStore {
  TestSessionPreferences(this.store, String sessionId)
    : prefix = validateTestSessionId(sessionId) == 'default'
          ? ''
          : 'development_session_${sessionId}_';
  final PreferenceStore store;
  final String prefix;
  String _key(String key) => '$prefix$key';
  @override
  String? getString(String key) => store.getString(_key(key));
  @override
  int? getInt(String key) => store.getInt(_key(key));
  @override
  Set<String> getKeys() => store
      .getKeys()
      .where((key) => key.startsWith(prefix))
      .map((key) => key.substring(prefix.length))
      .toSet();
  @override
  Future<bool> setString(String key, String value) =>
      store.setString(_key(key), value);
  @override
  Future<bool> setInt(String key, int value) => store.setInt(_key(key), value);
  @override
  Future<bool> remove(String key) => store.remove(_key(key));
  @override
  Future<void> apply(Map<String, Object?> changes) => store.apply({
    for (final entry in changes.entries) _key(entry.key): entry.value,
  });
}
