import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/item_info_io.dart';
import 'package:mcdev_income/development/launcher_io.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:path/path.dart' as p;

import 'development_test.dart' show MemoryPreferences;
import 'test_settings_test.dart' show RejectTestSettingPreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-item-info-');
  });
  tearDown(() async => temp.delete(recursive: true));

  NativeDevelopmentLauncher launcher(
    MemoryPreferences preferences, {
    String session = 'default',
  }) => NativeDevelopmentLauncher(
    NativeDevelopmentStorage(
      preferences: preferences,
      defaultRoot: temp.path,
      lockPath: p.join(temp.path, 'lock'),
    ),
    preferences,
    sessionId: session,
  );

  test('item info defaults off and persists per tab', () async {
    final preferences = MemoryPreferences();
    final first = launcher(preferences);
    expect(first.itemInfoDisplay, isFalse);
    await first.chooseItemInfoDisplay(true);
    first.dispose();
    final reopened = launcher(preferences);
    final other = launcher(preferences, session: 'other');
    expect(reopened.itemInfoDisplay, isTrue);
    expect(other.itemInfoDisplay, isFalse);
    reopened.dispose();
    other.dispose();
  });

  for (final state in ['busy', 'running', 'failed write']) {
    test('item info setting is unchanged during $state', () async {
      final instance =
          launcher(
              state == 'failed write'
                  ? RejectTestSettingPreferences()
                  : MemoryPreferences(),
            )
            ..busy = state == 'busy'
            ..running = state == 'running';
      await expectLater(instance.chooseItemInfoDisplay(true), throwsException);
      expect(instance.itemInfoDisplay, isFalse);
      instance
        ..busy = false
        ..running = false
        ..dispose();
    });
  }

  Directory pack(String type) =>
      Directory(p.join(temp.path, type, itemInfoPackName));
  File file(String type, String path) => File(p.join(pack(type).path, path));

  test(
    'install writes a script pack and a UI pack the game can load',
    () async {
      await installItemInfoPacks(temp.path);
      final behavior = jsonDecode(
        await file('behavior_packs', 'manifest.json').readAsString(),
      );
      final resource = jsonDecode(
        await file('resource_packs', 'manifest.json').readAsString(),
      );
      expect(behavior['modules'].single['type'], 'data');
      expect(resource['modules'].single['type'], 'resources');
      expect({
        behavior['header']['uuid'],
        behavior['modules'].single['uuid'],
        resource['header']['uuid'],
        resource['modules'].single['uuid'],
      }, hasLength(4));

      final scripts = 'mcdevItemInfoScripts';
      expect(
        await file('behavior_packs', '$scripts/__init__.py').exists(),
        true,
      );
      final main = await file(
        'behavior_packs',
        '$scripts/modMain.py',
      ).readAsString();
      expect(main, contains('$scripts.itemInfo.ItemInfoSystem'));
      final runtime = await file(
        'behavior_packs',
        '$scripts/itemInfo.py',
      ).readAsString();
      expect(
        runtime,
        await rootBundle.loadString('tools/item_info/runtime.py'),
      );
      expect(runtime, contains("'$scripts.itemInfo.ItemInfoScreen'"));

      final defs = jsonDecode(
        await file('resource_packs', 'ui/_ui_defs.json').readAsString(),
      );
      final ui = jsonDecode(
        await file('resource_packs', defs['ui_defs'].single).readAsString(),
      );
      expect(runtime, contains("UI_DEF = '${ui['namespace']}.main'"));
      expect(ui['main']['type'], 'screen');
      // A HUD must not swallow movement or the mouse.
      expect(ui['main']['absorbs_input'], isFalse);
      expect(ui['main']['is_showing_menu'], isFalse);
      expect(ui['info']['anchor_from'], 'top_right');
      // Raw keys must stay visible rather than being translated again.
      expect(ui['text']['localize'], isFalse);
    },
  );

  test('reinstall drops compiled scripts from an older version', () async {
    await installItemInfoPacks(temp.path);
    final stale = file('behavior_packs', 'mcdevItemInfoScripts/itemInfo.pyc');
    await stale.writeAsString('old');
    await installItemInfoPacks(temp.path);
    expect(await stale.exists(), isFalse);
    expect(await file('resource_packs', 'manifest.json').exists(), isTrue);
  });

  test('install refuses a directory owned by another project', () async {
    final foreign = file('behavior_packs', 'manifest.json');
    await foreign.parent.create(recursive: true);
    await foreign.writeAsString(
      jsonEncode({
        'header': {'uuid': '11111111-1111-4111-8111-111111111111'},
      }),
    );
    final kept = file('behavior_packs', 'keep.txt');
    await kept.writeAsString('mine');
    await expectLater(
      installItemInfoPacks(temp.path),
      throwsA(predicate((e) => e.toString() == '物品信息辅助包目录已被其他项目占用。')),
    );
    expect(await kept.readAsString(), 'mine');
  });

  test('install never writes through a linked pack directory', () async {
    final outside = await Directory(p.join(temp.path, 'outside')).create();
    await Directory(p.join(temp.path, 'behavior_packs')).create();
    await Link(pack('behavior_packs').path).create(outside.path);
    await expectLater(installItemInfoPacks(temp.path), throwsException);
    expect(await outside.list().isEmpty, isTrue);
  });
}
