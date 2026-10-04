import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'development_storage.dart';
import 'launcher_service.dart';

class DuplicateModUuidException extends DevelopmentStorageException {
  const DuplicateModUuidException() : super('项目中存在重复 UUID。');
}

/// Prepare every manifest before writing, and retain the exact source for
/// rollback if a manifest or the project registry cannot be committed.
class ModManifestChanges {
  ModManifestChanges._(this._edits);
  final List<_ManifestEdit> _edits;

  Map<String, String> get uuidReplacements => {
    for (final edit in _edits) edit.pack.uuid: edit.newUuid,
  };

  List<ModPack> get packs => [
    for (final edit in _edits)
      ModPack(
        name: edit.manifest['header']['name']?.toString() ?? edit.pack.name,
        uuid: edit.newUuid,
        version: edit.newVersion,
        type: edit.pack.type,
        directory: edit.pack.directory,
        projectRoot: edit.pack.projectRoot,
        importedAt: edit.pack.importedAt,
        lastLaunchedAt: edit.pack.lastLaunchedAt,
      ),
  ];

  static Future<ModManifestChanges> prepare(
    List<ModPack> packs, {
    bool refreshUuids = false,
    bool upgradeVersion = false,
  }) async {
    final edits = <_ManifestEdit>[];
    final random = Random.secure();
    final used = <String>{};
    String uuid() {
      while (true) {
        final bytes = List.generate(16, (_) => random.nextInt(256));
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        final hex = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        final value =
            '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
            '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
            '${hex.substring(20)}';
        if (used.add(value)) return value;
      }
    }

    for (final pack in packs) {
      final file = File(p.join(pack.directory, 'manifest.json'));
      final original = await file.readAsString();
      final decoded = jsonDecode(original);
      if (decoded is! Map<String, dynamic> ||
          decoded['header'] is! Map ||
          decoded['modules'] is! List) {
        throw const DevelopmentStorageException('模组 manifest.json 结构无效。');
      }
      final header = decoded['header'] as Map;
      final version = header['version'];
      if (header['uuid'] is! String ||
          version is! List ||
          version.length != 3 ||
          version.any((v) => v is! int || v < 0) ||
          (decoded['modules'] as List).any((m) => m is! Map)) {
        throw const DevelopmentStorageException('模组 UUID 或版本无效。');
      }
      edits.add(_ManifestEdit(pack, file, original, decoded));
      for (final id in [
        header['uuid'] as String,
        for (final module in decoded['modules'] as List)
          if (module['uuid'] is String) module['uuid'] as String,
      ]) {
        if (!used.add(id.toLowerCase()) && !refreshUuids) {
          throw const DuplicateModUuidException();
        }
      }
    }

    for (final edit in edits) {
      final header = edit.manifest['header'] as Map;
      if (refreshUuids) {
        edit.newUuid = uuid();
        header['uuid'] = edit.newUuid;
        for (final module in edit.manifest['modules'] as List) {
          module['uuid'] = uuid();
        }
      }
      if (upgradeVersion) {
        edit.newVersion = [...edit.oldVersion];
        edit.newVersion[2]++;
        header['version'] = edit.newVersion;
        for (final module in edit.manifest['modules'] as List) {
          module['version'] = [...edit.newVersion];
        }
      }
    }

    for (final edit in edits) {
      final dependencies = edit.manifest['dependencies'];
      if (dependencies is! List) continue;
      for (final dependency in dependencies) {
        if (dependency is! Map || dependency['uuid'] is! String) continue;
        final oldUuid = (dependency['uuid'] as String).toLowerCase();
        var targets = edits
            .where(
              (e) =>
                  e.oldUuid == oldUuid || e.pack.uuid.toLowerCase() == oldUuid,
            )
            .toList();
        if (targets.length > 1) {
          // A BP/RP pair may accidentally share its header UUID. A pack
          // dependency refers to its companion, rather than to itself.
          targets = targets.where((e) => e != edit).toList();
          final sameProject = targets
              .where(
                (e) =>
                    (e.pack.projectRoot ?? p.dirname(e.pack.directory)) ==
                    (edit.pack.projectRoot ?? p.dirname(edit.pack.directory)),
              )
              .toList();
          if (sameProject.isNotEmpty) targets = sameProject;
          final versionMatches = targets
              .where(
                (e) =>
                    jsonEncode(e.oldVersion) ==
                    jsonEncode(dependency['version']),
              )
              .toList();
          if (versionMatches.isNotEmpty) targets = versionMatches;
        }
        if (targets.isEmpty) continue; // External / module_name dependency.
        if (targets.length != 1) {
          throw const DevelopmentStorageException(
            '重复 UUID 的依赖无法确定目标包，请先修正 manifest.json 中的依赖。',
          );
        }
        final target = targets.single;
        dependency['uuid'] = target.newUuid;
        if (upgradeVersion) dependency['version'] = [...target.newVersion];
      }
    }
    return ModManifestChanges._(edits);
  }

  final List<_ManifestEdit> _written = [];

  Future<void> write() async {
    try {
      for (final edit in _edits) {
        await _replace(
          edit.file,
          '${const JsonEncoder.withIndent('  ').convert(edit.manifest)}\n',
        );
        _written.add(edit);
      }
    } catch (_) {
      await rollback();
      rethrow;
    }
  }

  Future<void> rollback() async {
    for (final edit in _written.reversed) {
      await _replace(edit.file, edit.original);
    }
    _written.clear();
  }
}

class _ManifestEdit {
  _ManifestEdit(this.pack, this.file, this.original, this.manifest)
    : oldUuid = (manifest['header']['uuid'] as String).toLowerCase(),
      oldVersion = (manifest['header']['version'] as List)
          .cast<int>()
          .toList() {
    newUuid = oldUuid;
    newVersion = [...oldVersion];
  }
  final ModPack pack;
  final File file;
  final String original;
  final Map<String, dynamic> manifest;
  final String oldUuid;
  final List<int> oldVersion;
  late String newUuid;
  late List<int> newVersion;
}

Future<void> _replace(File file, String content) async {
  final temporary = File(
    '${file.path}.tmp-${Random.secure().nextInt(1 << 30)}',
  );
  try {
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
