import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../core.dart';
import '../storage/file_preferences.dart';
import 'commands.dart';
import 'common.dart';
import 'media.dart';
import 'resource_upload.dart';

part 'resource_commands.dart';
part 'local_commands.dart';
part 'income_commands.dart';

/// A standalone Dart command surface. It never initializes Flutter or a window.
class McdevCli {
  McdevCli({
    void Function(String)? output,
    void Function(String)? diagnostic,
    Map<String, String>? environment,
    Future<String> Function()? readPassword,
    this.apiFactory,
  }) : output = output ?? stdout.writeln,
       diagnostic = diagnostic ?? stderr.writeln,
       environment = environment ?? Platform.environment,
       readPassword =
           readPassword ?? (() => stdin.transform(utf8.decoder).join());
  final void Function(String) output, diagnostic;
  final Map<String, String> environment;
  final Future<String> Function() readPassword;
  final McDevApi Function(String cookie, String category)? apiFactory;
  final _apis = <McDevApi>[];
  late ArgResults args;
  late List<ArgResults> _chain;
  late FilePreferences store;
  late String home;
  bool pretty = false;
  bool verbose = false;

  bool has(String key) =>
      _chain.reversed.any((a) => a.options.contains(key) && a.wasParsed(key));
  dynamic option(String key) {
    for (final a in _chain.reversed) {
      if (a.options.contains(key) && a.wasParsed(key)) return a[key];
    }
    for (final a in _chain.reversed) {
      if (a.options.contains(key)) return a[key];
    }
    return null;
  }

  String? str(String key) => option(key) as String?;
  bool flag(String key) => option(key) == true;
  List<String> many(String key) => (option(key) as List?)?.cast<String>() ?? [];
  String get category => switch (str('category')) {
    'pc' || 'java' => 'comp',
    final c? => c,
    _ => 'pe',
  };
  String get modCategory {
    if (['multi', 'pe_multi'].contains(category)) {
      throw CliFailure('invalid_category', '收益和 Mod 查询仅支持 pe/java');
    }
    return category == 'comp' ? 'java' : 'pe';
  }

  void progress(String message) {
    if (verbose) diagnostic(message);
  }

  void emit(Object? value) => output(
    (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder()).convert(
      value,
    ),
  );

  Future<int> run(List<String> arguments) async {
    try {
      final parser = commandParser();
      final root = parser.parse(arguments);
      _chain = [root];
      var leaf = root;
      var selected = parser;
      final names = <String>[];
      while (leaf.command != null) {
        leaf = leaf.command!;
        _chain.add(leaf);
        names.add(leaf.name!);
        selected = selected.commands[leaf.name]!;
      }
      args = leaf;
      pretty = flag('pretty');
      verbose = flag('verbose');
      final path = commandAliases[names.join(' ')] ?? names.join(' ');
      final spec = cliCommands.where((s) => s.path == path).firstOrNull;
      if (flag('help') || (spec == null && leaf.rest.isEmpty)) {
        final commands = cliCommands.where(
          (s) => path.isEmpty || s.path.startsWith('$path '),
        );
        if (flag('json')) {
          emit({
            'ok': true,
            'data': spec == null ? commands.map(_spec).toList() : _spec(spec),
          });
        } else {
          output(
            '我的世界开发者管理 · mcdev\n用法：mcdev ${spec == null
                ? path.isEmpty
                      ? '<command>'
                      : '$path <command>'
                : '${spec.path} ${spec.arguments}'} [options]\n',
          );
          if (spec != null) output(spec.description);
          for (final s in commands) {
            output('  ${s.path.padRight(24)} ${s.description}');
          }
          output('\n${selected.usage}');
          if (path.isEmpty) {
            output(
              '\n快捷命令：list、show、upload、edit、submit。默认输出 JSON；mcdev schema 可供 Agent 读取。',
            );
          }
        }
        return 0;
      }
      if (spec == null) {
        throw CliFailure('unknown_command', '未知命令；运行 mcdev --help');
      }
      if (args.rest.length < spec.minArgs || args.rest.length > spec.maxArgs) {
        throw CliFailure('usage', '用法：mcdev ${spec.path} ${spec.arguments}');
      }
      if (path == 'schema') {
        emit({'ok': true, 'data': _schema()});
        return 0;
      }
      home = str('home') ?? environment['MCDEV_HOME'] ?? mcdevHome();
      store = await FilePreferences.open(home);
      home = store.directory;
      CoreRuntime.preferences = () => FilePreferences.open(home);
      CoreRuntime.system = Platform.isMacOS
          ? 'Mac'
          : Platform.isWindows
          ? 'Windows'
          : 'Linux';
      // Login internals can include account identifiers; never forward their logs.
      CoreRuntime.log = (_) {};
      final result = await _dispatch(path);
      emit({'ok': true, 'data': result});
      return 0;
    } catch (error) {
      final failure = switch (error) {
        CliFailure e => e,
        ArgParserException e => CliFailure('usage', e.message),
        FormatException e => CliFailure('invalid_input', e.message),
        ArgumentError e => CliFailure(
          'invalid_argument',
          e.message?.toString() ?? '无效参数',
        ),
        FileSystemException e => CliFailure(
          'file_error',
          e.message,
          exitCode: 1,
          details: {'path': e.path},
        ),
        McDevException e => CliFailure(
          e.outcomeUnknown
              ? 'outcome_unknown'
              : e.statusCode == 401
              ? 'auth_expired'
              : e.statusCode == 403
              ? 'permission_denied'
              : 'platform_error',
          e.message,
          exitCode: e.outcomeUnknown
              ? 6
              : [401, 403].contains(e.statusCode)
              ? 3
              : 4,
        ),
        TimeoutException _ => CliFailure(
          'timeout',
          '请求超时，请检查平台状态；写操作请先核对结果再重试',
          exitCode: 4,
        ),
        http.ClientException _ || SocketException _ => CliFailure(
          'network_error',
          '网络请求失败，请检查连接',
          exitCode: 4,
        ),
        TypeError _ => CliFailure('invalid_input', '字段类型不正确，请参考 mcdev schema'),
        _ => CliFailure(
          'internal_error',
          '命令未完成：${error.runtimeType}',
          exitCode: 1,
        ),
      };
      emit({
        'ok': false,
        'error': {
          'code': failure.code,
          'message': failure.message,
          if (failure.details != null) 'details': failure.details,
        },
      });
      return failure.exitCode;
    } finally {
      for (final api in _apis) {
        api.close();
      }
      _apis.clear();
    }
  }

  Future<McDevApi> api({String? forCategory, bool allowOffline = false}) async {
    var cookie = environment['MCDEV_COOKIE'];
    if (allowOffline) cookie = '';
    if (!allowOffline && (cookie == null || cookie.isEmpty)) {
      final session = await LoginService.ensureFreshLogin();
      if (session != null && session.expiresAt.isBefore(DateTime.now())) {
        throw CliFailure(
          'auth_expired',
          '登录已过期，请运行 mcdev auth login',
          exitCode: 3,
        );
      }
      cookie = await LoginService.buildCookieHeader(refreshIfNeeded: false);
    }
    cookie ??= '';
    if (cookie.isEmpty && !allowOffline) {
      throw CliFailure(
        'auth_required',
        '请先运行 mcdev auth login <email> --password-stdin',
        exitCode: 3,
      );
    }
    final value =
        apiFactory?.call(cookie, forCategory ?? 'pe') ??
        McDevApi(cookie: cookie, category: forCategory ?? 'pe');
    _apis.add(value);
    return value;
  }

  Future<Object?> _dispatch(String path) async {
    if (path == 'rank') {
      final limit = integer(str('limit'), 'limit', min: 1, max: 100);
      final start = (integer(str('page'), 'page', min: 1) - 1) * limit;
      final page = await (await api()).fetchLeaderboard(
        type: str('type')!,
        kind: str('kind')!,
        start: start,
        span: limit,
      );
      return {
        'type': str('type'),
        'kind': str('kind'),
        'total': page.total,
        'items': page.items.map((e) => e.raw).toList(),
        'next_offset': start + page.items.length < page.total
            ? start + page.items.length
            : null,
      };
    }
    if (path.startsWith('mail ')) {
      final client = await api();
      if (path == 'mail count') {
        return {'unread': await client.fetchUnreadMailCount()};
      }
      if (path == 'mail show') {
        return (await client.fetchMailDetail(args.rest.single)).raw;
      }
      final limit = integer(str('limit'), 'limit', min: 1, max: 100);
      final start = (integer(str('page'), 'page', min: 1) - 1) * limit;
      final page = await client.fetchMail(
        start: start,
        span: limit,
        type: str('type') == 'all' ? '' : str('type')!,
        haveRead: flag('unread') ? false : null,
        query: str('query'),
      );
      return {
        'total': page.total,
        'unread': page.unread,
        'items': page.items.map((e) => e.raw).toList(),
        'next_offset': start + page.items.length < page.total
            ? start + page.items.length
            : null,
      };
    }
    if (path.startsWith('auth ')) return _auth(path.substring(5));
    if (path.startsWith('resource ')) return _resource(path.substring(9));
    if (path.startsWith('media ')) return _media(path.substring(6));
    if (path.startsWith('jobs ')) return _jobs(path.substring(5));
    if (path.startsWith('draft ')) return _draft(path.substring(6));
    if (path.startsWith('preset ')) return _preset(path.substring(7));
    if (path.startsWith('settings ')) {
      if (path == 'settings set') {
        if (args.rest[0] != 'theme' ||
            !['system', 'light', 'dark'].contains(args.rest[1])) {
          throw CliFailure(
            'invalid_setting',
            '用法：mcdev settings set theme system|light|dark',
          );
        }
        await store.setString('theme_mode', args.rest[1]);
      }
      return {'theme': store.getString('theme_mode') ?? 'system'};
    }
    if (path == 'income' || path.startsWith('mods ')) return _income(path);
    final client = await api();
    if (path == 'profile') {
      final profile = await client.fetchDeveloperProfile();
      return _redact({'author': profile.authorRaw, 'user': profile.userRaw});
    }
    if (path == 'overview') {
      final o = await client.fetchOverview();
      return {
        'this_month_diamond': o.thisMonthDiamond,
        'last_month_diamond': o.lastMonthDiamond,
        'yesterday_diamond': o.yesterdayDiamond,
        'days_14_average_diamond': o.days14AverageDiamond,
        'this_month_download': o.thisMonthDownload,
        'last_month_download': o.lastMonthDownload,
        'yesterday_download': o.yesterdayDownload,
        'days_14_average_download': o.days14AverageDownload,
        'day_diamond_diff': o.dayDiamondDiff,
        'day_download_diff': o.dayDownloadDiff,
        'month_diamond_diff': o.monthDiamondDiff,
        'month_download_diff': o.monthDownloadDiff,
      };
    }
    throw CliFailure('unknown_command', path);
  }

  Future<Object?> _auth(String action) async {
    if (action == 'logout') {
      await LoginService.clearLogin();
      return {'logged_in': false};
    }
    if (action == 'login' || action == 'refresh') {
      final old = action == 'refresh'
          ? await LoginService.readLoginSession()
          : null;
      final email = action == 'refresh' ? old?.email : args.rest.single;
      final password = action == 'refresh'
          ? old?.savedPassword
          : flag('password-stdin')
          ? (await readPassword()).replaceFirst(RegExp(r'[\r\n]+$'), '')
          : environment['MCDEV_PASSWORD'];
      if (email == null || password == null || password.isEmpty) {
        throw CliFailure(
          'credentials_required',
          action == 'refresh'
              ? '没有可刷新凭据，请重新登录'
              : '密码请通过 --password-stdin 或 MCDEV_PASSWORD 提供',
          exitCode: 3,
        );
      }
      try {
        await LoginService.loginWithEmail(
          email: email,
          password: password,
          rememberPassword: action == 'refresh' || flag('remember'),
        );
      } on McDevException catch (e) {
        throw CliFailure('login_failed', e.message, exitCode: 3);
      }
    }
    final session = await LoginService.readLoginSession();
    final env = environment['MCDEV_COOKIE']?.isNotEmpty == true;
    var valid =
        env || (session != null && session.expiresAt.isAfter(DateTime.now()));
    if (flag('check')) {
      await (await api()).fetchDeveloperProfile();
      valid = true;
    }
    return {
      'logged_in': valid,
      'source': env ? 'environment' : 'shared_state',
      if (!env && session != null) ...{
        'email': session.email,
        'expires_at': session.expiresAt.toIso8601String(),
        'can_refresh': session.canRefresh,
      },
      'home': home,
      'checked': flag('check'),
    };
  }

  Map<String, dynamic> _spec(CliCommand spec) {
    var parser = commandParser();
    for (final name in spec.path.split(' ')) {
      parser = parser.commands[name]!;
    }
    return {
      'command': spec.path,
      'description': spec.description,
      'arguments': spec.arguments,
      'options': {
        for (final e in parser.options.entries)
          e.key: {
            'help': e.value.help,
            'abbr': e.value.abbr,
            'type': e.value.isFlag
                ? 'boolean'
                : e.value.isMultiple
                ? 'array'
                : 'string',
            if (e.value.defaultsTo != null) 'default': e.value.defaultsTo,
            if (e.value.allowed != null) 'allowed': e.value.allowed,
          },
      },
    };
  }

  Object _schema() => {
    'version': 1,
    'commands': cliCommands.map(_spec).toList(),
    'aliases': commandAliases,
    'actions': actionAliases,
    'resource_statuses': resourceStatusLabels,
    'conflict_types': resourceConflictTypes.map((k, v) => MapEntry('$k', v)),
    'manifest': {
      'category': 'pe|comp',
      'fields': '平台可编辑字段对象；嵌套对象合并、数组整体替换',
      'packages': [
        'path.zip',
        {
          'path': 'replacement.zip',
          'replace': 0,
          'mc_version': ['1.20.1'],
          'java_version': '17',
        },
      ],
      'images': {'<channel id>': 'image.jpg'},
      'description_images': ['detail.png'],
      'video': {'path': 'video.mp4', 'cover': 'cover.jpg'},
      'proof': 'proof.png',
      'banner': 'banner.jpg',
      'sync': {
        'images': {'<PC channel id>': 'image.jpg'},
        'description_images': ['detail.png'],
      },
      'notes': '审核备注',
      'conflict_notify': '0|1|2',
      'conflict_types': [0],
    },
    'output': {
      'success': {'ok': true, 'data': 'result'},
      'failure': {
        'ok': false,
        'error': {
          'code': 'machine_code',
          'message': 'human message',
          'details': 'optional',
        },
      },
    },
    'exit_codes': {
      '0': '成功',
      '1': '本机或内部错误',
      '2': '参数/校验错误',
      '3': '需要登录',
      '4': '平台/网络错误',
      '5': '需要排队确认',
      '6': '远程写入结果不明，先核对再恢复',
    },
  };
}

Object? _redact(Object? value) {
  if (value is Map) {
    return {
      for (final e in value.entries)
        if (!RegExp(
          r'password|cookie|token|secret|authorization',
          caseSensitive: false,
        ).hasMatch(e.key.toString()))
          e.key.toString(): _redact(e.value),
    };
  }
  if (value is List) return value.map(_redact).toList();
  return value;
}
