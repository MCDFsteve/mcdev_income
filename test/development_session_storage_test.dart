import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'package:mcdev_income/storage/file_lock.dart';
import 'development_test.dart' show MemoryPreferences;

void main() {
  late Directory temporary;
  late MemoryPreferences preferences;
  late NativeDevelopmentStorage storage;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mcdev-session-storage-');
    temporary = Directory(await temporary.resolveSymbolicLinks());
    preferences = MemoryPreferences();
    storage = NativeDevelopmentStorage(
      preferences: preferences,
      defaultRoot: p.join(temporary.path, 'data'),
      lockPath: p.join(temporary.path, 'config', 'storage.lock'),
    );
    await storage.initialize();
  });

  tearDown(() async => temporary.delete(recursive: true));

  final gameRunning = throwsA(
    isA<DevelopmentStorageException>().having(
      (error) => error.message,
      'message',
      contains('退出所有测试游戏'),
    ),
  );

  for (final id in ['default', 'test_second']) {
    test('a running $id session blocks data moves and root changes', () async {
      final original = storage.paths.root;
      final lease = p.join(storage.paths.prefixes, '.session-$id.lock');
      final destination = p.join(temporary.path, 'moved');
      final save = File(p.join(storage.paths.prefixes, 'saved-world'));
      await save.writeAsString('existing world');

      // Game startup has already released the global storage lock. Only its
      // lifetime lease remains, as happens while another tab keeps running.
      await withFileLock(lease, () async {
        await expectLater(storage.migrateTo(destination), gameRunning);
        await expectLater(storage.initialize(root: destination), gameRunning);
        await expectLater(storage.useExisting(original), gameRunning);
        expect(storage.paths.root, original);
        expect(await Directory(destination).exists(), isFalse);
        expect(await save.readAsString(), 'existing world');
      });

      // A previous session leaves a lock file behind. Its unlocked file must
      // not prevent a later move, and the original save is still preserved.
      await storage.migrateTo(destination);
      expect(storage.paths.root, destination);
      expect(await save.readAsString(), 'existing world');
      expect(
        await File(
          p.join(destination, 'prefixes', 'saved-world'),
        ).readAsString(),
        'existing world',
      );
    });
  }

  test(
    'migration respects an active lease owned by another process',
    () async {
      final lease = p.join(
        storage.paths.prefixes,
        '.session-other_process.lock',
      );
      final process = await Process.start('/usr/bin/python3', [
        '-u',
        '-c',
        'import fcntl, sys\n'
            'with open(sys.argv[1], "a") as lease:\n'
            '    fcntl.lockf(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)\n'
            '    print("locked", flush=True)\n'
            '    sys.stdin.readline()\n',
        lease,
      ]);
      final errors = process.stderr.drain<void>();
      try {
        expect(
          await process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 10)),
          'locked',
        );
        await expectLater(
          storage.migrateTo(p.join(temporary.path, 'moved')),
          gameRunning,
        );
      } finally {
        process.stdin.writeln();
        await process.stdin.close();
        await process.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        await errors;
      }
    },
    skip: !Platform.isMacOS,
  );

  test(
    'all leases are released when a later active session blocks a move',
    () async {
      final idleLease = p.join(storage.paths.prefixes, '.session-a_idle.lock');
      final activeLease = p.join(
        storage.paths.prefixes,
        '.session-z_active.lock',
      );
      await File(idleLease).writeAsString('');
      await withFileLock(activeLease, () async {
        await expectLater(
          storage.migrateTo(p.join(temporary.path, 'moved')),
          gameRunning,
        );
        // The first lease was acquired before the active one was discovered.
        // A rejected migration must release it so the idle tab can still start.
        var acquired = false;
        await withFileLock(idleLease, () async {
          acquired = true;
        }, wait: false);
        expect(acquired, isTrue);
      });
    },
  );

  test(
    'migration keeps tab identities while other roots keep their own tabs',
    () async {
      final source = storage.paths.root;
      const tabs = '{"ids":["default","second"],"selected":"second"}';
      await preferences.setString('development_test_tabs_v1:$source', tabs);
      final moved = p.join(temporary.path, 'moved');
      await storage.migrateTo(moved);
      expect(preferences.getString('development_test_tabs_v1:$moved'), tabs);
      expect(preferences.getString('development_test_tabs_v1:$source'), tabs);

      final unrelated = p.join(temporary.path, 'unrelated');
      await storage.initialize(root: unrelated);
      expect(
        preferences.getString('development_test_tabs_v1:$unrelated'),
        isNull,
      );
      await storage.useExisting(source);
      expect(preferences.getString('development_test_tabs_v1:$source'), tabs);
    },
  );
}
