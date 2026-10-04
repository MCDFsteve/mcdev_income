import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/lan_bridge_io.dart';

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('mcdev-lan-'));
  tearDown(() async => temp.delete(recursive: true));

  Future<LanRosterBridge> create([String instance = 'host']) {
    return LanRosterBridge.create(
      behaviorPacksDirectory: p.join(temp.path, instance, 'behavior_packs'),
      reportPath: p.join(temp.path, instance, 'lan-roster.json'),
      windowsReportPath: r'C:\MCDevTests\lan-roster.json',
    );
  }

  Map<String, Object> report(LanRosterBridge bridge) => {
    'nonce': bridge.nonce,
    'ready': true,
    'epoch': '1790942276935324-3141592',
    'sequence': 1,
    'players': [
      {'id': '-4294967295', 'name': 'Developer'},
      {'id': '42', 'name': '玩家二'},
    ],
  };

  test(
    'stages a separate server pack with a private report generation',
    () async {
      final first = await create();
      final second = await create('another');
      expect(first.nonce, isNot(second.nonce));
      expect(await first.readReport(), isNull);
      final pack = p.join(
        temp.path,
        'host',
        'behavior_packs',
        first.directoryName,
      );
      final manifest = jsonDecode(
        await File(p.join(pack, 'manifest.json')).readAsString(),
      );
      expect(manifest['header']['uuid'], first.uuid);
      expect(manifest['modules'][0]['type'], 'data');
      final source = await File(
        p.join(pack, 'mcdevLanBridgeScripts', 'server.py'),
      ).readAsString();
      expect(source, contains(jsonEncode(r'C:\MCDevTests\lan-roster.json')));
      expect(source, contains(first.nonce));
      expect(source, isNot(contains(second.nonce)));
      expect(source, isNot(contains('__MCDEV_REPORT_')));
    },
  );

  test(
    'generated server script reports players without restarting networking',
    () async {
      final bridge = await create();
      final source = p.join(
        temp.path,
        'host',
        'behavior_packs',
        bridge.directoryName,
        'mcdevLanBridgeScripts',
        'server.py',
      );
      final result = await Process.run('python3', [
        '-c',
        _pythonRuntimeTest,
        source,
        bridge.reportFile.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('mock server runtime passed'));
      expect(result.stdout, isNot(contains(bridge.nonce)));
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );

  test('only complete matching snapshots count as world membership', () async {
    final bridge = await create();
    await bridge.reportFile.writeAsString(jsonEncode(report(bridge)));
    final current = await bridge.readReport();
    expect(current?.ready, isTrue);
    expect(current?.epoch, '1790942276935324-3141592');
    expect(current?.sequence, 1);
    expect(current?.players.map((p) => p.name), ['Developer', '玩家二']);
    for (final mutation in [
      {'nonce': 'another world'},
      {'ready': false},
      {'epoch': null},
      {'epoch': ''},
      {'epoch': 123},
      {'epoch': '1790942276935324-/etc'},
      {'epoch': '${'1' * 21}-42'},
      {'sequence': 0},
      {'sequence': '1'},
      {
        'players': [
          {'id': '42', 'name': 'First'},
          {'id': '42', 'name': 'Duplicate'},
        ],
      },
      {
        'players': [
          {'id': 42, 'name': 'Invalid'},
        ],
      },
    ]) {
      await bridge.reportFile.writeAsString(
        jsonEncode({...report(bridge), ...mutation}),
      );
      expect(await bridge.readReport(), isNull);
    }
    await bridge.reportFile.writeAsString('{"nonce":');
    expect(await bridge.readReport(), isNull);
    await bridge.reportFile.writeAsString(
      ' ' * (LanRosterBridge.maximumReportBytes + 1),
    );
    expect(await bridge.readReport(), isNull);
  });

  test(
    'a re-entered world has a new epoch while its sequence restarts',
    () async {
      final bridge = await create();
      await bridge.reportFile.writeAsString(
        jsonEncode({...report(bridge), 'sequence': 80}),
      );
      final before = await bridge.readReport();
      await bridge.reportFile.writeAsString(
        jsonEncode({...report(bridge), 'epoch': '1790942280935324-3141592'}),
      );
      final after = await bridge.readReport();
      expect(before?.sequence, 80);
      expect(after?.sequence, 1);
      expect(after?.epoch, isNot(before?.epoch));
    },
  );

  test('restart drops stale reports and accepts a real empty world', () async {
    final previous = await create();
    await previous.reportFile.writeAsString(jsonEncode(report(previous)));
    final next = await create();
    expect(await next.readReport(), isNull);
    await next.reportFile.writeAsString(jsonEncode(report(previous)));
    expect(await next.readReport(), isNull);
    await next.reportFile.writeAsString(
      jsonEncode({...report(next), 'players': <Object>[]}),
    );
    expect((await next.readReport())?.players, isEmpty);
  });

  test(
    'does not replace a developer-owned pack with the reserved name',
    () async {
      final bridge = await create();
      final pack = Directory(
        p.join(temp.path, 'host', 'behavior_packs', bridge.directoryName),
      );
      await File(p.join(pack.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'header': {'uuid': 'user-pack'},
        }),
      );
      await expectLater(create(), throwsA(isA<FileSystemException>()));
      expect(
        await File(p.join(pack.path, 'manifest.json')).readAsString(),
        contains('user-pack'),
      );
    },
  );

  test('guest receives only the exact active host bridge snapshot', () async {
    final host = await create();
    final previous = await create('guest');
    await File(
      p.join(host.packDirectory.path, 'private-report.json'),
    ).writeAsString('not a pack file');
    await File(
      p.join(
        previous.packDirectory.path,
        'mcdevLanBridgeScripts',
        'server.pyc',
      ),
    ).writeAsBytes([1, 2, 3]);
    await host.copyToGuest(
      behaviorPacksDirectory: p.dirname(previous.packDirectory.path),
    );
    final files = await previous.packDirectory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .toList();
    expect(files, hasLength(4));
    for (final guestFile in files) {
      final relative = p.relative(
        guestFile.path,
        from: previous.packDirectory.path,
      );
      expect(
        await File(guestFile.path).readAsBytes(),
        await File(p.join(host.packDirectory.path, relative)).readAsBytes(),
      );
    }
    final server = await File(
      p.join(previous.packDirectory.path, 'mcdevLanBridgeScripts', 'server.py'),
    ).readAsString();
    expect(server, contains(host.nonce));
    expect(server, isNot(contains(previous.nonce)));
    expect(await host.reportFile.exists(), isFalse);
    expect(await previous.reportFile.exists(), isFalse);
  });

  test('guest snapshot does not overwrite other content or the host', () async {
    final host = await create();
    final guest = await create('guest');
    final other = File(p.join(guest.packDirectory.path, 'developer.txt'));
    await other.writeAsString('keep');
    await expectLater(
      host.copyToGuest(
        behaviorPacksDirectory: p.dirname(guest.packDirectory.path),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await other.readAsString(), 'keep');
    await expectLater(
      host.copyToGuest(
        behaviorPacksDirectory: p.dirname(host.packDirectory.path),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await host.packDirectory.exists(), isTrue);
    await other.delete();
    final manifest = File(p.join(guest.packDirectory.path, 'manifest.json'));
    await manifest.writeAsString('{"header":{"uuid":"developer"}}');
    await expectLater(
      host.copyToGuest(
        behaviorPacksDirectory: p.dirname(guest.packDirectory.path),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await manifest.readAsString(), contains('developer'));
  });

  test('stale host objects cannot copy a replacement launch bridge', () async {
    final old = await create();
    final current = await create();
    final destination = p.join(temp.path, 'guest', 'behavior_packs');
    await expectLater(
      old.copyToGuest(behaviorPacksDirectory: destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory(destination).exists(), isFalse);
    await current.copyToGuest(behaviorPacksDirectory: destination);
    expect(
      await Directory(p.join(destination, current.directoryName)).exists(),
      isTrue,
    );
  });

  test(
    'guest snapshot rejects symlinked files and destinations',
    () async {
      final host = await create();
      final guest = await create('guest');
      final destination = p.dirname(guest.packDirectory.path);
      final external = File(p.join(temp.path, 'external.txt'));
      await external.writeAsString('keep');
      final hostServer = File(
        p.join(host.packDirectory.path, 'mcdevLanBridgeScripts', 'server.py'),
      );
      final source = await hostServer.readAsBytes();
      await hostServer.delete();
      await Link(hostServer.path).create(external.path);
      await expectLater(
        host.copyToGuest(behaviorPacksDirectory: destination),
        throwsA(isA<FileSystemException>()),
      );
      await Link(hostServer.path).delete();
      await hostServer.writeAsBytes(source);
      final guestManifest = File(
        p.join(guest.packDirectory.path, 'manifest.json'),
      );
      await guestManifest.delete();
      await Link(guestManifest.path).create(external.path);
      await expectLater(
        host.copyToGuest(behaviorPacksDirectory: destination),
        throwsA(isA<FileSystemException>()),
      );
      await guest.packDirectory.delete(recursive: true);
      await Link(guest.packDirectory.path).create(host.packDirectory.path);
      await expectLater(
        host.copyToGuest(behaviorPacksDirectory: destination),
        throwsA(isA<FileSystemException>()),
      );
      expect(await external.readAsString(), 'keep');
      expect(await hostServer.readAsBytes(), source);
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );
}

const _pythonRuntimeTest = r'''
import contextlib
import io
import json
import sys
import types

state = {"players": [], "handler": None, "clock": 100, "error": False}
calls = []
attempts = []

class ServerSystem(object):
    def __init__(self, namespace, name):
        pass
    def ListenForEvent(self, *args):
        pass
    def UnListenForEvent(self, *args):
        pass
    def CreateComponent(self, playerId, namespace, name):
        return types.SimpleNamespace(GetName=lambda: "Developer")

api = types.ModuleType("mod.server.extraServerApi")
api.GetServerSystemCls = lambda: ServerSystem
api.GetEngineNamespace = lambda: "Minecraft"
api.GetEngineSystemName = lambda: "engine"
api.GetPlayerList = lambda: state["players"]
mod = types.ModuleType("mod")
mod.server = types.ModuleType("mod.server")
mod.server.extraServerApi = api
sys.modules.update({"mod": mod, "mod.server": mod.server,
                    "mod.server.extraServerApi": api})

network = types.ModuleType("_network")
def get_handler():
    attempts.append(state["clock"])
    return state["handler"]
network.get_game_network_handler = get_handler
def host(*args):
    calls.append(args)
    if state["error"]:
        raise RuntimeError("do not disclose native payload")
    return None
network.host = host

namespace = {"__name__": "mcdev_bridge_test"}
with open(sys.argv[1], "r") as source:
    exec(compile(source.read(), sys.argv[1], "exec"), namespace)
namespace["REPORT_PATH"] = sys.argv[2]
namespace["time"] = types.SimpleNamespace(time=lambda: state["clock"])
RosterSystem = namespace["RosterSystem"]
captured = io.StringIO()
def tick(system):
    system._ticks = 29
    system.OnTick()
    with open(sys.argv[2], "r") as report:
        return json.load(report)

sys.modules["_network"] = network
with contextlib.redirect_stdout(captured):
    system = RosterSystem("bridge", "roster")
    assert tick(system)["players"] == []
    state["players"] = ["42"]
    before = tick(system)
    assert before["players"][0]["name"] == "Developer"
    state["clock"] += 5
    state["handler"] = object()
    after = tick(system)
    assert after["sequence"] > before["sequence"]
    # Late _network.host restarts the transport and disconnects the local host.
    # A roster bridge must never call it, including across world re-entry.
    assert calls == [] and attempts == []
    system.Destroy()
    reopened = RosterSystem("bridge", "roster")
    again = tick(reopened)
    assert again["epoch"] != after["epoch"] and again["sequence"] == 1
    assert calls == [] and attempts == []

output = captured.getvalue()
assert "hosting requested" not in output
assert namespace["REPORT_NONCE"] not in output
print("mock server runtime passed")
''';
