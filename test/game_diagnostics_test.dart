import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/platform/file_game_diagnostics.dart';

void main() {
  test(
    'diagnostics follow new data, truncation, partial lines and new crashes',
    () async {
      final root = await Directory.systemTemp.createTemp('mcdev-diagnostics-');
      addTearDown(() => root.delete(recursive: true));
      final logs = await Directory(p.join(root.path, 'logs')).create();
      final crashes = await Directory(p.join(root.path, 'crashes')).create();
      final native = File(p.join(logs.path, 'Debug_Log.txt'));
      await native.writeAsString('set skin file not found old\n');
      await File(p.join(crashes.path, 'old.dmp')).writeAsString('old');
      final diagnostics = FileGameDiagnostics(
        dataDirectory: root.path,
        crashDirectory: crashes.path,
      );
      await diagnostics.prepare();
      expect(await diagnostics.poll(), isEmpty);
      await native.writeAsString('launchWorld starting', mode: FileMode.append);
      expect(await diagnostics.poll(), isEmpty);
      await native.writeAsString(' step\n', mode: FileMode.append);
      expect((await diagnostics.poll()).single.message, contains('加载测试世界'));
      await native.writeAsString('set skin file not found\n');
      expect((await diagnostics.poll()).single.message, contains('皮肤'));
      expect(await diagnostics.poll(), isEmpty);
      final python = File(p.join(root.path, 'mcp.log'));
      await python.writeAsString(
        '${base64Encode(utf8.encode('MCDEV_LAN_BRIDGE ready players=1'))}\n',
      );
      expect((await diagnostics.poll()).single.message, '世界脚本已运行。');
      await File(p.join(crashes.path, 'new.dmp')).writeAsString('new');
      expect((await diagnostics.poll()).single.fatal, isTrue);
      expect(await diagnostics.poll(), isEmpty);
    },
  );

  test(
    'SDK payloads and embedded credentials never enter diagnostic messages',
    () {
      expect(
        classifyNativeDiagnostic('login token=secret cookie=secret'),
        isNull,
      );
      final diagnostic = classifyNativeDiagnostic(
        'set skin file not found token=secret',
      );
      expect(diagnostic!.message, isNot(contains('secret')));
    },
  );
}
