import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

class LanRosterPlayer {
  const LanRosterPlayer({required this.id, required this.name});

  final String id;
  final String name;
}

class LanRosterReport {
  const LanRosterReport({
    required this.epoch,
    required this.sequence,
    required this.players,
  });

  /// Changes when a server-side world instance is recreated in the same game
  /// process; [sequence] starts again at one for each such instance.
  final String epoch;
  final int sequence;
  final List<LanRosterPlayer> players;
  bool get ready => true;
}

/// A small, launcher-owned server script reports the actual world's players.
/// Each host prefix receives its own report path and launch nonce. It never
/// edits the developer's source packs or guesses membership from live processes.
class LanRosterBridge {
  LanRosterBridge._(this.reportFile, this.nonce, this.packDirectory);

  static const _packName = 'mcdev_lan_bridge';
  static const _packUuid = '637f57c2-24b6-4efd-ab8c-322873b46e67';
  static const _moduleUuid = '55297c4c-0d72-4e24-9138-c759383953d7';
  static const maximumReportBytes = 256 * 1024;
  static final _validEpoch = RegExp(r'^[0-9]{1,20}-[0-9]{1,20}$');
  static const _scriptsDirectory = 'mcdevLanBridgeScripts';
  static const _packFiles = [
    'manifest.json',
    '$_scriptsDirectory/__init__.py',
    '$_scriptsDirectory/modMain.py',
    '$_scriptsDirectory/server.py',
  ];

  final File reportFile;
  final String nonce;
  final Directory packDirectory;
  String get directoryName => _packName;
  String get uuid => _packUuid;

  static Future<LanRosterBridge> create({
    required String behaviorPacksDirectory,
    required String reportPath,
    required String windowsReportPath,
  }) async {
    final random = Random.secure();
    final nonce = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final report = File(reportPath);
    await report.parent.create(recursive: true);
    // Never follow an old report symlink when writing or reading our state.
    final reportType = await FileSystemEntity.type(
      reportPath,
      followLinks: false,
    );
    if (reportType != FileSystemEntityType.notFound) {
      if (reportType != FileSystemEntityType.file) {
        throw const FileSystemException('局域网玩家报告路径不是普通文件');
      }
      await report.delete();
    }
    final pack = Directory(p.join(behaviorPacksDirectory, _packName));
    final packType = await FileSystemEntity.type(pack.path, followLinks: false);
    if (packType != FileSystemEntityType.notFound) {
      if (packType != FileSystemEntityType.directory) {
        throw const FileSystemException('局域网测试辅助包路径已被占用');
      }
      try {
        final manifest = jsonDecode(
          await File(p.join(pack.path, 'manifest.json')).readAsString(),
        );
        if (manifest is! Map || manifest['header']?['uuid'] != _packUuid) {
          throw const FormatException();
        }
      } on Object {
        throw const FileSystemException('局域网测试辅助包路径已被其他项目占用');
      }
      await pack.delete(recursive: true);
    }
    final scripts = Directory(p.join(pack.path, 'mcdevLanBridgeScripts'));
    await scripts.create(recursive: true);
    await File(p.join(pack.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'format_version': 2,
        'header': {
          'name': 'MCDev LAN Test Bridge',
          'description': 'Local test world player roster',
          'uuid': _packUuid,
          'version': [1, 0, 0],
          'min_engine_version': [1, 18, 0],
        },
        'modules': [
          {
            'type': 'data',
            'uuid': _moduleUuid,
            'version': [1, 0, 0],
          },
        ],
        'dependencies': <Object>[],
      }),
    );
    await File(p.join(scripts.path, '__init__.py')).writeAsString('');
    await File(p.join(scripts.path, 'modMain.py')).writeAsString(_modMain);
    await File(p.join(scripts.path, 'server.py')).writeAsString(
      _serverScript
          .replaceFirst('__MCDEV_REPORT_PATH__', jsonEncode(windowsReportPath))
          .replaceFirst('__MCDEV_REPORT_NONCE__', jsonEncode(nonce)),
    );
    return LanRosterBridge._(report, nonce, pack);
  }

  /// Match the host's exact bridge pack during the native mod handshake. Only
  /// its four generated files are copied; reports and developer packs are not.
  /// The script has an InitServer entry point, so guests do not run a roster
  /// writer. Keep its original nonce and content to match the active host.
  Future<void> copyToGuest({required String behaviorPacksDirectory}) async {
    final files = await _readOwnedPack(packDirectory);
    final server = utf8.decode(files['$_scriptsDirectory/server.py']!);
    if (!server.contains('REPORT_NONCE = ${jsonEncode(nonce)}')) {
      throw const FileSystemException('房主的局域网辅助包已更新，请重新启动测试');
    }
    final parent = Directory(behaviorPacksDirectory);
    var parentType = await FileSystemEntity.type(
      parent.path,
      followLinks: false,
    );
    if (parentType == FileSystemEntityType.notFound) {
      await parent.create(recursive: true);
      parentType = await FileSystemEntity.type(parent.path, followLinks: false);
    }
    if (parentType != FileSystemEntityType.directory) {
      throw const FileSystemException('访客行为包路径不是普通目录');
    }
    final target = Directory(p.join(parent.path, _packName));
    final targetType = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    if (targetType != FileSystemEntityType.notFound) {
      await _readOwnedPack(target);
      if (await target.resolveSymbolicLinks() ==
          await packDirectory.resolveSymbolicLinks()) {
        throw const FileSystemException('访客辅助包不能覆盖房主辅助包');
      }
      // Never remove unrelated content merely because its manifest reused the
      // reserved UUID. Python's own compiled copies are safe to replace.
      await for (final item in target.list(
        recursive: true,
        followLinks: false,
      )) {
        final relative = p.relative(item.path, from: target.path);
        final knownFile =
            _packFiles.contains(relative) ||
            _packFiles.any(
              (file) => file.endsWith('.py') && '${file}c' == relative,
            );
        if (!((item is File && knownFile) ||
            (item is Directory && relative == _scriptsDirectory))) {
          throw const FileSystemException('访客辅助包目录包含其他项目文件');
        }
      }
    }
    final staging = await parent.createTemp('.mcdev-lan-pack-');
    Directory? backup;
    var installed = false;
    try {
      for (final entry in files.entries) {
        final file = File(p.join(staging.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      if (targetType != FileSystemEntityType.notFound) {
        backup = await parent.createTemp('.mcdev-lan-backup-');
        await backup.delete();
        await target.rename(backup.path);
      }
      try {
        await staging.rename(target.path);
        installed = true;
      } catch (_) {
        if (backup != null && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (installed && backup != null && await backup.exists()) {
        await backup.delete(recursive: true);
      }
    }
  }

  static Future<Map<String, List<int>>> _readOwnedPack(Directory pack) async {
    for (final directory in [pack.path, p.join(pack.path, _scriptsDirectory)]) {
      if (await FileSystemEntity.type(directory, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FileSystemException('局域网辅助包路径不是普通目录');
      }
    }
    final files = <String, List<int>>{};
    for (final relative in _packFiles) {
      final path = p.join(pack.path, relative);
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FileSystemException('局域网辅助包缺少普通文件');
      }
      final file = await File(path).open();
      try {
        final bytes = await file.read(64 * 1024 + 1);
        if (bytes.length > 64 * 1024) {
          throw const FileSystemException('局域网辅助包文件大小异常');
        }
        files[relative] = bytes;
      } finally {
        await file.close();
      }
    }
    try {
      final manifest = jsonDecode(utf8.decode(files['manifest.json']!));
      if (manifest is! Map ||
          manifest['header']?['uuid'] != _packUuid ||
          manifest['modules'] is! List ||
          (manifest['modules'] as List).length != 1 ||
          manifest['modules'][0]?['uuid'] != _moduleUuid ||
          manifest['modules'][0]?['type'] != 'data') {
        throw const FormatException();
      }
    } on Object {
      throw const FileSystemException('局域网辅助包路径已被其他项目占用');
    }
    return files;
  }

  /// A partial write, stale nonce, malformed list, or missing script report is
  /// unknown state. Only a complete matching report is evidence of membership.
  Future<LanRosterReport?> readReport() async {
    try {
      if (await FileSystemEntity.type(reportFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final file = await reportFile.open();
      late List<int> bytes;
      try {
        bytes = await file.read(maximumReportBytes + 1);
      } finally {
        await file.close();
      }
      if (bytes.length > maximumReportBytes) return null;
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map ||
          data['nonce'] != nonce ||
          data['ready'] != true ||
          data['epoch'] is! String ||
          !_validEpoch.hasMatch(data['epoch'] as String) ||
          data['sequence'] is! int ||
          (data['sequence'] as int) < 1 ||
          data['players'] is! List) {
        return null;
      }
      final players = <LanRosterPlayer>[];
      final ids = <String>{};
      for (final player in data['players'] as List) {
        if (player is! Map ||
            player['id'] is! String ||
            player['name'] is! String) {
          return null;
        }
        final id = player['id'] as String;
        final name = player['name'] as String;
        if (id.isEmpty ||
            id.length > 128 ||
            name.length > 256 ||
            !ids.add(id)) {
          return null;
        }
        players.add(LanRosterPlayer(id: id, name: name));
      }
      return LanRosterReport(
        epoch: data['epoch'] as String,
        sequence: data['sequence'] as int,
        players: List.unmodifiable(players),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

const _modMain = '''# -*- coding: utf-8 -*-
from mod.common.mod import Mod
import mod.server.extraServerApi as serverApi


@Mod.Binding(name="MCDevLanBridge", version="1.0.0")
class MCDevLanBridge(object):
    @Mod.InitServer()
    def InitServer(self):
        serverApi.RegisterSystem("MCDevLanBridge", "Roster",
                                 "mcdevLanBridgeScripts.server.RosterSystem")
''';

const _serverScript = r'''# -*- coding: utf-8 -*-
import json
import time
import mod.server.extraServerApi as serverApi

REPORT_PATH = __MCDEV_REPORT_PATH__
REPORT_NONCE = __MCDEV_REPORT_NONCE__
ServerSystem = serverApi.GetServerSystemCls()

try:
    _unicode = unicode
except NameError:
    _unicode = str


def _text(value):
    if isinstance(value, _unicode):
        return value
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return _unicode(value)


class RosterSystem(ServerSystem):
    def __init__(self, namespace, systemName):
        ServerSystem.__init__(self, namespace, systemName)
        self._ticks = 29
        self._sequence = 0
        # The launcher can distinguish a freshly re-entered world from a stale
        # file even though this process and its per-launch nonce did not change.
        self._epoch = "%d-%d" % (int(time.time() * 1000000), id(self))
        self._reported_error = False
        self.ListenForEvent(serverApi.GetEngineNamespace(),
                            serverApi.GetEngineSystemName(),
                            "OnScriptTickServer", self, self.OnTick)

    def OnTick(self, *args):
        self._ticks += 1
        if self._ticks < 30:
            return
        self._ticks = 0
        try:
            players = []
            for playerId in serverApi.GetPlayerList():
                name = self.CreateComponent(playerId, "Minecraft", "name").GetName()
                players.append({"id": _text(playerId), "name": _text(name or "")})
            self._sequence += 1
            payload = json.dumps({"nonce": REPORT_NONCE, "ready": True,
                                  "epoch": self._epoch,
                                  "sequence": self._sequence, "players": players},
                                 ensure_ascii=True).encode("ascii")
            if len(payload) > 262144:
                return
            # Readers reject a partially written JSON document and retry. The
            # file is always closed so a stopped world cannot refresh its lease.
            with open(REPORT_PATH, "wb") as output:
                output.write(payload)
            if self._sequence == 1:
                print("MCDEV_LAN_BRIDGE ready players=%d" % len(players))
            self._reported_error = False
        except Exception:
            # Diagnostics must never break the developer's gameplay scripts or
            # expose the per-launch nonce in normal game logs.
            if not self._reported_error:
                print("MCDEV_LAN_BRIDGE report unavailable")
                self._reported_error = True

    def Destroy(self):
        self.UnListenForEvent(serverApi.GetEngineNamespace(),
                              serverApi.GetEngineSystemName(),
                              "OnScriptTickServer", self, self.OnTick)
''';
