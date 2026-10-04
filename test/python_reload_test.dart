import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/mod_log_capture_io.dart';
import 'package:mcdev_income/development/python_reload_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Directory source;
  late Directory mounted;
  late PythonReloadSession session;
  Future<void> write(Directory root, String name, String value) async {
    final file = File(p.join(root.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-reload-');
    source = Directory(p.join(temp.path, 'source'));
    mounted = Directory(p.join(temp.path, 'mounted'));
    for (final root in [source, mounted]) {
      await write(
        root,
        'manifest.json',
        '{"header":{"uuid":"fixture"},"modules":[{"type":"data"}]}',
      );
      await write(
        root,
        'scripts/__init__.py',
        '# -*- coding: utf-8 -*-\n"""原文"""\nfrom __future__ import division\n',
      );
      await write(root, 'scripts/logic.py', 'VALUE = 1\n');
      await write(root, 'scripts/modMain.py', '# fixture entry point\n');
      await write(root, 'entity.json', '{"unchanged":true}');
    }
    session = await PythonReloadSession.capture([
      PythonReloadPack(source.path, mounted.path),
    ]);
  });
  tearDown(() async => temp.delete(recursive: true));

  test('packaged native DLL is pinned x64 PE', () async {
    final bytes = await File(
      'assets/development/python-reload.dll',
    ).readAsBytes();
    expect(sha256.convert(bytes).toString(), pythonReloadDllHash);
    final data = ByteData.sublistView(bytes);
    expect(data.getUint16(0, Endian.little), 0x5a4d);
    final header = data.getUint32(0x3c, Endian.little);
    expect(data.getUint32(header, Endian.little), 0x4550);
    expect(data.getUint16(header + 4, Endian.little), 0x8664);
    expect(data.getUint16(header + 22, Endian.little) & 0x2000, isNonZero);
  });

  test(
    'wrong game binary is rejected before writing any runtime files',
    () async {
      final exe = File(p.join(temp.path, 'game.exe'));
      await exe.writeAsString('other build');
      await expectLater(
        preparePythonReloadDll(p.join(temp.path, 'runtime'), exe),
        throwsException,
      );
      expect(await Directory(p.join(temp.path, 'runtime')).exists(), isFalse);
    },
  );

  test(
    'only changed Python snapshots are staged, caches removed and baseline committed',
    () async {
      expect((await session.changes()).isEmpty, isTrue);
      await write(source, 'scripts/logic.py', 'VALUE = 2\n');
      await write(source, 'entity.json', '{"unchanged":false}');
      await write(mounted, 'scripts/logic.pyc', 'old bytecode');
      final change = await session.changes();
      expect(change.count, 1);
      expect(
        change.requestFiles((path) => path).single['module'],
        'scripts.logic',
      );
      await write(source, 'scripts/logic.py', 'VALUE = 3\n');
      await change.stage(() {});
      expect(
        await File(p.join(mounted.path, 'scripts/logic.py')).readAsString(),
        'VALUE = 2\n',
      );
      expect(
        await File(p.join(source.path, 'scripts/logic.py')).readAsString(),
        'VALUE = 3\n',
      );
      expect(
        await File(p.join(mounted.path, 'scripts/logic.pyc')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(mounted.path, 'entity.json')).readAsString(),
        '{"unchanged":true}',
      );
      change.commit();
      expect((await session.changes()).count, 1);
      final next = await session.changes();
      await next.stage(() {});
      next.commit();
      expect((await session.changes()).isEmpty, isTrue);
    },
  );

  test(
    'rollback restores mounted sources and bytecode including new files',
    () async {
      await write(source, 'scripts/logic.py', 'VALUE = 2\n');
      await write(source, 'scripts/new.py', 'NEW = True\n');
      await write(mounted, 'scripts/logic.pyo', 'cache');
      final change = await session.changes();
      await change.stage(() {});
      await change.rollback();
      expect(
        await File(p.join(mounted.path, 'scripts/logic.py')).readAsString(),
        'VALUE = 1\n',
      );
      expect(
        await File(p.join(mounted.path, 'scripts/logic.pyo')).readAsString(),
        'cache',
      );
      expect(
        await File(p.join(mounted.path, 'scripts/new.py')).exists(),
        isFalse,
      );
      expect((await session.changes()).count, 2);
    },
  );

  test('cancellation during staging rolls back the whole batch', () async {
    await write(source, 'scripts/logic.py', 'VALUE = 2\n');
    await write(source, 'scripts/new.py', 'NEW = True\n');
    final change = await session.changes();
    var checked = 0;
    await expectLater(
      change.stage(() {
        if (++checked == 2) throw StateError('world exited');
      }),
      throwsStateError,
    );
    expect(
      await File(p.join(mounted.path, 'scripts/logic.py')).readAsString(),
      'VALUE = 1\n',
    );
    expect(
      await File(p.join(mounted.path, 'scripts/new.py')).exists(),
      isFalse,
    );
  });

  test(
    'initializer update retains logging bootstrap and exact original bytes',
    () async {
      await prepareModLogCapture([mounted]);
      final init = File(p.join(mounted.path, 'scripts/__init__.py'));
      final before = (await init.readAsString()).split('\n');
      final text =
          '# -*- coding: utf-8 -*-\n"""更新后的文档"""\nfrom __future__ import division\nVALUE = 2\n';
      await write(source, 'scripts/__init__.py', text);
      final changes = await session.changes();
      await changes.stage(() {});
      final after = (await init.readAsString()).split('\n');
      expect(after[2], before[2]);
      final original =
          jsonDecode(after[1].substring('# MCDEV_ORIGINAL_INIT_V1 '.length))
              as Map;
      expect(utf8.decode(base64Decode(original['data'])), text);
      expect(after[3], contains(base64Encode(utf8.encode(text))));
      expect(
        await File(p.join(source.path, 'scripts/__init__.py')).readAsString(),
        text,
      );
      await changes.rollback();
      expect(await init.readAsString(), before.join('\n'));
    },
  );

  test('deleted files and changed manifests require restart', () async {
    final logic = File(p.join(source.path, 'scripts/logic.py'));
    await logic.delete();
    await expectLater(session.changes(), throwsException);
    await write(source, 'scripts/logic.py', 'VALUE = 1\n');
    await write(source, 'manifest.json', '{"header":{"uuid":"different"}}');
    await expectLater(session.changes(), throwsException);
  });

  test(
    'source links, overlapping roots and duplicate modules are rejected',
    () async {
      await expectLater(
        PythonReloadSession.capture([
          PythonReloadPack(source.path, source.path),
        ]),
        throwsException,
      );
      final other = Directory(p.join(temp.path, 'other'));
      await write(other, 'manifest.json', '{}');
      await write(other, 'scripts/logic.py', 'VALUE = 2\n');
      await expectLater(
        PythonReloadSession.capture([
          PythonReloadPack(source.path, mounted.path),
          PythonReloadPack(source.path, other.path),
        ]),
        throwsException,
      );
      if (!Platform.isWindows) {
        await Link(
          p.join(source.path, 'linked.py'),
        ).create(p.join(mounted.path, 'scripts/logic.py'));
        await expectLater(session.changes(), throwsException);
      }
    },
  );

  Future<PythonReloadBridge> bridge() => PythonReloadBridge.create(
    behaviorPacks: p.join(temp.path, 'behavior_packs'),
    testDirectory: temp.path,
    gamePath: (path) => path,
    roots: ['scripts'],
  );
  Future<void> report(
    PythonReloadBridge bridge, {
    String? nonce,
    String epoch = 'world',
    int sequence = 1,
    Map<String, Object>? result,
  }) => File(p.join(bridge.directory.path, 'report.json')).writeAsString(
    jsonEncode({
      'nonce': nonce ?? bridge.nonce,
      'epoch': epoch,
      'sequence': sequence,
      'result': result,
    }),
  );

  test(
    'bridge requires fresh nonce heartbeat and matching acknowledgement',
    () async {
      final b = await bridge();
      expect(b.ready, isFalse);
      await report(b, nonce: 'old');
      expect(await b.poll(), isNull);
      expect(b.ready, isFalse);
      await report(b);
      await b.poll();
      expect(b.ready, isTrue);
      final pending = b.request(
        id: 'request',
        operation: 'validate',
        worldEpoch: 'world',
        files: [],
        checkCurrent: () {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await report(
        b,
        sequence: 2,
        result: {'id': 'request', 'operation': 'apply', 'ok': true},
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await report(
        b,
        sequence: 3,
        result: {'id': 'request', 'operation': 'validate', 'ok': true},
      );
      expect((await pending)['ok'], isTrue);
      expect(
        await File(p.join(b.directory.path, 'request.json')).exists(),
        isFalse,
      );
      await b.close();
      expect(b.ready, isFalse);
    },
  );

  test(
    'bridge cancels on world change, close or timeout and removes pending request',
    () async {
      final b = await bridge();
      await report(b);
      await b.poll();
      final pending = b.request(
        id: 'request',
        operation: 'validate',
        worldEpoch: 'world',
        files: [],
        checkCurrent: () {},
      );
      final assertion = expectLater(pending, throwsException);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await report(b, epoch: 'new-world');
      await assertion;
      await expectLater(
        b.request(
          id: 'timeout',
          operation: 'validate',
          worldEpoch: 'new-world',
          files: [],
          checkCurrent: () {},
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        await File(p.join(b.directory.path, 'request.json')).exists(),
        isFalse,
      );
      await b.close();
      await expectLater(
        b.request(
          id: 'closed',
          operation: 'apply',
          worldEpoch: 'new-world',
          files: [],
          checkCurrent: () {},
        ),
        throwsException,
      );
    },
  );
}
