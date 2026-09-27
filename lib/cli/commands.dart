import 'package:args/args.dart';
import '../core.dart' show leaderboardTypes, leaderboardKinds, mailboxTypes;

class CliCommand {
  CliCommand(
    this.path,
    this.description,
    this.arguments,
    this.minArgs,
    this.maxArgs, [
    this.configure,
  ]);
  final String path;
  final String description;
  final String arguments;
  final int minArgs;
  final int maxArgs;
  final void Function(ArgParser)? configure;
}

void categoryOptions(ArgParser p) => p.addOption(
  'category',
  abbr: 'c',
  defaultsTo: 'pe',
  allowed: ['pe', 'pc', 'comp', 'java', 'multi', 'pe_multi'],
  help: '作品类别，pc 等同 comp；Mod/收益使用 java',
);
void reviewOptions(ArgParser p) {
  p.addOption('notes', help: '审核备注，最多 500 字');
  p.addFlag('confirm-queue', negatable: false, help: '预先同意平台排队确认');
  p.addOption(
    'conflict',
    allowed: ['none', 'mine', 'all'],
    help: '冲突报告：不检测/本账号/全平台',
  );
  p.addMultiOption('conflict-types', help: '冲突类型编号，逗号分隔；0 表示全部');
}

void uploadOptions(ArgParser p) {
  categoryOptions(p);
  reviewOptions(p);
  p.addOption('id', help: '更新现有作品编号；省略则新建');
  p.addOption('resume', help: '恢复上传任务编号，不再重新创建已保存的作品');
  p.addOption('name', help: '作品名称');
  p.addOption('primary', help: '主类别编号');
  p.addOption('secondary', help: '次类别编号');
  p.addOption('info', help: '详情 HTML');
  p.addOption('intro', help: '详情 HTML 文件路径');
  p.addFlag('original', negatable: false, help: '确认作品为原创');
  p.addMultiOption('file', splitCommas: false, help: '资源包路径，可重复');
  p.addMultiOption('image', splitCommas: false, help: '渠道编号=图片路径，可重复；默认居中裁剪');
  p.addOption('video', help: 'MP4 视频路径');
  p.addOption('video-cover', help: '视频封面路径');
  p.addMultiOption(
    'set',
    splitCommas: false,
    help: '任意字段路径=JSON 值，可重复，如 mc_version=["1.20.1"]',
  );
  p.addFlag('submit', negatable: false, help: '保存后提交审核');
  p.addFlag('dry-run', negatable: false, help: '检查文件、裁剪和表单，仅返回计划，不上传或保存');
  p.addOption('options', help: '离线平台配置 JSON（来自 resource options），供校验使用');
}

final cliCommands = <CliCommand>[
  CliCommand('rank', '查看平台排行榜', '', 0, 0, (p) {
    p.addOption(
      'type',
      defaultsTo: 'pe_hot',
      allowed: leaderboardTypes.keys,
      allowedHelp: leaderboardTypes,
    );
    p.addOption(
      'kind',
      defaultsTo: 'mods',
      allowed: leaderboardKinds.keys,
      allowedHelp: leaderboardKinds,
    );
    p.addOption('page', defaultsTo: '1');
    p.addOption('limit', defaultsTo: '50');
  }),
  CliCommand('mail count', '查看未读邮件数量', '', 0, 0),
  CliCommand('mail list', '查询邮件，支持标题、类别、未读与分页', '', 0, 0, (p) {
    p.addOption(
      'type',
      defaultsTo: 'all',
      allowed: ['all', ...mailboxTypes.keys.where((s) => s.isNotEmpty)],
    );
    p.addOption('query', abbr: 'q');
    p.addFlag('unread', negatable: false);
    p.addOption('page', defaultsTo: '1');
    p.addOption('limit', defaultsTo: '30');
  }),
  CliCommand('mail show', '读取邮件正文（与网页一致，会将此邮件标记为已读）', '<id>', 1, 1),
  CliCommand('schema', '输出全部命令和上传清单结构，供 Agent 自发现', '', 0, 0),
  CliCommand(
    'auth login',
    '邮箱登录（密码从标准输入或 MCDEV_PASSWORD 读取）',
    '<email>',
    1,
    1,
    (p) {
      p.addFlag('password-stdin', negatable: false, help: '从标准输入读取密码');
      p.addFlag('remember', negatable: false, help: '保存密码用于自动刷新会话');
    },
  ),
  CliCommand(
    'auth status',
    '查看会话状态，不输出凭证',
    '',
    0,
    0,
    (p) => p.addFlag('check', negatable: false, help: '请求平台验证会话'),
  ),
  CliCommand('auth refresh', '使用已保存的凭据刷新会话', '', 0, 0),
  CliCommand('auth logout', '清除本地账号会话和保存密码', '', 0, 0),
  CliCommand('overview', '数据概览', '', 0, 0),
  CliCommand('profile', '开发者信息与账号权限', '', 0, 0),
  CliCommand('mods list', '获取 Mod 列表', '', 0, 0, (p) {
    categoryOptions(p);
    p.addFlag('priced', negatable: false, help: '仅付费 Mod');
    p.addFlag('published', negatable: false, help: '仅已发布 Mod');
    p.addOption('query', abbr: 'q', help: '本地按名称或编号筛选');
  }),
  CliCommand('mods sales', '查询下载总数或时间范围增量', '', 0, 0, (p) {
    categoryOptions(p);
    p.addMultiOption('id', help: 'Mod 编号，可重复或逗号分隔');
    p.addOption('from', help: '开始日期 YYYY-MM-DD');
    p.addOption('to', help: '结束日期 YYYY-MM-DD');
    p.addFlag('total', negatable: false, help: '返回累计总数，默认时间段增量');
  }),
  CliCommand('income', '查询收益、退款、下载与分成，可导出 CSV', '', 0, 0, (p) {
    categoryOptions(p);
    p.addOption('from', help: '开始日期 YYYY-MM-DD');
    p.addOption('to', help: '结束日期 YYYY-MM-DD');
    p.addMultiOption('id', help: 'Mod 编号；省略为全部');
    p.addOption('preset', help: '使用收益预设编号');
    p.addOption('internal', help: '默认内部分成比例');
    p.addOption('netease', help: '默认网易分成比例');
    p.addOption('tax', help: '税率，0 到 1');
    p.addOption('csv', help: 'CSV 输出文件路径');
    p.addOption(
      'sort',
      defaultsTo: 'diamonds',
      allowed: ['diamonds', 'downloads', 'release'],
      help: '排序字段',
    );
    p.addFlag('asc', negatable: false, help: '升序');
  }),
  CliCommand('resource list', '查询作品列表，支持分页、搜索和状态', '', 0, 0, (p) {
    categoryOptions(p);
    p.addOption('query', abbr: 'q', help: '作品名称或编号');
    p.addOption('status', help: '平台状态');
    p.addOption('page', defaultsTo: '1', help: '页码');
    p.addOption('limit', defaultsTo: '30', help: '每页条数');
    p.addFlag('all', negatable: false, help: '获取所有页');
  }),
  for (final name in ['get', 'feedback', 'actions'])
    CliCommand(
      'resource $name',
      {'get': '作品详情', 'feedback': '审核与下架反馈', 'actions': '当前状态可用操作'}[name]!,
      '<id>',
      1,
      1,
      categoryOptions,
    ),
  CliCommand(
    'resource options',
    '上传类别、图片尺寸、版本、定价和冲突配置',
    '',
    0,
    0,
    categoryOptions,
  ),
  CliCommand(
    'resource requirements',
    '搜索前置作品',
    '<query>',
    1,
    1,
    categoryOptions,
  ),
  CliCommand('resource dlc', '搜索 DLC 主副包候选作品', '<query>', 1, 1),
  CliCommand(
    'resource create',
    '上传并新建作品',
    '[manifest.json]',
    0,
    1,
    uploadOptions,
  ),
  CliCommand(
    'resource update',
    '局部更新作品，保留其余字段',
    '<id> [manifest.json]',
    1,
    2,
    uploadOptions,
  ),
  CliCommand('resource submit', '提交作品审核', '<id>', 1, 1, (p) {
    categoryOptions(p);
    reviewOptions(p);
  }),
  CliCommand(
    'resource action',
    '发布维护：撤审、自测、上架、定时、改价、加急、弱下架、删除',
    '<id> <action>',
    2,
    2,
    (p) {
      categoryOptions(p);
      p.addOption('at', help: '定时上架时间 YYYY-MM-DD HH:mm');
      p.addOption('reason', help: '加急/免审弱下架原因');
      p.addOption('price', help: '官方价格');
      p.addOption('channel-price', help: '渠道价格');
      p.addOption('rank', help: '官方价格档位');
      p.addOption('channel-rank', help: '渠道价格档位');
      p.addFlag('confirm-queue', negatable: false, help: '同意排队确认');
      p.addFlag('yes', negatable: false, help: '确认删除作品');
    },
  ),
  CliCommand('media upload', '单独上传素材，输出可用于作品的签名数据', '<path>', 1, 1, (p) {
    categoryOptions(p);
    p.addOption(
      'type',
      defaultsTo: 'image',
      help: '平台 file_type，image 默认裁剪；png 资源包原样上传',
    );
    p.addOption('channel', help: '展示图渠道编号，自动读取目标尺寸');
    p.addOption('secondary', help: '作品次类别编号');
    p.addOption('width', help: '目标宽度');
    p.addOption('height', help: '目标高度');
    p.addFlag('secure', negatable: false, help: '使用平台私有文件服务器');
  }),
  CliCommand('media crop', '离线居中裁剪图片并保存 PNG', '<path>', 1, 1, (p) {
    p.addOption('out', help: '输出 PNG 路径');
    p.addOption('width', help: '目标宽度');
    p.addOption('height', help: '目标高度');
  }),
  CliCommand('jobs list', '查看上传任务状态', '', 0, 0),
  CliCommand('jobs show', '查看任务进度和资源编号', '<job>', 1, 1),
  CliCommand('jobs resolve', '核对平台后恢复保存结果不明的任务', '<job>', 1, 1, (p) {
    p.addOption('id', help: '已保存的作品编号');
    p.addFlag('not-created', negatable: false, help: '已核实平台没有创建作品，允许恢复保存');
    p.addFlag('yes', negatable: false, help: '确认 not-created 判定');
  }),
  CliCommand('draft list', '列出当前账号的 GUI/CLI 本机作品草稿', '', 0, 0, categoryOptions),
  CliCommand('draft get', '读取本机作品草稿', '[id|new]', 0, 1, categoryOptions),
  CliCommand(
    'draft put',
    '保存本机作品草稿，可在 GUI 恢复',
    '<file.json> [id|new]',
    1,
    2,
    categoryOptions,
  ),
  CliCommand('draft delete', '移除本机草稿', '[id|new]', 0, 1, categoryOptions),
  CliCommand('preset list', '列出收益预设', '', 0, 0),
  CliCommand('preset get', '读取收益预设', '<id>', 1, 1),
  CliCommand('preset put', '创建或更新收益预设', '<file.json>', 1, 1),
  CliCommand('preset rename', '重命名收益预设', '<id> <name>', 2, 2),
  CliCommand('preset delete', '删除收益预设', '<id>', 1, 1),
  CliCommand('settings get', '读取应用设置', '', 0, 0),
  CliCommand(
    'settings set',
    '设置 GUI 主题（重启 GUI 生效）',
    '<theme> <system|light|dark>',
    2,
    2,
  ),
];

const commandAliases = {
  'list': 'resource list',
  'show': 'resource get',
  'upload': 'resource create',
  'edit': 'resource update',
  'submit': 'resource submit',
};
const actionAliases = {
  'cancel-review': 'cancel_review',
  'self-test': 'self-test-apply',
  'self-test-unchecked': 'self_test_without_check',
  'cancel-test': 'cancel_self_test',
  'publish': 'online',
  'schedule': 'appoint_online',
  'cancel-schedule': 'cancel_appoint',
  'price': 'change_price',
  'offline': 'exempt_review',
  'urgent': 'urgent-admin',
  'remind': 'remind',
  'delete': 'delete',
};

ArgParser commandParser() {
  ArgParser parser() => ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: '显示帮助')
    ..addFlag('json', negatable: false, help: '输出机器可读帮助；普通命令始终输出 JSON')
    ..addFlag('pretty', negatable: false, help: '缩进 JSON 输出')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: '进度和诊断写入 stderr')
    ..addOption('home', help: '状态目录，默认与桌面软件共享；也可设置 MCDEV_HOME');
  final root = parser();
  for (final spec in cliCommands) {
    var parent = root;
    for (final name in spec.path.split(' ')) {
      if (!parent.commands.containsKey(name)) parent.addCommand(name, parser());
      parent = parent.commands[name]!;
    }
    spec.configure?.call(parent);
  }
  for (final alias in commandAliases.entries) {
    final spec = cliCommands.firstWhere((s) => s.path == alias.value);
    root.addCommand(alias.key, parser());
    spec.configure?.call(root.commands[alias.key]!);
  }
  return root;
}
