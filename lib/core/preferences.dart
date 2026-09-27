abstract interface class PreferenceStore {
  String? getString(String key);
  int? getInt(String key);
  Set<String> getKeys();
  Future<bool> setString(String key, String value);
  Future<bool> setInt(String key, int value);
  Future<bool> remove(String key);

  /// Null values remove keys. Desktop stores commit the batch atomically.
  Future<void> apply(Map<String, Object?> changes);
}
