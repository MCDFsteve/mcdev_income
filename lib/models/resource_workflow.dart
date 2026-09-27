part of '../core.dart';

/// Field types and upload constraints come from the platform's mc_consts response.
class ResourceOptions {
  ResourceOptions(this.raw);
  final Map<String, dynamic> raw;

  static List<Map<String, dynamic>> maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];

  List<Map<String, dynamic>> primary(String category) =>
      maps((raw['pri_type'] as Map?)?[category]);
  List<Map<String, dynamic>> secondary(String category, dynamic primary) =>
      maps(
        (raw['sub_type'] as Map?)?[category == 'comp'
            ? 'pc'
            : category]?[primary.toString()],
      );
  List<Map<String, dynamic>> channels(String category, [dynamic subType]) {
    final all = maps((raw['channel'] as Map?)?[category]);
    final special =
        (raw['special_channel'] as Map?)?[category]?[subType.toString()];
    if (special is List) {
      return all.where((c) => special.contains(c['id'])).toList();
    }
    return all.where((c) => c['vip_only'] != true).toList();
  }

  List<Map<String, dynamic>> get prices => maps(raw['price_type']);
  List<String> strings(String key) => (raw[key] is List)
      ? (raw[key] as List).map((e) => e.toString()).toList()
      : [];
}

class UploadedResourceFile {
  const UploadedResourceFile({
    required this.url,
    required this.name,
    required this.fileType,
    required this.body,
    required this.signature,
  });
  final String url;
  final String name;
  final String fileType;
  final String body;
  final String signature;

  Map<String, dynamic> get signedValue => {
    'body': body,
    'file_type': fileType,
    'sign': signature,
  };
}

class ResourcePriceSettings {
  ResourcePriceSettings(
    this.raw, {
    this.useRank = false,
    this.hasChannel = false,
  });
  final Map<String, dynamic> raw;
  final bool useRank;
  final bool hasChannel;

  bool get ranked =>
      useRank || (int.tryParse('${raw['new_price_rank_switch']}') ?? 0) != 0;
  List<Map<String, dynamic>> get ranks {
    final value = raw['item_price_rank'];
    return ResourceOptions.maps(value is String ? jsonDecode(value) : value);
  }

  List<Map<String, dynamic>> choices({int? current}) => [
    for (var i = 0; i < ranks.length; i++)
      if (current == null || current < 0 || (i - current).abs() <= 1)
        {
          'id': i,
          'title': '第 ${i + 1} 档 · ${ranks[i]['price']} 钻石',
          'price': ranks[i]['price'],
        },
  ];

  List<String> validate(ResourceDraft draft) {
    final errors = <String>[];
    final type = draft.text('price_type');
    if (ranked && type == 'diamond') {
      for (final key in ['price_rank', if (hasChannel) 'channel_price_rank']) {
        final rank = int.tryParse(draft.text(key));
        final priceKey = key == 'price_rank' ? 'price' : 'other_channel_price';
        if (rank == null ||
            rank < 0 ||
            rank >= ranks.length ||
            draft.text(priceKey) != '${ranks[rank]['price']}') {
          errors.add('请选择${key == 'price_rank' ? '官方' : '渠道'}平台定价档位');
        }
      }
    }
    if (hasChannel && ['diamond', 'unrestricted_diamond'].contains(type)) {
      final channel = int.tryParse(draft.text('other_channel_price'));
      final price = int.tryParse(draft.text('price')) ?? 0;
      if (channel == null || channel < price) errors.add('渠道平台价格不能低于官方平台价格');
    }
    return errors;
  }
}

class ResourceDraft {
  ResourceDraft({required this.category, Map<String, dynamic>? source})
    : values = Map<String, dynamic>.from(
        jsonDecode(
              jsonEncode({
                'item_name': '',
                'brief': '',
                'info': '',
                'pri_type': null,
                'sub_type': null,
                'price_type': 'free',
                'price': 0,
                'mc_version': <String>[],
                'mod_version': '',
                'res': <dynamic>[],
                'channel': <dynamic>[],
                'requirement': <dynamic>[],
                'charge_type': category == 'pe' ? 'worlds' : 'mods',
                'charge_desc': '',
                'current_change_log': '',
                'update_summary': '',
                'available_scope': 'client',
                'body_type': '',
                'banner_pic': '',
                'pre_review_video': '',
                'force_encrypt': false,
                'is_original': false,
                'searchable': true,
                'version_compatible_enable': false,
                'anti_cheat_enable': 0,
                'item_update_push': true,
                ...?source,
              }),
            )
            as Map,
      );

  final String category;
  final Map<String, dynamic> values;
  dynamic get(String key) {
    dynamic value = values;
    for (final segment in key.split('.')) {
      value = value is Map ? value[segment] : null;
    }
    return value;
  }

  void set(String key, dynamic value) {
    final path = key.split('.');
    Map<dynamic, dynamic> target = values;
    for (final segment in path.take(path.length - 1)) {
      if (target[segment] is! Map) target[segment] = <String, dynamic>{};
      target = target[segment];
    }
    target[path.last] = value;
  }

  String text(String key) => get(key)?.toString() ?? '';
  List<Map<String, dynamic>> entries(String key) =>
      ResourceOptions.maps(get(key));
  List<String> strings(String key) => get(key) is List
      ? (get(key) as List).map((e) => e.toString()).toList()
      : [];

  // Only response metadata is discarded. Unknown editable fields from existing
  // resources are preserved so newer platform fields are not silently erased.
  static const readOnlyFields = {
    'item_id',
    'category',
    'status',
    'item_real_status',
    'author_info',
    'create_time',
    'update_time',
    'online_time',
    'first_online_time',
    'apply_review_time',
    'queue_position',
    'urgent_status',
    'urgent_reason',
    'perf_data',
    'change_log',
    'intercept_fields',
    'level_data_sync_error',
    'level_data_sync_status',
    'discount_activity_status',
    'is_in_promotion_application',
    'can_manage_server',
    'can_silent_online',
    'can_synchronize_pc_old',
  };

  Map<String, dynamic> toPayload() {
    final result = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(values)) as Map,
    );
    result.removeWhere((key, _) => readOnlyFields.contains(key));
    result['item_name'] = text('item_name').trim();
    for (final key in ['pri_type', 'sub_type', 'mod_second_type', 'price']) {
      if (result[key] is String) result[key] = int.tryParse(result[key]);
    }
    if (result['price_type'] == 'free') result['price'] = 0;
    if (text('charge_desc').isEmpty) {
      result['charge_desc'] = '${result['item_name']}付费备注';
    }
    if (text('pre_review_video').isEmpty || text('pre_review_video') == '{}') {
      result.remove('pre_review_video');
    }
    if (result['mc_version'] is! List) result['mc_version'] = <String>[];
    if (category == 'pe') {
      result['prerequisite_item_ids'] = entries(
        'prerequisite_items',
      ).map((e) => e['item_id']).where((e) => e != null).toList();
      if (result['pri_type'] != 2) result.remove('mod_second_type');
      final dlc = result['dlc_info'];
      if (dlc is Map && dlc['dlc_switch'] == true) {
        final self = {
          'item_id': values['item_id'] ?? '',
          'item_name': result['item_name'],
        };
        if (dlc['dlc_type'] == 'master') dlc['master'] = self;
        if (dlc['dlc_type'] == 'slave') {
          final slaves = ResourceOptions.maps(dlc['slave_list']);
          slaves.removeWhere((e) => e['item_id'] == self['item_id']);
          dlc['slave_list'] = [...slaves, self];
        }
      }
    }
    return result;
  }

  List<String> validate(ResourceOptions options) {
    final errors = <String>[];
    if (text('item_name').trim().isEmpty) errors.add('请填写资源名称');
    if (values['pri_type'] == null) errors.add('请选择主类别');
    if (values['sub_type'] == null) errors.add('请选择次类别');
    final price = int.tryParse(text('price'));
    if (price == null || price < 0) errors.add('价格必须是非负整数');
    final rule = options.prices
        .where((e) => e['id'] == values['price_type'])
        .firstOrNull;
    if (rule != null && price != null && values['price_type'] != 'free') {
      final min = (rule['min'] as num?)?.toInt() ?? 0;
      final max = (rule['max'] as num?)?.toInt();
      final step = (rule['step'] as num?)?.toInt() ?? 1;
      if (price < min ||
          (max != null && price > max) ||
          (step > 0 && price % step != 0)) {
        errors.add(
          '价格不符合平台要求：最低 $min，步进 $step${max == null ? '' : '，最高 $max'}',
        );
      }
    }
    if (text('info').trim().isEmpty) errors.add('请填写资源介绍');
    if (category == 'comp' && strings('mc_version').isEmpty) {
      errors.add('请选择适用游戏版本');
    }
    if (entries('res').isEmpty && values['pure'] != true) errors.add('请上传资源文件');
    final channels = entries('channel');
    for (final rule in options.channels(category, values['sub_type'])) {
      if (rule['required'] == 1 &&
          !channels.any(
            (c) =>
                c['channel_id'] == rule['id'] &&
                c['channel_url'] != null &&
                c['channel_url'] != '',
          )) {
        errors.add('请上传${rule['title']}');
      }
    }
    if (values['weak_offline'] == true &&
        text('weak_offline_reason').trim().isEmpty) {
      errors.add('请填写弱下架原因');
    }
    for (final video in entries('video_info_list')) {
      if (video['url'] == null || video['cover'] == null) {
        errors.add('展示视频和视频封面需要一起上传');
      }
    }
    final subtype = options
        .secondary(category, values['pri_type'])
        .where((e) => e['id'] == values['sub_type'])
        .firstOrNull;
    if (ResourceOptions.maps(subtype?['body_type']).isNotEmpty &&
        text('body_type').isEmpty) {
      errors.add('请选择皮肤体型');
    }
    if (category == 'comp') {
      for (final res in entries('res')) {
        final versions = res['mc_version'];
        if (versions is! List || versions.isEmpty) {
          errors.add('每个 PC 资源文件需要选择适用版本');
        }
      }
    }
    if (values['sync_pc_flag'] == true && category == 'pe') {
      if (text('sync_item_info.item_name').trim().isEmpty) {
        errors.add('请填写同步 PC 作品名称');
      }
      if (get('sync_item_info.pri_type') == null ||
          get('sync_item_info.sub_type') == null) {
        errors.add('请选择同步 PC 作品类别');
      }
      if (text('sync_item_info.info').trim().isEmpty) {
        errors.add('请填写同步 PC 作品介绍');
      }
      for (final rule in options.channels(
        'comp',
        get('sync_item_info.sub_type'),
      )) {
        if (rule['required'] == 1 &&
            !entries('sync_item_info.channel').any(
              (c) =>
                  c['channel_id'] == rule['id'] &&
                  c['channel_url'] != null &&
                  c['channel_url'] != '',
            )) {
          errors.add('请上传 PC ${rule['title']}');
        }
      }
      if (get('sync_item_info.weak_offline') == true &&
          text('sync_item_info.weak_offline_reason').trim().isEmpty) {
        errors.add('请填写 PC 弱下架原因');
      }
    }
    if (get('dlc_info.dlc_switch') == true) {
      if (text('dlc_info.dlc_type') == 'slave' &&
          text('dlc_info.master.item_id').isEmpty) {
        errors.add('请选择 DLC 主包');
      }
      if (entries('dlc_info.slave_list').length > 20) {
        errors.add('DLC 副包数量不能超过 20 个');
      }
    }
    if (get('is_original') != true &&
        (get('corp_proof_image') == null || get('corp_proof_image') == '')) {
      errors.add('请上传非原创作品授权证明，或确认作品为原创');
    }
    return errors;
  }
}

const resourceStatusLabels = {
  'init': '待提交审核',
  'preparing': '审核准备中',
  'reviewing': '审核中',
  'accept': '审核通过',
  'reject': '审核驳回',
  'online': '已上架',
  'offline': '已下架',
  'appoint_online': '定时上架',
  'self_test': '机审自测中',
  'self_test_prepare': '自测准备中',
};

List<(String, String)> resourceActions(
  ResourceItem item, {
  Map<String, dynamic> permissions = const {},
}) =>
    !['pe', 'comp'].contains(item.category) ||
        (item.category == 'comp' && item.raw['sync_pc_flag'] == true)
    ? []
    : [
        if (item.status == 'init') ...[
          ('apply_review', '提交审核'),
          if (item.category != 'comp') ...[
            ('self-test-apply', '机审自测'),
            ('self_test_without_check', '免机审自测'),
          ],
        ],
        if (['reviewing', 'preparing'].contains(item.status))
          ('cancel_review', '撤销审核'),
        if (['self_test', 'self_test_prepare'].contains(item.status))
          ('cancel_self_test', '取消自测'),
        if (item.status == 'accept') ('online', '上架'),
        if (item.status == 'accept') ('appoint_online', '定时上架'),
        if (item.status == 'appoint_online') ('cancel_appoint', '取消定时上架'),
        if (item.status == 'init') ('delete', '删除资源'),
        if (item.status == 'online' &&
            ['diamond', 'point'].contains(item.priceType))
          ('change_price', '调整价格'),
        if (item.status == 'online' &&
            (permissions['exempt_review_weak_offline_remain'] as num? ?? 0) > 0)
          ('exempt_review', '免审弱下架'),
        if (item.category == 'pe' &&
            item.status == 'reviewing' &&
            item.raw['urgent_status'] != true &&
            (permissions['remain_urgent_count'] as num? ?? 0) > 0)
          ('urgent-admin', '申请加急'),
        if (item.category == 'comp' &&
            ['reviewing', 'preparing'].contains(item.status) &&
            item.raw['remindable'] == true)
          ('remind', '催促审核'),
      ];

const resourceConflictTypes = <int, String>{
  0: '全部',
  1: '动画文件',
  2: '场景中目标贴图的映射表',
  3: 'Biome Client',
  4: '方块贴图',
  5: '骨骼动画',
  6: 'Mesh',
  7: '骨骼',
  8: '摄像机配置',
  9: '特效',
  10: '客户端实体',
  11: '字体',
  12: '物品资源',
  13: '材质',
  14: '粒子特效',
  15: '渲染控制',
  16: '音频文件',
  17: '语言',
  18: '纹理',
  19: 'UI',
  20: '成就系统定义',
  21: '动画控制器',
  22: '自定义方块',
  23: '自定义书',
  24: '自定义维度',
  25: '自定义效果',
  26: '自定义附魔',
  27: '自定义实体',
  28: '自定义特征',
  29: '自定义特征规则',
  30: '自定义分组',
  31: '自定义物品',
  32: '自定义大型特征',
  33: '自定义掉落表',
  34: '自定义微型块',
  35: '自定义配方',
  36: '自定义生成规则',
  37: '自定义结构',
  38: '自定义分页',
  39: '自定义交易',
  40: '自定义中文翻译',
  41: '自定义大型特征规则',
};
