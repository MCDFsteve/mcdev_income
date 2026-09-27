part of 'cli.dart';

extension _ResourceCommands on McdevCli {
  Future<Object?> _resource(String action) async {
    if (action == 'create' || action == 'update') return _upload(action);
    final client = await api();
    final cat = category;
    if (action == 'list') {
      final limit = integer(str('limit'), 'limit', min: 1, max: 100);
      var start = (integer(str('page'), 'page', min: 1) - 1) * limit;
      final items = <Map<String, dynamic>>[], seen = <String>{};
      var total = 0;
      do {
        final page = await client.fetchResources(
          resourceCategory: cat,
          start: start,
          span: limit,
          keyword: str('query'),
          status: str('status'),
        );
        total = page.total;
        for (final item in page.items) {
          if (seen.add(item.id)) {
            items.add(item.raw);
          } else if (flag('all')) {
            throw CliFailure(
              'pagination_changed',
              '列表分页出现重复，请重试以获取完整结果',
              exitCode: 4,
            );
          }
        }
        start += page.items.length;
        if (!flag('all') || page.items.isEmpty || start >= total) break;
      } while (true);
      return {
        'category': cat,
        'items': items,
        'total': total,
        'next_offset': start < total ? start : null,
      };
    }
    if (action == 'options') return _configuration(client);
    if (action == 'requirements') {
      return client.searchRequirements(cat, args.rest.single);
    }
    if (action == 'dlc') return client.searchDlcResources(args.rest.single);
    final id = args.rest.first;
    if (action == 'get') {
      return (await client.fetchResourceDetail(
        resourceCategory: cat,
        itemId: id,
      )).raw;
    }
    if (action == 'feedback') {
      return client.fetchResourceFeedbacks(resourceCategory: cat, itemId: id);
    }
    final item = await client.fetchResourceDetail(
      resourceCategory: cat,
      itemId: id,
    );
    final profile = await client.fetchDeveloperProfile();
    final permissions = profile.userRaw ?? {};
    final actions = resourceActions(item, permissions: permissions);
    if (action == 'actions') {
      return {
        'item_id': id,
        'status': item.status,
        'actions': [
          for (final (code, label) in actions)
            {
              'action': code,
              'label': label,
              'command': code == 'apply_review'
                  ? 'mcdev submit $id -c $cat'
                  : 'mcdev resource action $id ${actionAliases.entries.where((e) => e.value == code).firstOrNull?.key ?? code} -c $cat',
            },
        ],
      };
    }
    final requested = action == 'submit'
        ? 'apply_review'
        : actionAliases[args.rest[1]] ?? args.rest[1];
    if (!actions.any((a) => a.$1 == requested)) {
      throw CliFailure(
        'action_unavailable',
        '当前作品状态或权限不允许此操作',
        details: {
          'status': item.status,
          'available': actions.map((a) => a.$1).toList(),
        },
      );
    }
    if (requested == 'apply_review') {
      final review = _reviewArguments();
      _checkConflict(review, permissions);
      final result = await client.submitResourceReview(
        resourceCategory: cat,
        itemId: id,
        notes: review['notes'],
        confirmQueue: flag('confirm-queue'),
        conflictNotify: review['conflict_notify'],
        conflictTypes: review['conflict_types'],
      );
      _checkQueue(result);
      return {'item_id': id, 'submitted': true, 'response': result};
    }
    if (requested == 'delete') {
      if (!flag('yes')) {
        throw CliFailure('confirmation_required', '删除作品需要 --yes');
      }
      return client.deleteResource(resourceCategory: cat, itemId: id);
    }
    var endpoint = requested;
    final payload = <String, dynamic>{};
    if (requested == 'change_price') {
      final config = await _configuration(client, profile: profile);
      return client.resourcePostAction(
        resourceCategory: cat,
        itemId: id,
        action: requested,
        payload: _pricePayload(item, config),
      );
    }
    if (requested == 'urgent-admin' || requested == 'exempt_review') {
      final reason = str('reason')?.trim() ?? '';
      if (reason.isEmpty) throw CliFailure('reason_required', '此操作需要 --reason');
      if (requested == 'urgent-admin') {
        return client.resourcePostAction(
          resourceCategory: cat,
          itemId: id,
          action: requested,
          payload: {'reason': reason},
        );
      }
      payload.addAll({
        'type': 'weak_offline',
        'weak_offline_reason': reason,
        if (item.raw['sync_pc_flag'] == true) 'op_platform': 'all',
      });
    }
    if (requested == 'appoint_online') {
      DateTime time;
      try {
        time = DateFormat('yyyy-MM-dd HH:mm').parseStrict(str('at') ?? '');
      } on FormatException {
        throw CliFailure('invalid_time', '--at 格式应为 YYYY-MM-DD HH:mm（本机时区）');
      }
      if (!time.isAfter(DateTime.now())) {
        throw CliFailure('invalid_time', '定时上架时间必须在将来');
      }
      payload['appoint_online_time'] = DateFormat(
        'yyyy-MM-dd HH:mm:00',
      ).format(time);
    }
    if (requested == 'cancel_appoint') {
      endpoint = 'appoint_online';
      payload['appoint_online_time'] = null;
    }
    if (requested == 'self-test-apply' ||
        requested == 'self_test_without_check') {
      endpoint = 'self-test-apply';
      payload.addAll({
        'self_test_pass_check': requested == 'self_test_without_check',
        'is_check_apply': flag('confirm-queue'),
      });
    }
    if (requested == 'remind') {
      return client.resourcePostAction(
        resourceCategory: cat,
        itemId: id,
        action: requested,
        payload: payload,
      );
    }
    final response = await client.changeResourceStatus(
      resourceCategory: cat,
      itemId: id,
      action: endpoint,
      payload: payload,
    );
    _checkQueue(response);
    return response;
  }

  Future<Map<String, dynamic>> _configuration(
    McDevApi client, {
    DeveloperProfile? profile,
  }) async {
    final options = await client.fetchResourceOptions();
    final settings = await client.fetchPlatformSettings('item_price_setting');
    profile ??= await client.fetchDeveloperProfile();
    return {
      'options': options.raw,
      'price_settings': settings,
      'permissions': _redact(profile.userRaw ?? {}),
    };
  }

  ResourcePriceSettings _prices(Map<String, dynamic> config) {
    final permissions = objectMap(config['permissions'] ?? {}, 'permissions');
    return ResourcePriceSettings(
      objectMap(config['price_settings'] ?? {}, 'price_settings'),
      useRank: permissions['use_price_rank'] == true,
      hasChannel: permissions['can_office_channel'] == true,
    );
  }

  Map<String, dynamic> _pricePayload(
    ResourceItem item,
    Map<String, dynamic> config,
  ) {
    final settings = _prices(config),
        draft = ResourceDraft(category: item.category, source: item.raw);
    final ranked = settings.ranked && item.priceType == 'diamond';
    final channel =
        settings.hasChannel &&
        ['diamond', 'unrestricted_diamond'].contains(item.priceType);
    for (final (key, priceKey, rankArg, priceArg) in [
      ('price_rank', 'price', 'rank', 'price'),
      if (channel)
        (
          'channel_price_rank',
          'other_channel_price',
          'channel-rank',
          'channel-price',
        ),
    ]) {
      if (ranked) {
        final rank = integer(str(rankArg), rankArg, min: 0);
        if (!settings
            .choices(current: int.tryParse('${item.raw[key]}'))
            .any((e) => e['id'] == rank)) {
          throw CliFailure(
            'invalid_rank',
            '价格档位只允许相邻调整',
            details: {
              'choices': settings.choices(
                current: int.tryParse('${item.raw[key]}'),
              ),
            },
          );
        }
        draft.set(key, rank);
        draft.set(priceKey, settings.ranks[rank]['price']);
      } else {
        draft.set(priceKey, integer(str(priceArg), priceArg, min: 0));
      }
    }
    final errors = settings.validate(draft);
    final rule = ResourceOptions(
      objectMap(config['options'], 'options'),
    ).prices.where((e) => e['id'] == item.priceType).firstOrNull;
    final price = integer(draft.text('price'), 'price', min: 0);
    final min = (rule?['min'] as num?)?.toInt() ?? 0,
        max = (rule?['max'] as num?)?.toInt(),
        step = (rule?['step'] as num?)?.toInt() ?? 1;
    if (price < min ||
        (max != null && price > max) ||
        (step > 0 && price % step != 0)) {
      errors.add('价格不符合平台范围或步进');
    }
    if (errors.isNotEmpty) {
      throw CliFailure('invalid_price', '价格校验失败', details: errors);
    }
    return {
      'price_type': item.priceType,
      'price': price,
      if (ranked) 'price_rank': draft.get('price_rank'),
      if (channel) 'other_channel_price': draft.get('other_channel_price'),
      if (channel && ranked)
        'channel_price_rank': draft.get('channel_price_rank'),
    };
  }

  Map<String, dynamic> _reviewArguments() {
    final notes = str('notes') ?? '';
    if (notes.trim().length > 500) {
      throw CliFailure('invalid_notes', '审核备注不能超过 500 字');
    }
    return {
      'notes': notes,
      if (has('conflict'))
        'conflict_notify': ['none', 'mine', 'all'].indexOf(str('conflict')!),
      if (has('conflict-types'))
        'conflict_types': many(
          'conflict-types',
        ).map((s) => integer(s, 'conflict-types', min: 0, max: 41)).toList(),
    };
  }

  void _checkConflict(
    Map<String, dynamic> review,
    Map<String, dynamic> permissions,
  ) {
    if ((review['conflict_notify'] != null ||
            review['conflict_types'] != null) &&
        permissions['can_set_conflict_notify'] != true) {
      throw CliFailure('permission_denied', '账号未开放冲突检测配置');
    }
  }

  void _checkQueue(Map<String, dynamic> response) {
    if (response['data']?['need_check_apply'] == true) {
      throw CliFailure(
        'queue_confirmation_required',
        '平台要求排队确认；使用 --confirm-queue 后重试',
        exitCode: 5,
        details: response['data'],
      );
    }
  }

  Future<Object?> _upload(String action) async {
    final update = action == 'update';
    if (update && has('id')) {
      throw CliFailure('usage', 'edit 的作品编号写在命令后，不需要 --id');
    }
    var id = update ? args.rest.first : str('id');
    final manifestPath = args.rest.length > (update ? 1 : 0)
        ? args.rest.last
        : null;
    final resume = str('resume');
    if (resume != null &&
        (manifestPath != null ||
            flag('dry-run') ||
            has('id') ||
            update ||
            [
              'file',
              'image',
              'set',
              'name',
              'primary',
              'secondary',
              'info',
              'intro',
              'original',
              'video',
              'video-cover',
              'notes',
              'conflict',
              'conflict-types',
            ].any(has))) {
      throw CliFailure(
        'invalid_resume',
        '--resume 仅可配合 --category、--submit、--confirm-queue 和全局选项',
      );
    }
    var manifest = manifestPath == null
        ? <String, dynamic>{}
        : await readObject(manifestPath);
    // Accept both an authored manifest and a saved success envelope.
    if (manifest['ok'] == true && manifest['data'] is Map) {
      manifest = objectMap(manifest['data'], 'data');
    }
    const keys = {
      'category',
      'fields',
      'base_dir',
      'packages',
      'images',
      'description_images',
      'video',
      'proof',
      'banner',
      'sync',
      'notes',
      'conflict_notify',
      'conflict_types',
    };
    final unknown = manifest.keys.toSet().difference(keys);
    if (unknown.isNotEmpty) {
      throw CliFailure(
        'unknown_manifest_fields',
        '清单中有未知字段，作品字段请放入 fields',
        details: unknown.toList(),
      );
    }
    manifest['base_dir'] = manifestPath == null
        ? Directory.current.path
        : File(manifestPath).absolute.parent.path;
    final rawCat = has('category')
        ? category
        : manifest['category']?.toString() ?? category;
    var cat = ['pc', 'java'].contains(rawCat) ? 'comp' : rawCat;
    if (resume != null) {
      final job = await _readJob(resume);
      if (!has('category')) cat = job['category'];
    }
    if (!['pe', 'comp'].contains(cat)) {
      throw CliFailure('unsupported_category', '作品编辑仅支持 pe/comp，网络服与 GUI 一样只读');
    }
    final draft = ResourceDraft(
      category: cat,
      source: objectMap(manifest['fields'] ?? {}, 'fields'),
    );
    // Only overlay explicitly supplied fields; update uses the existing server data.
    final fields = objectMap(manifest['fields'] ?? {}, 'fields');
    for (final (arg, key) in [('name', 'item_name'), ('info', 'info')]) {
      if (has(arg)) fields[key] = str(arg);
    }
    for (final (arg, key) in [
      ('primary', 'pri_type'),
      ('secondary', 'sub_type'),
    ]) {
      if (has(arg)) fields[key] = integer(str(arg), arg, min: 0);
    }
    if (flag('original')) fields['is_original'] = true;
    if (has('intro')) fields['info'] = await File(str('intro')!).readAsString();
    draft.values.clear();
    draft.values.addAll(fields);
    for (final entry in many('set')) {
      final split = entry.indexOf('=');
      if (split <= 0) throw CliFailure('invalid_set', '--set 格式为 字段路径=JSON');
      draft.set(
        entry.substring(0, split),
        jsonDecode(entry.substring(split + 1)),
      );
    }
    manifest['fields'] = draft.values;
    String absolute(String path) => File(path).absolute.path;
    if (has('file')) {
      manifest['packages'] = [
        ...(manifest['packages'] as List? ?? []),
        ...many('file').map(absolute),
      ];
    }
    if (has('image')) {
      final images = objectMap(manifest['images'] ?? {}, 'images');
      for (final pair in many('image')) {
        final i = pair.indexOf('=');
        if (i <= 0) throw CliFailure('invalid_image', '--image 格式为 渠道编号=路径');
        images[pair.substring(0, i)] = absolute(pair.substring(i + 1));
      }
      manifest['images'] = images;
    }
    if (has('video') || has('video-cover')) {
      manifest['video'] = {
        ...objectMap(manifest['video'] ?? {}, 'video'),
        if (has('video')) 'path': absolute(str('video')!),
        if (has('video-cover')) 'cover': absolute(str('video-cover')!),
      };
    }
    final review = _reviewArguments();
    for (final key in review.keys) {
      if (key != 'notes' || has('notes')) manifest[key] = review[key];
    }
    final offline = flag('dry-run') && has('options');
    if (has('options') && !offline) {
      throw CliFailure(
        'invalid_options',
        '--options 仅用于 --dry-run；实际上传使用最新平台规则',
      );
    }
    if (offline && id != null) {
      throw CliFailure('offline_update', '现有作品校验需要读取平台详情，请去掉 --options');
    }
    final client = await api(allowOffline: offline);
    var config = offline
        ? await readObject(str('options')!)
        : await _configuration(client);
    if (config['ok'] == true) config = objectMap(config['data'], 'data');
    _checkConflict(
      manifest,
      objectMap(config['permissions'] ?? {}, 'permissions'),
    );
    final session = await LoginService.readLoginSession();
    // Owner derives from the remote account when cookie credentials are used.
    final owner = environment['MCDEV_COOKIE']?.isNotEmpty == true
        ? 'cookie:${credentialFingerprint(environment['MCDEV_COOKIE']!)}'
        : session?.email ?? 'offline';
    return ResourceUpload(
      api: client,
      home: home,
      owner: owner,
      category: cat,
      options: ResourceOptions(objectMap(config['options'], 'options')),
      prices: _prices(config),
      progress: progress,
    ).execute(
      manifest,
      itemId: id,
      dryRun: flag('dry-run'),
      submit: flag('submit'),
      confirmQueue: flag('confirm-queue'),
      resume: resume,
    );
  }

  Future<Object?> _media(String action) async {
    var width = has('width') ? integer(str('width'), 'width', min: 1) : null;
    var height = has('height')
        ? integer(str('height'), 'height', min: 1)
        : null;
    if (action == 'crop') {
      if (str('out') == null || width == null || height == null) {
        throw CliFailure('usage', '裁剪需要 --out、--width 和 --height');
      }
      final media = await prepareMedia(
        args.rest.single,
        type: 'image',
        width: width,
        height: height,
      );
      final file = File(str('out')!);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(media.bytes!, flush: true);
      return {...media.description, 'output': file.absolute.path};
    }
    final client = await api();
    if (has('channel')) {
      final options = await client.fetchResourceOptions();
      final rule = options
          .channels(category, str('secondary'))
          .where((e) => '${e['id']}' == str('channel'))
          .firstOrNull;
      if (rule == null) throw CliFailure('invalid_channel', '未找到图片渠道');
      width = (rule['width'] as num?)?.toInt();
      height = (rule['height'] as num?)?.toInt();
    }
    final type = str('type')!;
    final media = await prepareMedia(
      args.rest.single,
      type: type,
      width: width,
      height: height,
      extensions: type == 'video' ? ['mp4'] : null,
      maxBytes: type == 'video' ? 50 * 1024 * 1024 : null,
    );
    final result = await client.uploadResourceFile(
      name: media.name,
      length: media.length,
      stream: media.openRead(),
      fileType: type,
      secure: flag('secure'),
    );
    return {
      ...media.description,
      'url': result.url,
      'signed': result.signedValue,
    };
  }
}
