// Diagnostic fixture only. Imported by the explicitly opted-in live LAN test.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Install into the isolated smoke-test BP before importing/launching it.
/// Returns the nonce required to distinguish this run's report from old files.
Future<String> installLiveLanFixtureServer(Directory behaviorPack) async {
  if (await FileSystemEntity.type(
        p.join(behaviorPack.path, 'manifest.json'),
        followLinks: false,
      ) !=
      FileSystemEntityType.file) {
    throw StateError('A diagnostic behavior pack manifest is required');
  }
  final random = Random.secure();
  final nonce = List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final scripts = Directory(
    p.join(behaviorPack.path, 'mcdevLanFixtureScripts'),
  );
  await scripts.create(recursive: true);
  await File(p.join(scripts.path, '__init__.py')).writeAsString('');
  await File(p.join(scripts.path, 'modMain.py')).writeAsString(_modMain);
  await File(p.join(scripts.path, 'server.py')).writeAsString(
    _serverScript.replaceFirst('__FIXTURE_NONCE__', jsonEncode(nonce)),
  );
  return nonce;
}

const _modMain = '''# -*- coding: utf-8 -*-
from mod.common.mod import Mod
import mod.server.extraServerApi as serverApi


@Mod.Binding(name="MCDevLanFixture", version="1.0.0")
class MCDevLanFixture(object):
    @Mod.InitServer()
    def InitServer(self):
        serverApi.RegisterSystem("MCDevLanFixture", "Verification",
                                 "mcdevLanFixtureScripts.server.VerificationSystem")
''';

// Official API evidence:
// https://mc.163.com/dev/mcmanual/mc-dev/mcdocs/1-ModAPI/接口/世界/指令.html#setcommand
// SetCommand(cmdStr, entityId, showOutput) -> bool (command execution success).
// The unpacked official BedWarsTemplate/script_World/worldServerSystem.py uses
// self.CreateComponent(serverApi.GetLevelId(), "Minecraft", "command").
// Official neteaseTrade/tradeServerSystem.py passes entityId for the @s origin.
// The official player-render API lists SetSkin/ResetSkin, not a model getter;
// do not infer a real rendered skin from the launcher's requested skin setting.
// Official CustomDimensionTemplate/portalGateDemoScripts/server/Portal.py's
// TravelPlayerToPortal uses CreateRot(entityId).SetRot((pitch, yaw)) and
// CreatePos(entityId).SetPos((x, y, z)) to move the exact player entity.
// https://mc.163.com/dev/mcmanual/mc-dev/mcdocs/1-ModAPI/接口/实体/属性.html
// SetPos sets feet coordinates; SetPos and SetRot both return bool success.
const _serverScript = r'''# -*- coding: utf-8 -*-
import json
import time
import mod.server.extraServerApi as serverApi

REPORT_PATH = r"C:\MCDevTests\lan-fixture.json"
NONCE = __FIXTURE_NONCE__
EXPECTED_NAMES = (u"Developer", u"测试史蒂夫", u"测试艾莉")
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


class VerificationSystem(ServerSystem):
    def __init__(self, namespace, name):
        ServerSystem.__init__(self, namespace, name)
        self._ticks = 0
        self._stable = 0
        self._stable_since = None
        self._done = False
        self._commands = []
        self._positions = []
        self.ListenForEvent(serverApi.GetEngineNamespace(),
                            serverApi.GetEngineSystemName(),
                            "OnScriptTickServer", self, self.OnTick)

    def _write(self, status, players, success=False, error=None):
        report = {"nonce": NONCE, "status": status, "success": success,
                  "players": sorted(players), "commands": self._commands,
                  "positions": self._positions,
                  "skin_model_verification": "requires_visual_inspection"}
        if error is not None:
            # Exception messages may include native identifiers. Keep only the
            # exception class; never write account/entity IDs or network data.
            report["error_type"] = type(error).__name__
        data = json.dumps(report, ensure_ascii=True).encode("ascii")
        with open(REPORT_PATH, "wb") as output:
            output.write(data)

    def _command(self, command, entityId, name):
        record = {"player": name, "command": command, "success": False}
        self._commands.append(record)
        try:
            component = self.CreateComponent(serverApi.GetLevelId(),
                                             "Minecraft", "command")
            result = component.SetCommand(command, entityId, True)
            record["success"] = result is True
            if not isinstance(result, bool):
                record["unexpected_result_type"] = type(result).__name__
        except Exception as error:
            record["error_type"] = type(error).__name__
        return record["success"]

    def _position(self, entityId, name, position, rotation):
        record = {"player": name, "position": position, "rotation": rotation,
                  "position_success": False, "rotation_success": False,
                  "success": False}
        self._positions.append(record)
        try:
            factory = serverApi.GetEngineCompFactory()
            record["position_success"] = factory.CreatePos(entityId).SetPos(position) is True
            record["rotation_success"] = factory.CreateRot(entityId).SetRot(rotation) is True
            record["success"] = record["position_success"] and record["rotation_success"]
        except Exception as error:
            record["error_type"] = type(error).__name__
        return record["success"]

    def OnTick(self, *args):
        if self._done:
            return
        self._ticks += 1
        if self._ticks % 30:
            return
        names = []
        try:
            players = {}
            for entityId in serverApi.GetPlayerList():
                name = _text(self.CreateComponent(entityId, "Minecraft",
                                                  "name").GetName() or "")
                names.append(name)
                players.setdefault(name, []).append(entityId)
            ready = len(names) == 3 and all(
                len(players.get(name, [])) == 1 for name in EXPECTED_NAMES)
            if ready:
                if self._stable == 0:
                    self._stable_since = time.time()
                self._stable += 1
            else:
                self._stable = 0
                self._stable_since = None
            # Server membership arrives before the guest finishes spawning.
            # Keep a real-time grace period before the one strict command pass.
            if self._stable < 3 or time.time() - self._stable_since < 15:
                self._write("waiting", names)
                return
            # Run once only after stable real membership and the spawn grace.
            self._done = True
            for name in EXPECTED_NAMES:
                self._command("/function mcdev_lan_verify", players[name][0], name)
            host = players[u"Developer"][0]
            # A small display stage in this disposable diagnostic world only.
            floor = self._command("/fill -7 150 -7 7 150 7 stone", host, u"Developer")
            # Clearing an already empty sky returns false. Place one block so
            # this setup command always has a real change to make.
            self._command("/setblock -7 151 -7 stone", host, u"Developer")
            clear = self._command("/fill -7 151 -7 7 155 7 air", host, u"Developer")
            self._command("/time set day", host, u"Developer")
            if floor and clear:
                positions = ((u"Developer", (0.5, 151, -4.5), (0, 0)),
                             (u"测试史蒂夫", (-1.5, 151, 0.5), (0, 180)),
                             (u"测试艾莉", (2.5, 151, 0.5), (0, 180)))
                for name, position, rotation in positions:
                    # Native command selectors do not resolve these LAN
                    # display names. Use the actual server entity IDs.
                    self._position(players[name][0], name, position, rotation)
            success = (len(self._commands) == 7 and len(self._positions) == 3
                       and all(command["success"] for command in self._commands)
                       and all(position["success"] for position in self._positions))
            self._write("complete", names, success)
            print("MCDEV_LAN_FIXTURE complete success=%s" % success)
        except Exception as error:
            self._done = True
            try:
                self._write("error", names, error=error)
            except Exception:
                pass
            print("MCDEV_LAN_FIXTURE failed")

    def Destroy(self):
        self.UnListenForEvent(serverApi.GetEngineNamespace(),
                              serverApi.GetEngineSystemName(),
                              "OnScriptTickServer", self, self.OnTick)
''';

void main() {
  test(
    'fixture executes only for three real unique players and reports failures',
    () async {
      final root = await Directory.systemTemp.createTemp('mcdev-lan-fixture-');
      try {
        await File(p.join(root.path, 'manifest.json')).writeAsString('{}');
        final nonce = await installLiveLanFixtureServer(root);
        final result = await Process.run('python3', [
          '-c',
          _runtimeTest,
          p.join(root.path, 'mcdevLanFixtureScripts', 'server.py'),
          p.join(root.path, 'report.json'),
          nonce,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, contains('fixture runtime checks passed'));
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );
}

const _runtimeTest = r'''
import json
import sys
import types

players = {}
commands = []
positions = []
rotations = []
fail = False
fail_position = False
fail_rotation = False
class ServerSystem(object):
    def __init__(self, *args): pass
    def ListenForEvent(self, *args): pass
    def UnListenForEvent(self, *args): pass
    def CreateComponent(self, entity, namespace, kind):
        if kind == "name":
            return types.SimpleNamespace(GetName=lambda: players[entity])
        assert entity == "level" and namespace == "Minecraft" and kind == "command"
        def execute(command, entityId, output):
            assert entityId in players and output is True
            commands.append((command, entityId))
            assert not command.startswith("/tp ")
            return False if fail and command.startswith("/function") else True
        return types.SimpleNamespace(SetCommand=execute)

class Factory(object):
    def CreatePos(self, entityId):
        assert entityId in players
        def set_position(position):
            positions.append((entityId, position))
            return not (fail_position and players[entityId] == "测试艾莉")
        return types.SimpleNamespace(SetPos=set_position)

    def CreateRot(self, entityId):
        assert entityId in players
        def set_rotation(rotation):
            rotations.append((entityId, rotation))
            return not (fail_rotation and players[entityId] == "测试艾莉")
        return types.SimpleNamespace(SetRot=set_rotation)

api = types.ModuleType("mod.server.extraServerApi")
api.GetServerSystemCls = lambda: ServerSystem
api.GetEngineNamespace = lambda: "Minecraft"
api.GetEngineSystemName = lambda: "engine"
api.GetLevelId = lambda: "level"
api.GetPlayerList = lambda: list(players)
api.GetEngineCompFactory = Factory
mod = types.ModuleType("mod")
mod.server = types.ModuleType("mod.server")
mod.server.extraServerApi = api
sys.modules.update({"mod": mod, "mod.server": mod.server,
                    "mod.server.extraServerApi": api})
scope = {"__name__": "fixture_test"}
with open(sys.argv[1], "r") as source:
    exec(compile(source.read(), sys.argv[1], "exec"), scope)
scope["REPORT_PATH"] = sys.argv[2]
assert scope["NONCE"] == sys.argv[3]
clock = [1000.0]
scope["time"] = types.SimpleNamespace(time=lambda: clock[0])

def tick(system):
    clock[0] += 5.0
    for unused in range(30): system.OnTick()
    with open(sys.argv[2], "r") as report: return json.load(report)

system = scope["VerificationSystem"]("fixture", "test")
assert tick(system)["players"] == [] and commands == []
players.update({"not-account-host": "Developer", "not-account-steve": "测试史蒂夫"})
assert tick(system)["status"] == "waiting" and commands == []
players["not-account-alex"] = "测试艾莉"
tick(system)
tick(system)
assert commands == []
assert tick(system)["status"] == "waiting" and commands == []
result = tick(system)
assert result["status"] == "complete" and result["success"] is True
assert len(commands) == 7
assert {entity for cmd,entity in commands if cmd.startswith("/function")} == set(players)
assert positions == [
    ("not-account-host", (0.5, 151, -4.5)),
    ("not-account-steve", (-1.5, 151, 0.5)),
    ("not-account-alex", (2.5, 151, 0.5)),
]
assert rotations == [("not-account-host", (0, 0)),
                     ("not-account-steve", (0, 180)),
                     ("not-account-alex", (0, 180))]
assert len(result["positions"]) == 3
assert result["skin_model_verification"] == "requires_visual_inspection"
assert "not-account" not in json.dumps(result)
assert len(result["players"]) == 3
tick(system)
assert len(commands) == 7 and len(positions) == 3

commands[:] = []
fail = True
system = scope["VerificationSystem"]("fixture", "test")
tick(system)
tick(system)
tick(system)
result = tick(system)
assert result["success"] is False
assert len([item for item in result["commands"] if not item["success"]]) == 3
assert "not-account" not in json.dumps(result)

commands[:] = []
fail = False
fail_position = True
system = scope["VerificationSystem"]("fixture", "test")
tick(system)
tick(system)
tick(system)
result = tick(system)
assert result["success"] is False and len(commands) == 7
failed = [item for item in result["positions"] if not item["success"]]
assert len(failed) == 1 and failed[0]["player"] == "测试艾莉"
assert failed[0]["position"] == [2.5, 151, 0.5]
assert failed[0]["position_success"] is False
assert failed[0]["rotation_success"] is True

commands[:] = []
fail_position = False
fail_rotation = True
system = scope["VerificationSystem"]("fixture", "test")
tick(system)
tick(system)
tick(system)
result = tick(system)
assert result["success"] is False and len(commands) == 7
failed = [item for item in result["positions"] if not item["success"]]
assert len(failed) == 1 and failed[0]["player"] == "测试艾莉"
assert failed[0]["position_success"] is True
assert failed[0]["rotation_success"] is False

commands[:] = []
players["duplicate-player"] = "测试艾莉"
system = scope["VerificationSystem"]("fixture", "test")
for unused in range(5): result = tick(system)
assert result["status"] == "waiting" and commands == []
assert len(result["players"]) == 4
print("fixture runtime checks passed")
''';
