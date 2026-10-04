import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/development/development_logs.dart';
import 'package:mcdev_income/development/log_dialog.dart';
import 'package:mcdev_income/development/log_format.dart';
import 'package:mcdev_income/development/log_store_io.dart';
import 'package:mcdev_income/development/log_save_path.dart';
import 'package:mcdev_income/ui/ore_material.dart';
import 'development_widget_test.dart' show host, FakeStorage;

class MemoryLogs extends DevelopmentLogStore {
  final content = <String, List<int>>{};
  String? exportedSource;
  String? exportedDestination;
  String? exportedText;
  bool original = false;
  bool failExport = false;
  int reads = 0;

  void put(String name, String text) =>
      content['/test/development/logs/$name'] = utf8.encode(text).toList();
  void append(String name, String text) =>
      content['/test/development/logs/$name']!.addAll(utf8.encode(text));

  @override
  Future<List<DevelopmentLogFile>> list() async => [
    for (final entry in content.entries)
      DevelopmentLogFile(entry.key, DateTime(2026), entry.value.length),
  ];
  @override
  Future<DevelopmentLogChunk> read(String path, {int? offset}) async {
    reads++;
    final bytes = content[path]!;
    final reset = offset != null && offset > bytes.length;
    return DevelopmentLogChunk(
      bytes: Uint8List.fromList(bytes.sublist(reset ? 0 : offset ?? 0)),
      nextOffset: bytes.length,
      reset: reset,
    );
  }

  @override
  Future<void> exportOriginal(String source, String destination) async {
    if (failExport) throw const FileSystemException('disk unavailable');
    exportedSource = source;
    exportedDestination = destination;
    original = true;
  }

  @override
  Future<void> exportText(
    String source,
    String destination,
    String text,
  ) async {
    if (failExport) throw const FileSystemException('disk unavailable');
    exportedSource = source;
    exportedDestination = destination;
    exportedText = text;
    original = false;
  }
}

Future<void> openLogs(
  WidgetTester tester,
  MemoryLogs logs, {
  Size size = const Size(1200, 800),
  bool dark = true,
  Future<String?> Function(String)? savePath,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    host(
      Builder(
        builder: (context) => OreButton(
          child: const Text('open logs'),
          onPressed: () => showOreDialog<void>(
            context: context,
            builder: (_) => DevelopmentLogDialog(
              storage: FakeStorage(),
              store: logs,
              savePath: savePath,
            ),
          ),
        ),
      ),
      dark: dark,
    ),
  );
  await tester.tap(find.text('open logs'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'default log source prefers a mod session over newer diagnostics',
    () async {
      final store = MemoryLogs()
        ..put('renderer-new.log', 'renderer details\n')
        ..put('test-last.log', 'mod output\n');
      final controller = DevelopmentLogController(store);
      await controller.refresh();
      expect(controller.selectedPath, '/test/development/logs/test-last.log');
      expect(controller.entries.single.text, 'mod output');
      expect(controller.files.last.label, startsWith('模组 ·'));
      controller.dispose();
    },
  );

  test('mod traceback header and native errors keep their error level', () {
    final buffer = DevelopmentLogBuffer();
    buffer.add(
      Uint8List.fromList(
        utf8.encode(
          'Traceback (most recent call last):\n'
          '  File "MyModScripts.modMain", line 7\n'
          'RuntimeError: failed\n'
          '[2026-10-03 11:00:00:123 ERROR ENTITY 1 2] bad mod JSON\n'
          '  source frame\n',
        ),
      ),
    );
    expect(
      buffer.entries.map((entry) => entry.level),
      everyElement(DevelopmentLogLevel.error),
    );
    buffer.close();
  });
  test(
    'macOS log export uses the owned native save panel and preserves cancellation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(developmentLogSaveChannel, (
        call,
      ) async {
        calls.add(call);
        return calls.length == 1 ? '/tmp/chosen.log' : null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(developmentLogSaveChannel, null),
      );
      expect(
        await chooseDevelopmentLogExport('test-filtered.log', filtered: true),
        '/tmp/chosen.log',
      );
      expect(calls.single.method, 'chooseLogExport');
      expect(calls.single.arguments, {
        'fileName': 'test-filtered.log',
        'filtered': true,
      });
      expect(
        await chooseDevelopmentLogExport('test.log', filtered: false),
        isNull,
      );
    },
  );
  test(
    'level classification understands Wine, game, JSON and stack traces',
    () {
      expect(
        classifyLogLine('016c:err:module:loader failed'),
        DevelopmentLogLevel.error,
      );
      expect(
        classifyLogLine('016c:fixme:system query'),
        DevelopmentLogLevel.debug,
      );
      expect(
        classifyLogLine('[Scripting][warning] missing value'),
        DevelopmentLogLevel.warning,
      );
      expect(
        classifyLogLine('2026-09-30T10:01:02.003 INFO ready'),
        DevelopmentLogLevel.info,
      );
      expect(
        classifyLogLine('{"level":"error","message":"bad"}'),
        DevelopmentLogLevel.error,
      );
      expect(
        classifyLogLine(
          '    at load (main.js:12)',
          continuation: DevelopmentLogLevel.error,
        ),
        DevelopmentLogLevel.error,
      );
      expect(classifyLogLine('error_count = 0'), DevelopmentLogLevel.other);
    },
  );

  test(
    'highlighting preserves code and distinguishes keys, literals and paths',
    () {
      const text =
          '[2026-09-30 12:02:03] ERROR {"count":42,"ready":true} Z:\\game\\main.js';
      final tokens = highlightLogLine(text);
      expect(tokens.map((token) => token.text).join(), text);
      expect(
        tokens.map((token) => token.kind),
        containsAll([
          LogTokenKind.timestamp,
          LogTokenKind.level,
          LogTokenKind.key,
          LogTokenKind.number,
          LogTokenKind.keyword,
          LogTokenKind.path,
        ]),
      );
    },
  );

  test(
    'streaming buffer keeps split UTF-8 and partial lines and bounds memory',
    () {
      final buffer = DevelopmentLogBuffer(maxLines: 3);
      final bytes = utf8.encode('[ERROR] 中文\n    at main.js:12\n[INFO] ready');
      final split = bytes.indexOf(0xe4) + 1;
      buffer.add(Uint8List.fromList(bytes.sublist(0, split)));
      buffer.add(Uint8List.fromList(bytes.sublist(split)));
      expect(buffer.entries.first.text, '[ERROR] 中文');
      expect(buffer.entries[1].level, DevelopmentLogLevel.error);
      expect(buffer.entries.last.text, '[INFO] ready');
      buffer.add(Uint8List.fromList(utf8.encode(' now\n[DEBUG] next\n')));
      expect(buffer.entries.map((entry) => entry.text), [
        '    at main.js:12',
        '[INFO] ready now',
        '[DEBUG] next',
      ]);
      expect(buffer.droppedLines, 1);
      buffer.close();
      final malformed = DevelopmentLogBuffer(maxCharacters: 50);
      malformed.add(Uint8List.fromList([255, 10]));
      expect(malformed.entries.single.text, contains('\ufffd'));
      malformed.add(
        Uint8List.fromList(utf8.encode(List.filled(50, 'x').join('\n'))),
      );
      expect(
        malformed.entries
            .map((line) => line.text.length)
            .fold(0, (a, b) => a + b),
        lessThanOrEqualTo(50),
      );
      malformed.close();
    },
  );

  test(
    'controller appends, filters, switches files and resets truncated logs',
    () async {
      final store = MemoryLogs()
        ..put(
          'test-current.log',
          '[INFO] Ready\n[ERROR] Failed\n    at main.js:3\n',
        )
        ..put('game-old.log', '[WARN] Previous\n');
      final controller = DevelopmentLogController(store);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.selectedPath, endsWith('test-current.log'));
      expect(
        controller.filter('failed', DevelopmentLogLevel.error).single.text,
        '[ERROR] Failed',
      );
      expect(controller.filter('', DevelopmentLogLevel.error).length, 2);
      store.append('test-current.log', '[INFO] More\n');
      await controller.refresh();
      expect(controller.entries.length, 4);
      await controller.select('/test/development/logs/game-old.log');
      expect(controller.entries.single.text, '[WARN] Previous');
      store.put('game-old.log', 'x\n');
      await controller.refresh();
      expect(controller.entries.single.text, 'x');
    },
  );

  test(
    'switching during an outstanding read cannot mix different logs',
    () async {
      final store = _DelayedLogs();
      final controller = DevelopmentLogController(store);
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = controller.select('/test/development/logs/second.log');
      store.first.complete(
        DevelopmentLogChunk(
          bytes: Uint8List.fromList(utf8.encode('old\n')),
          nextOffset: 4,
        ),
      );
      await Future.wait([first, second]);
      expect(controller.entries.single.text, 'new');
      controller.dispose();
    },
  );

  test(
    'native reader tails large files, appends and exports complete original',
    () async {
      final root = await Directory.systemTemp.createTemp('mcdev-log-test-');
      addTearDown(() => root.delete(recursive: true));
      final logs = await Directory(p.join(root.path, 'logs')).create();
      final file = File(p.join(logs.path, 'test-current.log'));
      const full = '[INFO] 中文一\n[ERROR] 中文二\n[INFO] 中文三\n';
      await file.writeAsString(full);
      final store = NativeDevelopmentLogs(logs.path, chunkBytes: 35);
      final chunk = await store.read(file.path);
      expect(chunk.skippedBytes, greaterThan(0));
      expect(utf8.decode(chunk.bytes), contains('中文三'));
      await file.writeAsString('[WARN] 追加\n', mode: FileMode.append);
      final appended = await store.read(file.path, offset: chunk.nextOffset);
      expect(utf8.decode(appended.bytes), '[WARN] 追加\n');
      final export = p.join(root.path, 'original.log');
      await store.exportOriginal(file.path, export);
      expect(await File(export).readAsString(), '$full[WARN] 追加\n');
      final filtered = p.join(root.path, 'filtered.txt');
      await store.exportText(file.path, filtered, '[ERROR] 中文二');
      expect(await File(filtered).readAsString(), '[ERROR] 中文二');
      await expectLater(
        store.exportOriginal(file.path, file.path),
        throwsA(isA<Exception>()),
      );
      await file.writeAsString('new\n');
      expect(
        (await store.read(file.path, offset: appended.nextOffset)).reset,
        true,
      );
    },
  );

  test('native log discovery excludes links and unrelated files', () async {
    final root = await Directory.systemTemp.createTemp('mcdev-log-list-');
    addTearDown(() => root.delete(recursive: true));
    final logs = await Directory(p.join(root.path, 'logs')).create();
    final outside = await File(
      p.join(root.path, 'outside.log'),
    ).writeAsString('outside');
    await Link(p.join(logs.path, 'linked.log')).create(outside.path);
    await File(p.join(logs.path, 'credentials.json')).writeAsString('{}');
    await File(p.join(logs.path, 'test-ok.log')).writeAsString('ok');
    final store = NativeDevelopmentLogs(logs.path);
    expect((await store.list()).map((file) => file.name), ['test-ok.log']);
    await expectLater(store.read(outside.path), throwsA(isA<Exception>()));
    await expectLater(
      store.read(p.join(logs.path, 'linked.log')),
      throwsA(isA<Exception>()),
    );
  });

  for (final dark in [true, false]) {
    testWidgets(
      'log dialog filters, highlights, copies and exports ${dark ? 'dark' : 'light'}',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final store = MemoryLogs()
          ..put(
            'test-current.log',
            '[INFO] ready\n[ERROR] Failed {"code":42}\n[WARN] warning\n',
          );
        await openLogs(
          tester,
          store,
          dark: dark,
          savePath: (_) async => '/export/chosen.log',
        );
        await tester.tap(find.byKey(const ValueKey('log-level')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('错误'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(OreTextField), 'failed');
        await tester.pumpAndSettle();
        expect(find.text('1 / 3 行 · 实时更新'), findsOneWidget);
        final line = tester.widget<Text>(
          find.byKey(const ValueKey('log-line-2')),
        );
        final spans = (line.textSpan as TextSpan).children!.cast<TextSpan>();
        expect(
          spans.map((span) => span.style!.color).toSet().length,
          greaterThan(2),
        );
        await tester.tap(find.text('复制筛选结果'));
        await tester.pumpAndSettle();
        expect(copied, '[ERROR] Failed {"code":42}');
        await tester.tap(find.text('导出筛选结果'));
        await tester.pumpAndSettle();
        expect(store.exportedText, copied);
        expect(store.exportedSource, endsWith('test-current.log'));
        await tester.tap(find.text('导出原始日志'));
        await tester.pumpAndSettle();
        expect(store.original, true);
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is OreIconButton && widget.tooltip == '关闭日志',
          ),
        );
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('auto scroll can pause while receiving new lines and resume', (
    tester,
  ) async {
    final store = MemoryLogs()
      ..put(
        'test-current.log',
        '${List.generate(100, (i) => '[INFO] line $i').join('\n')}\n',
      );
    await openLogs(tester, store);
    final list = find.byKey(const ValueKey('log-entries'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.extentAfter, lessThan(2));
    await tester.drag(list, const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OreCheckbox>(find.byKey(const ValueKey('log-auto-scroll')))
          .value,
      false,
    );
    final position = scrollable.position.pixels;
    store.append('test-current.log', '[ERROR] Newly appended\n');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('101 / 101 行 · 实时更新'), findsOneWidget);
    expect(scrollable.position.pixels, closeTo(position, 1));
    await tester.tap(find.byKey(const ValueKey('log-auto-scroll')));
    await tester.pumpAndSettle();
    expect(scrollable.position.extentAfter, lessThan(2));
    expect(
      tester
          .widget<OreCheckbox>(find.byKey(const ValueKey('log-auto-scroll')))
          .value,
      true,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'compact log dialog fits, switches history and reports export failure',
    (tester) async {
      final store = MemoryLogs()
        ..put('test-current.log', '[INFO] first\n')
        ..put('game-old.log', '[ERROR] old\n');
      await openLogs(
        tester,
        store,
        size: const Size(390, 844),
        savePath: (_) async => '/export/chosen.log',
      );
      await tester.tap(find.byKey(const ValueKey('log-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('游戏 · game-old.log'));
      await tester.pumpAndSettle();
      expect(find.text('[ERROR] old', findRichText: true), findsOneWidget);
      store.failExport = true;
      await tester.tap(find.text('导出原始日志'));
      await tester.pumpAndSettle();
      expect(find.textContaining('导出失败：'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'cancelling a save does not export and re-enables export actions',
    (tester) async {
      final store = MemoryLogs()..put('test-current.log', '[INFO] ready\n');
      await openLogs(tester, store, savePath: (_) async => null);
      await tester.tap(find.text('导出原始日志'));
      await tester.pumpAndSettle();
      expect(store.exportedSource, isNull);
      expect(
        tester
            .widget<OreButton>(find.widgetWithText(OreButton, '导出原始日志'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('empty logs are readable before the first launch', (
    tester,
  ) async {
    await openLogs(tester, MemoryLogs(), size: const Size(800, 630));
    expect(find.text('暂无游戏日志。启动测试后会在这里显示。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _DelayedLogs extends MemoryLogs {
  final first = Completer<DevelopmentLogChunk>();
  _DelayedLogs() {
    put('first.log', 'old\n');
    put('second.log', 'new\n');
  }
  @override
  Future<DevelopmentLogChunk> read(String path, {int? offset}) =>
      path.endsWith('first.log')
      ? first.future
      : super.read(path, offset: offset);
}
