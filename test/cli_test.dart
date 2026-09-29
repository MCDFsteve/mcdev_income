import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:mcdev_income/cli/cli.dart';
import 'package:mcdev_income/cli/common.dart';
import 'package:mcdev_income/cli/media.dart';
import 'package:mcdev_income/cli/resource_upload.dart';
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'resource_workflow_test.dart' as fixtures;

class Backend {
  final requests = <http.Request>[];
  final uploaded = <({String type, Uint8List bytes})>[];
  Map<String, dynamic> resource = fixtures.testResource();
  Map<String, dynamic> permissions = {};
  Map<String, dynamic>? payload;
  String lastType = '';
  int saves = 0, reviews = 0;
  bool failReview = false, unknownSave = false, queue = false;
  Future<void> Function()? onSave;
  McDevApi api([String cookie = 'test', String category = 'pe']) => McDevApi(
    cookie: cookie,
    category: category,
    client: MockClient((r) async {
      requests.add(r);
      if (r.url.path == '/items/mc_consts/') {
        return fixtures.ok(fixtures.testOptions);
      }
      if (r.url.path.startsWith('/setting/')) {
        return fixtures.ok({'setting': {}});
      }
      if (r.url.path.startsWith('/users/')) return fixtures.ok(permissions);
      if (r.url.path == '/filepicker/file_token') {
        lastType = r.url.queryParameters['file_type']!;
        return fixtures.ok({'token': 'upload-scoped'});
      }
      if (r.url.host == 'fp.ps.netease.com') {
        final body = latin1.decode(r.bodyBytes);
        final start = body.indexOf('\r\n\r\n', body.indexOf('filename="')) + 4;
        final end = body.lastIndexOf('\r\n--');
        uploaded.add((type: lastType, bytes: r.bodyBytes.sublist(start, end)));
        expect(
          r.headers.keys.map((e) => e.toLowerCase()),
          isNot(contains('cookie')),
        );
        return http.Response(
          jsonEncode({
            'url': 'https://files.test/${uploaded.length}',
            'fsize': end - start,
          }),
          200,
          headers: {'x-ntes-signature': 'signature-${uploaded.length}'},
        );
      }
      if (r.url.path.endsWith('/upload') || r.url.path.endsWith('/update')) {
        saves++;
        payload = jsonDecode(r.body);
        await onSave?.call();
        if (unknownSave) throw http.ClientException('disconnected');
        if (queue && payload!['is_check_apply'] != true) {
          return fixtures.ok({'need_check_apply': true, 'queue_length': 3});
        }
        return fixtures.ok({'item_id': '123'});
      }
      if (r.url.path.endsWith('/apply_review')) {
        reviews++;
        if (failReview) {
          return http.Response('{"status":"error","msg":"模拟提审失败"}', 200);
        }
        return fixtures.ok({});
      }
      if (r.url.path.endsWith('/pe/') || r.url.path.endsWith('/comp/')) {
        return fixtures.ok({
          'count': 1,
          'item': [resource],
        });
      }
      if (r.method == 'GET') return fixtures.ok(resource);
      return fixtures.ok({});
    }),
  );
  ResourceUpload uploader(String home) => ResourceUpload(
    api: api(),
    home: home,
    owner: 'test',
    category: 'pe',
    options: ResourceOptions(fixtures.testOptions),
    prices: ResourcePriceSettings({}),
  );
}

void main() {
  late Directory temp;
  late Backend backend;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcdev-cli-test-');
    backend = Backend();
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<({int code, Map<String, dynamic> json})> run(
    List<String> args, {
    bool auth = true,
    McDevApi Function(String, String)? factory,
  }) async {
    final lines = <String>[];
    final code = await McdevCli(
      output: lines.add,
      diagnostic: (_) {},
      environment: {if (auth) 'MCDEV_COOKIE': 'test-cookie'},
      apiFactory: factory ?? backend.api,
    ).run(['--home', temp.path, ...args]);
    expect(
      lines,
      hasLength(1),
      reason: 'stdout must contain exactly one JSON document',
    );
    return (code: code, json: jsonDecode(lines.single) as Map<String, dynamic>);
  }

  Future<File> picture([String name = 'image #1 %.png']) async {
    final raster = image.Image(width: 120, height: 60);
    for (var y = 0; y < 60; y++) {
      for (var x = 0; x < 120; x++) {
        raster.setPixelRgba(
          x,
          y,
          x < 30 ? 255 : 0,
          x >= 30 && x < 90 ? 255 : 0,
          x >= 90 ? 255 : 0,
          255,
        );
      }
    }
    return File('${temp.path}/$name').writeAsBytes(image.encodePng(raster));
  }

  Future<Map<String, dynamic>> manifest() async {
    final pic = await picture();
    await File('${temp.path}/mod.zip').writeAsBytes([0x50, 0x4b, 3, 4, 0]);
    return {
      'base_dir': temp.path,
      'fields': {
        'item_name': '命令测试',
        'pri_type': 2,
        'sub_type': 6,
        'info': '<p>说明</p>',
        'is_original': true,
      },
      'packages': ['mod.zip'],
      'images': {'3': pic.path, '5': pic.path},
    };
  }

  test(
    'JSON command discovery, aliases, invalid args and auth exit codes',
    () async {
      final schema = await run(['schema'], auth: false);
      expect(schema.code, 0);
      expect(schema.json['data']['aliases']['upload'], 'resource create');
      expect(schema.json['data']['commands'], hasLength(greaterThan(30)));
      expect((await run(['list', '--limit', '0'])).code, 2);
      expect((await run(['unknown'])).code, 2);
      expect((await run(['show'])).code, 2);
      expect((await run(['list', '--unknown'])).code, 2);
      expect((await run(['list'], auth: false)).code, 3);
      final help = await run(['upload', '--help', '--json']);
      expect(help.json['data']['options']['file']['type'], 'array');
    },
  );
  test(
    'center crop selects center pixels, EXIF output size; skin package bytes unchanged',
    () async {
      final file = await picture();
      final prepared = await prepareMedia(
        file.path,
        type: 'image',
        width: 40,
        height: 40,
      );
      final decoded = image.decodePng(prepared.bytes!)!;
      expect((decoded.width, decoded.height), (40, 40));
      expect(decoded.getPixel(20, 20).g, 255);
      expect(decoded.getPixel(0, 20).r, 0);
      final skin = await prepareMedia(file.path, type: 'png');
      expect(skin.bytes, isNull);
      expect(
        await skin.openRead().expand((e) => e).toList(),
        await file.readAsBytes(),
      );
      final cropped = await run([
        'media',
        'crop',
        file.path,
        '--width',
        '40',
        '--height',
        '40',
        '--out',
        '${temp.path}/out.png',
      ], auth: false);
      expect(cropped.code, 0);
      expect(await File('${temp.path}/out.png').exists(), true);
    },
  );
  test(
    'manifest uploads all assets, preserves signatures, crops channels and submits once',
    () async {
      final m = await manifest();
      final cover = (m['images'] as Map)['3'];
      await File('${temp.path}/video.mp4').writeAsBytes([1, 2, 3, 4]);
      m['video'] = {'path': 'video.mp4', 'cover': cover};
      m['description_images'] = [cover];
      final path = '${temp.path}/work.json';
      await writeJsonFile(path, m);
      final result = await run(['upload', path, '--submit']);
      expect(result.code, 0, reason: result.json.toString());
      expect(result.json['data']['submitted'], true);
      expect(backend.saves, 1);
      expect(backend.reviews, 1);
      expect(backend.uploaded.map((e) => e.type), [
        'zip_package',
        'image',
        'image',
        'image',
        'video',
        'image',
      ]);
      final coverImage = image.decodePng(backend.uploaded[1].bytes)!;
      expect((coverImage.width, coverImage.height), (992, 558));
      final videoCover = image.decodePng(backend.uploaded.last.bytes)!;
      expect((videoCover.width, videoCover.height), (992, 558));
      expect(backend.payload!['res'][0]['res_url']['sign'], 'signature-1');
      expect(
        backend.payload!['channel'][0]['channel_url']['sign'],
        'signature-2',
      );
      expect(backend.payload!['info'], contains('data-fp-sign="signature-4"'));
      expect(backend.payload!['video_info_list'][0]['size'], 4);
    },
  );
  test(
    'preflight rejects missing late file and invalid notes before any remote write',
    () async {
      final m = await manifest();
      m['video'] = {'path': 'missing.mp4', 'cover': m['images']['3']};
      await expectLater(
        backend.uploader(temp.path).execute(m),
        throwsA(
          isA<CliFailure>().having((e) => e.code, 'code', 'file_not_found'),
        ),
      );
      expect(backend.uploaded, isEmpty);
      expect(backend.saves, 0);
      m.remove('video');
      m['notes'] = 'x' * 501;
      await expectLater(
        backend.uploader(temp.path).execute(m),
        throwsA(
          isA<CliFailure>().having((e) => e.code, 'code', 'invalid_notes'),
        ),
      );
      expect(backend.requests, isEmpty);
    },
  );
  test(
    'dry-run with saved configuration is offline and preserves original files',
    () async {
      final m = await manifest();
      await writeJsonFile('${temp.path}/work.json', m);
      await writeJsonFile('${temp.path}/options.json', {
        'ok': true,
        'data': {
          'options': fixtures.testOptions,
          'price_settings': {},
          'permissions': {},
        },
      });
      final result = await run([
        'upload',
        '${temp.path}/work.json',
        '--dry-run',
        '--options',
        '${temp.path}/options.json',
      ], auth: false);
      expect(result.code, 0, reason: result.json.toString());
      expect(result.json['data']['uploads'], hasLength(3));
      expect(backend.requests, isEmpty);
      expect(await Directory('${temp.path}/jobs').exists(), false);
    },
  );
  test(
    'partial edit replaces package without sending the previous res_id',
    () async {
      backend.resource['future_field'] = {'retain': 42};
      (backend.resource['res'] as List).first['cdn_info'] = {'res_size': 30};
      (backend.resource['res'] as List).first['cdn_url'] = 'old-cdn-url';
      await File('${temp.path}/new.zip').writeAsBytes([3, 2, 1]);
      final result = await backend.uploader(temp.path).execute({
        'fields': {'item_name': '更新后'},
        'packages': [
          {'path': '${temp.path}/new.zip', 'replace': 0},
        ],
      }, itemId: '123');
      expect(result['item_id'], '123');
      expect(backend.payload!['future_field'], {'retain': 42});
      expect(backend.payload!['res'][0].containsKey('res_id'), false);
      expect(backend.payload!['res'][0]['res_info'], {'res_size': 25});
      expect(backend.payload!['res'][0]['cdn_info'], {'res_size': 30});
      expect(backend.payload!['res'][0]['cdn_url'], 'old-cdn-url');
      expect(backend.payload!['res'][0]['res_url']['sign'], 'signature-1');
      expect(backend.payload!.containsKey('status'), false);
    },
  );
  test(
    'review failure resumes saved resource without duplicate upload or create',
    () async {
      backend.failReview = true;
      CliFailure? failure;
      try {
        await backend
            .uploader(temp.path)
            .execute(await manifest(), submit: true);
      } on CliFailure catch (e) {
        failure = e;
      }
      expect(failure, isNotNull);
      final details = failure!.details as Map;
      expect(details['item_id'], '123');
      expect(details['phase'], 'reviewing');
      final count = backend.uploaded.length;
      backend.failReview = false;
      final result = await backend
          .uploader(temp.path)
          .execute({}, resume: details['job']);
      expect(result['submitted'], true);
      expect(backend.saves, 1);
      expect(backend.uploaded.length, count);
      expect(backend.reviews, 2);
      await backend.uploader(temp.path).execute({}, resume: details['job']);
      expect(backend.reviews, 2);
    },
  );
  test(
    'lost save response refuses retry until operator reconciles outcome',
    () async {
      backend.unknownSave = true;
      CliFailure? failure;
      try {
        await backend.uploader(temp.path).execute(await manifest());
      } on CliFailure catch (e) {
        failure = e;
      }
      expect(failure!.exitCode, 6);
      final id = (failure.details as Map)['job'];
      await expectLater(
        backend.uploader(temp.path).execute({}, resume: id),
        throwsA(
          isA<CliFailure>().having((e) => e.code, 'code', 'outcome_unknown'),
        ),
      );
      expect(backend.saves, 1);
    },
  );
  test(
    'queue pause persists uploads and resumes only with explicit queue flag',
    () async {
      backend.queue = true;
      CliFailure? failure;
      try {
        await backend.uploader(temp.path).execute(await manifest());
      } on CliFailure catch (e) {
        failure = e;
      }
      expect(failure!.exitCode, 5);
      final id = (failure.details as Map)['job'];
      final count = backend.uploaded.length;
      await expectLater(
        backend.uploader(temp.path).execute({}, resume: id),
        throwsA(isA<CliFailure>().having((e) => e.exitCode, 'exit', 5)),
      );
      expect(backend.saves, 1);
      final result = await backend
          .uploader(temp.path)
          .execute({}, resume: id, confirmQueue: true);
      expect(result['phase'], 'complete');
      expect(backend.uploaded.length, count);
      expect(backend.saves, 2);
    },
  );
  test('job lock excludes simultaneous resume during a save', () async {
    final started = Completer<void>(), finish = Completer<void>();
    backend.onSave = () async {
      started.complete();
      await finish.future;
    };
    final pending = backend.uploader(temp.path).execute(await manifest());
    await started.future;
    final file = (await Directory(
      '${temp.path}/jobs',
    ).list().where((e) => e.path.endsWith('.json')).toList()).single;
    final job = await readObject(file.path);
    await expectLater(
      backend.uploader(temp.path).execute({}, resume: job['id']),
      throwsA(isA<FileSystemException>()),
    );
    finish.complete();
    await pending;
    expect(backend.saves, 1);
  });
  test(
    'state writes merge concurrent stores; login clears atomically; migration does not restore logout',
    () async {
      final a = await FilePreferences.open(temp.path),
          b = await FilePreferences.open(temp.path);
      await Future.wait([
        a.setString('a', 'first'),
        b.setString('b', 'second'),
      ]);
      final current = await FilePreferences.open(temp.path);
      expect(current.getString('a'), 'first');
      expect(current.getString('b'), 'second');
      await current.migrateGui({
        'login_email_v1': 'sample@example.test',
        'login_password_v1': 'secret',
        'login_cookie_cache_v1': '{}',
        'theme_mode': 'dark',
      });
      CoreRuntime.preferences = () => FilePreferences.open(temp.path);
      await LoginService.clearLogin();
      final loggedOut = await FilePreferences.open(temp.path);
      await loggedOut.migrateGui({'login_password_v1': 'secret'});
      expect(loggedOut.getString('login_password_v1'), isNull);
      expect(loggedOut.getString('theme_mode'), 'dark');
      if (!Platform.isWindows) {
        expect(
          (await File('${temp.path}/state.json').stat()).mode & 0x1ff,
          0x180,
        );
      }
    },
  );
  test(
    'preset, theme and GUI-compatible draft round trips do not use HTTP',
    () async {
      await writeJsonFile('${temp.path}/preset.json', {
        'id': 'p',
        'name': '合作',
        'scope': 'single',
        'modIds': ['123'],
        'internalRatios': {'123': 0.5},
      });
      expect(
        (await run([
          'preset',
          'put',
          '${temp.path}/preset.json',
        ], auth: false)).code,
        0,
      );
      expect(
        (await run([
          'preset',
          'rename',
          'p',
          '改名',
        ], auth: false)).json['data']['name'],
        '改名',
      );
      expect(
        (await run([
          'settings',
          'set',
          'theme',
          'light',
        ], auth: false)).json['data']['theme'],
        'light',
      );
      final state = await FilePreferences.open(temp.path);
      await state.apply({
        'login_email_v1': 'sample@example.test',
        'login_session_kind_v1': 'domestic',
        'login_cookie_cache_v1': '{"session":"test"}',
        'login_oversea_expires_at_v1': DateTime.now()
            .add(const Duration(days: 2))
            .millisecondsSinceEpoch,
      });
      await writeJsonFile('${temp.path}/draft.json', {'item_name': '本机草稿'});
      final saved = await run([
        'draft',
        'put',
        '${temp.path}/draft.json',
      ], auth: false);
      expect(saved.code, 0, reason: saved.json.toString());
      final actual = await FilePreferences.open(temp.path);
      expect(
        jsonDecode(
          actual.getString('resource_draft_v1:sample@example.test:pe:new')!,
        )['item_name'],
        '本机草稿',
      );
      expect(
        (await run(['draft', 'get'], auth: false)).json['data']['item_name'],
        '本机草稿',
      );
      expect(backend.requests, isEmpty);
    },
  );
  test('status omits secrets; logout does not echo credentials', () async {
    final result = await run(['auth', 'status']);
    expect(result.json['data']['logged_in'], true);
    expect(jsonEncode(result.json), isNot(contains('test-cookie')));
    backend.permissions = {
      'token': 'private',
      'nested': {'password': 'private'},
      'nickname': '开发者',
    };
    final profile = await run(['profile']);
    expect(jsonEncode(profile.json), isNot(contains('private')));
  });
  test(
    'first GUI migration cannot mix an old password into a CLI account or undo logout',
    () async {
      final state = await FilePreferences.open(temp.path);
      await state.apply({
        'login_email_v1': 'new@example.test',
        'login_cookie_cache_v1': '{"session":"new"}',
      });
      await state.migrateGui({
        'login_email_v1': 'old@example.test',
        'login_password_v1': 'old-password',
        'theme_mode': 'dark',
      });
      expect(state.getString('login_email_v1'), 'new@example.test');
      expect(state.getString('login_password_v1'), isNull);
      final cleanHome = '${temp.path}/logged-out';
      CoreRuntime.preferences = () => FilePreferences.open(cleanHome);
      await LoginService.clearLogin();
      final loggedOut = await FilePreferences.open(cleanHome);
      await loggedOut.migrateGui({
        'login_email_v1': 'old@example.test',
        'login_cookie_cache_v1': '{"session":"old"}',
      });
      expect(loggedOut.getString('login_cookie_cache_v1'), isNull);
    },
  );
  test(
    'stdin login, password opt-in and explicit refresh use the shared session',
    () async {
      final previous = LoginService.clientFactory;
      addTearDown(() => LoginService.clientFactory = previous);
      var attempts = 0;
      LoginService.clientFactory = () => MockClient((request) async {
        attempts++;
        expect(request.url.path, '/users/oversea/login_check');
        expect(jsonDecode(request.body)['password'], 'stdin-password');
        return fixtures.ok({'token': 'session-token'});
      });
      Future<int> login(bool remember) async {
        final output = <String>[];
        final exit =
            await McdevCli(
              output: output.add,
              environment: {},
              readPassword: () async => 'stdin-password\n',
            ).run([
              '--home',
              temp.path,
              'auth',
              'login',
              'sample@gmail.com',
              '--password-stdin',
              if (remember) '--remember',
            ]);
        expect(output.single, isNot(contains('stdin-password')));
        expect(output.single, isNot(contains('session-token')));
        return exit;
      }

      expect(await login(false), 0);
      expect(
        (await FilePreferences.open(temp.path)).getString('login_password_v1'),
        isNull,
      );
      expect((await run(['auth', 'refresh'], auth: false)).code, 3);
      expect(await login(true), 0);
      expect((await run(['auth', 'refresh'], auth: false)).code, 0);
      expect(attempts, 3);
      expect((await run(['auth', 'logout'], auth: false)).code, 0);
      expect(
        (await run(['auth', 'status'], auth: false)).json['data']['logged_in'],
        false,
      );
    },
  );
  test(
    'income presets apply per-Mod splits and downloads; CSV quotes names',
    () async {
      await writeJsonFile('${temp.path}/preset.json', {
        'id': 'share',
        'name': '分成',
        'scope': 'single',
        'modIds': ['123'],
        'internalRatios': {'123': 0.5},
        'defaultNeteaseRatio': 0.3,
        'taxRate': 0.16,
      });
      await run(['preset', 'put', '${temp.path}/preset.json']);
      McDevApi factory(String cookie, String category) => McDevApi(
        cookie: cookie,
        category: category,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/pe/')) {
            return fixtures.ok({
              'count': 1,
              'item': [
                {
                  'item_id': '123',
                  'item_name': '带逗号,和"引号"',
                  'price': 100,
                  'price_type': 'diamond',
                },
              ],
            });
          }
          if (r.url.path.contains('day_detail')) {
            return fixtures.ok({
              'data': [
                {'iid': '123', 'dateid': '20260831', 'download_num': 100},
                {'iid': '123', 'dateid': '20260901', 'download_num': 108},
                {'iid': '123', 'dateid': '20260902', 'download_num': 114},
              ],
            });
          }
          if (r.url.path.endsWith('/incomes/')) {
            return fixtures.ok({
              'total_diamonds': 10000,
              'total_points': 5,
              'count': 1,
              'orders': [
                {'refund_status': '已退款'},
              ],
            });
          }
          throw StateError('Unexpected endpoint ${r.url.path}');
        }),
      );
      final result = await run([
        'income',
        '--from',
        '2026-09-01',
        '--to',
        '2026-09-02',
        '--preset',
        'share',
        '--csv',
        '${temp.path}/income.csv',
      ], factory: factory);
      expect(result.code, 0, reason: result.json.toString());
      final row = result.json['data']['items'][0];
      expect(row['downloads'], 14);
      expect(row['refunded'], 1);
      expect(row['income_yuan'], closeTo(12.6, 0.00001));
      expect(
        await File('${temp.path}/income.csv').readAsString(),
        contains('"带逗号,和""引号"""'),
      );
    },
  );
  test(
    'synced PC work routes edits to PE and unknown action responses report uncertain writes',
    () async {
      backend.resource['sync_pc_flag'] = true;
      backend.resource['relate_item_id'] = '456';
      final result = await run(['edit', '123', '-c', 'pc', '--name', '修改']);
      expect(result.code, 2);
      expect(result.json['error']['code'], 'synced_resource');
      expect(backend.saves, 0);
      backend.resource = fixtures.testResource(status: 'accept');
      final failed = await run(
        ['resource', 'action', '123', 'publish'],
        factory: (cookie, category) => McDevApi(
          cookie: cookie,
          category: category,
          client: MockClient((r) async {
            if (r.method == 'PUT') throw http.ClientException('disconnected');
            return fixtures.ok(
              r.url.path.startsWith('/users') ? {} : backend.resource,
            );
          }),
        ),
      );
      expect(failed.code, 6);
      expect(failed.json['error']['code'], 'outcome_unknown');
    },
  );
  test(
    'actions enforce status, delete confirmation and scheduling payload',
    () async {
      expect((await run(['resource', 'action', '123', 'delete'])).code, 2);
      expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(
        (await run(['resource', 'action', '123', 'delete', '--yes'])).code,
        0,
      );
      backend.resource = fixtures.testResource(status: 'accept');
      final schedule = await run([
        'resource',
        'action',
        '123',
        'schedule',
        '--at',
        '2099-01-01 10:00',
      ]);
      expect(schedule.code, 0);
      final mutation = backend.requests.last;
      expect(mutation.method, 'PUT');
      expect(
        jsonDecode(mutation.body)['appoint_online_time'],
        '2099-01-01 10:00:00',
      );
      expect((await run(['submit', '123'])).code, 2);
    },
  );
}
