import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/mod_log_capture_io.dart';
import 'package:mcdev_income/development/mod_log_filter.dart';
import 'package:mcdev_income/development/mod_log_io.dart';

final sources = ModLogSources(
  modules: ['MyModScripts'],
  paths: ['mcdev_user_pack', 'entities/my_mob.json'],
  identifiers: ['my_mod:mob'],
);

String printRecord(
  String marker,
  String text, {
  String module = 'MyModScripts.main',
}) =>
    '$marker:P:${base64Encode(utf8.encode(module))}:${base64Encode(utf8.encode(text))}\n';

const modError =
    'Traceback (most recent call last):\n'
    '  File "mod/common/minecraftMod.py", line 895, in ImportModMain\n'
    '  File "MyModScripts.modMain", line 7, in InitServer\n'
    'RuntimeError: selected mod failed\n';

void main() {
  test(
    'decoder handles fragmented UTF-8 and multiple split command frames',
    () {
      final text = StringBuffer();
      final decoder = ModLogDecoder(text.write);
      final wire = [
        ...utf8.encode('中文前\n'),
        255,
        ...utf8.encode('private profiler command'),
        255,
        ...utf8.encode('后\n'),
        255,
        ...utf8.encode('another command'),
        255,
        ...utf8.encode('tail'),
      ];
      for (final byte in wire) {
        decoder.add([byte]);
      }
      decoder.close();
      decoder.close();
      decoder.add(utf8.encode('late'));
      expect(text.toString(), '中文前\n后\ntail');
    },
  );

  test(
    'only marked user prints survive, even if they resemble engine output',
    () {
      final text = StringBuffer();
      final filter = ModLogFilter(
        marker: 'session',
        sources: sources,
        onText: text.write,
      );
      final input =
          '[2026-10-03 11:00:00,123] [INFO][Developer] start\n'
          'MCDEV_LAN_BRIDGE ready players=0\n'
          "('=======InitState equipped ', '-123', False)\n"
          '[2026-10-03 11:00:00,123] [ERROR][Engine] get_world_record: None\n'
          '${printRecord('session', '中文\n多行\n[INFO][Engine] my print\n')}'
          '${printRecord('foreign-session', 'wrong session\n')}'
          '${printRecord('session', 'hidden pack\n', module: 'mcdevLanBridgeScripts.server')}'
          'session:P:malformed:bad!\n';
      for (var i = 0; i < input.length; i += 3) {
        filter.add(input.substring(i, (i + 3).clamp(0, input.length)));
      }
      filter.close();
      expect(text.toString(), '中文\n多行\n[INFO][Engine] my print\n');
    },
  );

  test(
    'syntax/import/runtime errors retain full frames; engine errors do not',
    () {
      final output = StringBuffer();
      final filter = ModLogFilter(
        marker: 's',
        sources: sources,
        onText: output.write,
      );
      const syntax =
          'Traceback (most recent call last):\n'
          '  File "redirect.py", line 89, in load_module\n'
          '  File "MyModScripts.bad", line 1\n'
          '    def broken(:\n'
          '               ^\n'
          'SyntaxError: invalid syntax\n';
      const imported =
          'Traceback (most recent call last):\n'
          '  File "MyModScripts.modMain", line 2\n'
          'ImportError: No module named missing_dependency\n';
      filter.add(
        'Traceback (most recent call last):\n'
        '  File "framework/log_mgr.py", line 2242\n'
        "AttributeError: 'NoneType' object has no attribute 'global_chat_mgr'\n"
        '$modError$syntax$imported',
      );
      filter.close();
      expect(output.toString(), '$modError$syntax$imported');
    },
  );

  test('source boundaries reject similar engine module and content names', () {
    expect(sources.mentionsSource('MyModScripts.modMain'), isTrue);
    expect(sources.mentionsSource('MyModScripts/server.py'), isTrue);
    expect(sources.mentionsSource('otherMyModScripts.modMain'), isFalse);
    expect(sources.mentionsSource('my_mod:mob'), isTrue);
    expect(sources.mentionsSource('my_mod:mob_extra'), isFalse);
  });

  test(
    'unfinished user traceback flushes on close; an engine one is discarded',
    () {
      final text = StringBuffer();
      final filter = ModLogFilter(
        marker: 's',
        sources: sources,
        onText: text.write,
      );
      filter.add(
        'Traceback (most recent call last):\n'
        '  File "MyModScripts.server", line 30',
      );
      filter.close();
      filter.close();
      filter.add('late');
      expect(text.toString(), contains('line 30\n'));
    },
  );

  test(
    'native loading errors require a selected source and preserve their stack',
    () {
      final text = StringBuffer();
      final filter = ModNativeErrorFilter(sources, text.write);
      const kept =
          '[2026-10-03 11:00:00:123 ERROR ENTITY 1 2] '
          'Unable to parse entities/my_mob.json (my_mod:mob)\n'
          'Call stack:[\n'
          '  { FileSystem.cpp, 99 }\n'
          ']\n';
      const core =
          '[2026-10-03 11:00:00:124 INFO UNKNOWN 1 2] '
          'Error: generic: invalid argument (22)\n'
          'Call stack:[\n'
          '  { FileSystem.cpp, 10 }\n'
          ']\n';
      final mixed =
          '$core$kept'
          '[2026-10-03 11:00:00:125 INFO ENTITY 1 2] loaded my_mod:mob\n'
          'unrelated raw engine message\n';
      for (final character in mixed.split('')) {
        filter.add(character);
      }
      filter.close();
      expect(text.toString(), kept);
    },
  );

  test('native buffering is bounded and does not absorb Python errors', () {
    final text = StringBuffer();
    final filter = ModNativeErrorFilter(sources, text.write);
    filter.add(
      '[2026-10-03 11:00:00:124 INFO UNKNOWN 1 2] engine\n'
      '$modError${'x' * (300 * 1024)}\n',
    );
    filter.close();
    expect(text.toString(), isEmpty);
  });

  test(
    'server isolates interleaved peers, session markers and shutdown',
    () async {
      final text = StringBuffer();
      final done = Completer<void>();
      final server = await ModLogServer.start(
        marker: 's',
        sources: sources,
        onText: (value) {
          text.write(value);
          if (text.toString().contains('selected mod failed') &&
              text.toString().contains('other peer\n') &&
              !done.isCompleted) {
            done.complete();
          }
        },
      );
      final first = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final second = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      first.listen((_) {}, onError: (Object _) {});
      second.listen((_) {}, onError: (Object _) {});
      first.done.ignore();
      second.done.ignore();
      try {
        first.add(utf8.encode(modError.substring(0, 10)));
        await first.flush();
        second.add(utf8.encode(printRecord('s', 'other peer\n')));
        await second.flush();
        first.add(utf8.encode(modError.substring(10)));
        await first.flush();
        await done.future.timeout(const Duration(seconds: 3));
        await server.close();
        final snapshot = text.toString();
        expect(snapshot, contains(modError));
        expect(snapshot, contains('other peer\n'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(text.toString(), snapshot);
        await server.close();
      } finally {
        first.destroy();
        second.destroy();
        await server.close();
      }
    },
  );

  test(
    'staged capture preserves modMain and restores original init for LAN guests',
    () async {
      final temp = await Directory.systemTemp.createTemp('mod-log-capture-');
      addTearDown(() => temp.delete(recursive: true));
      final pack = Directory(p.join(temp.path, 'mcdev_user_pack'));
      final script = Directory(p.join(pack.path, 'MyModScripts'));
      await script.create(recursive: true);
      const original =
          '# coding: utf-8\n"""docstring"""\n'
          'from __future__ import division\nprint "中文"\n';
      final init = File(p.join(script.path, '__init__.py'));
      final main = File(p.join(script.path, 'modMain.py'));
      await init.writeAsString(original);
      await main.writeAsString('import missing_dependency\n');
      final badJson = File(p.join(pack.path, 'entities', 'my_mob.json'));
      await badJson.parent.create();
      await badJson.writeAsString('{');
      final first = await prepareModLogCapture([pack]);
      final second = await prepareModLogCapture([pack]);
      expect(first.marker, isNot(second.marker));
      expect(first.sources.ownsModule('MyModScripts.modMain'), isTrue);
      expect(second.sources.mentionsSource('entities/my_mob.json'), isTrue);
      final rewritten = await init.readAsString();
      final metadata = jsonDecode(
        rewritten.split('\n')[1].substring('# MCDEV_ORIGINAL_INIT_V1 '.length),
      );
      expect(utf8.decode(base64.decode(metadata['data'] as String)), original);
      expect(await main.readAsString(), 'import missing_dependency\n');
      // The former wrapper must not be embedded as this guest's original source.
      expect(rewritten, isNot(contains(first.marker)));
    },
  );
}
