import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'development_storage.dart';
import 'game_archive_io.dart' show rejectTreeLinks;

const itemInfoPackName = 'mcdev_item_info';
const _behaviorUuid = '073796e4-37ff-4776-91c6-14dcd7aa5711';
const _behaviorModuleUuid = 'e507e5ba-b439-4712-904d-6598305c3617';
const _resourceUuid = 'e146a79d-ed2f-4247-b8be-4775fbed5bb5';
const _resourceModuleUuid = 'afb7c3e5-eabb-4d4d-b497-2733410d76b4';
const _scriptsName = 'mcdevItemInfoScripts';

const _modMain = r'''# -*- coding: utf-8 -*-
from mod.common.mod import Mod
import mod.client.extraClientApi as clientApi

@Mod.Binding(name="MCDevItemInfo", version="1.0.0")
class ItemInfoMod(object):
    @Mod.InitClient()
    def InitClient(self):
        clientApi.RegisterSystem("MCDevItemInfo", "ItemInfo", "mcdevItemInfoScripts.itemInfo.ItemInfoSystem")
''';

/// Installs the built-in mod into one prefix's data root. Python only loads
/// from a behavior pack and JSON UI only from a resource pack, so it needs both.
Future<void> installItemInfoPacks(String dataRoot) async {
  final behavior = await _resetPack(
    p.join(dataRoot, 'behavior_packs'),
    _behaviorUuid,
  );
  await _write(behavior, 'manifest.json', _manifest(true));
  await _write(behavior, '$_scriptsName/__init__.py', '');
  await _write(behavior, '$_scriptsName/modMain.py', _modMain);
  await _write(
    behavior,
    '$_scriptsName/itemInfo.py',
    await rootBundle.loadString('tools/item_info/runtime.py'),
  );
  final resource = await _resetPack(
    p.join(dataRoot, 'resource_packs'),
    _resourceUuid,
  );
  await _write(resource, 'manifest.json', _manifest(false));
  await _write(
    resource,
    'ui/_ui_defs.json',
    jsonEncode({
      'ui_defs': ['ui/mcdevItemInfo.json'],
    }),
  );
  await _write(
    resource,
    'ui/mcdevItemInfo.json',
    await rootBundle.loadString('tools/item_info/ui.json'),
  );
}

String _manifest(bool behavior) => jsonEncode({
  'format_version': 2,
  'header': {
    'name': 'MCDev Item Info',
    'description': 'Local crosshair target names',
    'uuid': behavior ? _behaviorUuid : _resourceUuid,
    'version': [1, 0, 0],
    'min_engine_version': [1, 18, 0],
  },
  'modules': [
    {
      'type': behavior ? 'data' : 'resources',
      'uuid': behavior ? _behaviorModuleUuid : _resourceModuleUuid,
      'version': [1, 0, 0],
    },
  ],
});

Future<void> _write(Directory pack, String path, String content) async {
  final file = File(p.join(pack.path, path));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

// Starting empty also drops the game's compiled .pyc from an older version.
Future<Directory> _resetPack(String parent, String uuid) async {
  final pack = Directory(p.join(parent, itemInfoPackName));
  final type = await FileSystemEntity.type(pack.path, followLinks: false);
  if (type != FileSystemEntityType.notFound) {
    if (type != FileSystemEntityType.directory) {
      throw const DevelopmentStorageException('物品信息辅助包路径已被占用。');
    }
    await rejectTreeLinks(pack.path);
    try {
      final manifest = jsonDecode(
        await File(p.join(pack.path, 'manifest.json')).readAsString(),
      );
      if (manifest is! Map || manifest['header']?['uuid'] != uuid) {
        throw const FormatException();
      }
    } on Object {
      throw const DevelopmentStorageException('物品信息辅助包目录已被其他项目占用。');
    }
    await pack.delete(recursive: true);
  }
  return pack.create(recursive: true);
}
