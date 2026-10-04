// Opt-in check of a downloaded archive, without login or network access.
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/launcher_io.dart';

void main() {
  test(
    'downloaded game archive extracts and verifies on Windows',
    () async {
      final zip = Platform.environment['MCDEV_GAME_ZIP'];
      final patch = Platform.environment['MCDEV_GAME_PATCH'];
      if (zip == null || patch == null) {
        throw StateError('Set MCDEV_GAME_ZIP and MCDEV_GAME_PATCH.');
      }
      final parent = await Directory(
        p.absolute('build', 'windows-install-smoke'),
      ).create(recursive: true);
      final stage = await parent.createTemp('game-');
      final input = InputFileStream(zip);
      try {
        final archive = ZipDecoder().decodeStream(input);
        stdout.writeln('Extracting ${archive.length} entries to ${stage.path}');
        await extractGameZipSafe(archive, stage.path);
        final roots = <String>[];
        if (await File(p.join(stage.path, 'Minecraft.Windows.exe')).exists()) {
          roots.add(stage.path);
        } else {
          await for (final dir in stage.list()) {
            if (dir is Directory &&
                await File(
                  p.join(dir.path, 'Minecraft.Windows.exe'),
                ).exists()) {
              roots.add(dir.path);
            }
          }
        }
        expect(roots, hasLength(1));
        final hashes = parseGamePatch(await File(patch).readAsString());
        await verifyGameFiles(roots.single, hashes);
        stdout.writeln('Verified ${hashes.length} official file hashes.');
      } finally {
        await input.close();
        // Retain the uniquely named staging directory for diagnosis.
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
