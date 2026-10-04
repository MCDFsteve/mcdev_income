import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mcdev_income/cli/cli.dart';
import 'package:mcdev_income/core.dart';

import 'resource_workflow_test.dart' as fixtures;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('income-default-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<Map<String, dynamic>> run(List<String> args) async {
    final lines = <String>[];
    final code = await McdevCli(
      output: lines.add,
      diagnostic: (_) {},
      environment: {'MCDEV_COOKIE': 'fixture'},
      apiFactory: (cookie, category) => McDevApi(
        cookie: cookie,
        category: category,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/pe/')) {
            return fixtures.ok({
              'count': 1,
              'item': [
                {
                  'item_id': '123',
                  'item_name': '收益测试',
                  'price': 100,
                  'price_type': 'diamond',
                },
              ],
            });
          }
          if (request.url.path.contains('day_detail')) {
            return fixtures.ok({'data': <Object>[]});
          }
          if (request.url.path.endsWith('/incomes/')) {
            return fixtures.ok({
              'total_diamonds': 10000,
              'total_points': 0,
              'count': 1,
              'orders': [<String, dynamic>{}],
            });
          }
          throw StateError('Unexpected endpoint ${request.url.path}');
        }),
      ),
    ).run(['--home', directory.path, ...args]);
    expect(code, 0, reason: lines.join('\n'));
    return jsonDecode(lines.single)['data'] as Map<String, dynamic>;
  }

  test(
    'CLI income defaults to 0.39 and honors an explicit ratio override',
    () async {
      final defaults = await run([
        'income',
        '--from',
        '2026-09-01',
        '--to',
        '2026-09-02',
      ]);
      expect(defaults['items'][0]['netease_ratio'], 0.39);
      expect(defaults['items'][0]['income_yuan'], closeTo(32.76, 0.00001));
      final custom = await run([
        'income',
        '--from',
        '2026-09-01',
        '--to',
        '2026-09-02',
        '--netease',
        '0.5',
      ]);
      expect(custom['items'][0]['netease_ratio'], 0.5);
      expect(custom['items'][0]['income_yuan'], closeTo(42, 0.00001));
    },
  );

  test(
    'new CLI presets default to 0.39 and updating keeps saved ratios',
    () async {
      final source = File('${directory.path}/preset.json');
      await source.writeAsString(jsonEncode({'id': 'default', 'name': '新预设'}));
      expect(
        (await run(['preset', 'put', source.path]))['defaultNeteaseRatio'],
        0.39,
      );
      await source.writeAsString(
        jsonEncode({'id': 'custom', 'name': '自定义', 'defaultNeteaseRatio': 1.0}),
      );
      await run(['preset', 'put', source.path]);
      await source.writeAsString(jsonEncode({'id': 'custom', 'name': '保留比例'}));
      expect(
        (await run(['preset', 'put', source.path]))['defaultNeteaseRatio'],
        1.0,
      );
    },
  );
}
