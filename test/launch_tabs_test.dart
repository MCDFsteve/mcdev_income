import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/launch_tabs.dart';

import 'development_test.dart' show MemoryPreferences;

void main() {
  test(
    'tabs keep stable identities, latest selection and per-tab options',
    () async {
      final preferences = MemoryPreferences();
      final store = DevelopmentTabsStore(preferences, '/development')..load();
      expect(store.tabs.single.id, 'default');
      expect(store.remove('default'), isFalse);
      final second = store.add()
        ..worldName = 'My world'
        ..creative = false
        ..menuOnly = true
        ..seed = '-1234';
      expect(second.id, matches(RegExp(r'^[a-f0-9]{32}$')));
      await store.save();
      final restored = DevelopmentTabsStore(preferences, '/development')
        ..load();
      expect(restored.activeId, second.id);
      expect(restored.tabs.last.toJson(), second.toJson());
      expect(restored.remove(second.id), isTrue);
      expect(restored.activeId, 'default');
      expect(restored.remove('default'), isFalse);
    },
  );

  test('invalid and duplicate IDs cannot escape a session directory', () {
    final preferences = MemoryPreferences();
    final store = DevelopmentTabsStore(preferences, '/development');
    preferences.values[store.key] =
        '{"active":"../outside","tabs":[{"id":"../outside"},{"id":"default"},{"id":"default"},null]}';
    store.load();
    expect(store.tabs.map((tab) => tab.id), ['default']);
    expect(store.activeId, 'default');
    preferences.values[store.key] = 'invalid json';
    store.load();
    expect(store.tabs.single.id, 'default');
  });

  test(
    'separate development directories retain independent tab lists',
    () async {
      final preferences = MemoryPreferences();
      final first = DevelopmentTabsStore(preferences, '/one')..load();
      first.add();
      await first.save();
      final second = DevelopmentTabsStore(preferences, '/two')..load();
      expect(second.tabs.length, 1);
      expect(
        (DevelopmentTabsStore(preferences, '/one')..load()).tabs.length,
        2,
      );
    },
  );
}
