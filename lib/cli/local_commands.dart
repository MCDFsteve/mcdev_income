part of 'cli.dart';

extension _LocalCommands on McdevCli {
  Future<Map<String, dynamic>> _readJob(String id) async {
    if (!RegExp(r'^\d+-\d+$').hasMatch(id)) {
      throw CliFailure('invalid_job', '无效任务编号');
    }
    return readObject('$home/jobs/$id.json');
  }

  Future<Object?> _jobs(String action) async {
    if (action == 'list') {
      final directory = Directory('$home/jobs');
      if (!await directory.exists()) return [];
      final entries = <Map<String, dynamic>>[];
      await for (final f in directory.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        final j = await readObject(f.path);
        entries.add({
          for (final key in [
            'id',
            'category',
            'item_id',
            'phase',
            'submit',
            'submitted',
            'created_at',
          ])
            key: j[key],
        });
      }
      entries.sort((a, b) => '${b['id']}'.compareTo('${a['id']}'));
      return entries;
    }
    final id = args.rest.single;
    if (!RegExp(r'^\d+-\d+$').hasMatch(id)) {
      throw CliFailure('invalid_job', '无效任务编号');
    }
    if (action == 'show') return _readJob(id);
    return withFileLock('$home/jobs/$id.lock', () async {
      final job = await _readJob(id);
      if (!['unknown', 'saving'].contains(job['phase'])) {
        throw CliFailure('invalid_job_state', '仅保存结果不明的任务需要 resolve');
      }
      if (has('id') == flag('not-created')) {
        throw CliFailure('usage', '请选择 --id <作品编号> 或 --not-created --yes');
      }
      if (has('id')) {
        final client = await api();
        final item = await client.fetchResourceDetail(
          resourceCategory: job['category'],
          itemId: str('id')!,
        );
        if (item.name != job['values']?['item_name']) {
          throw CliFailure('job_resource_mismatch', '作品名称与上传任务不匹配，请核对作品编号');
        }
        job['item_id'] = item.id;
        job['phase'] = 'saved';
      } else {
        if (!flag('yes')) {
          throw CliFailure('confirmation_required', '核实平台没有创建作品后，添加 --yes');
        }
        if (job['item_id'] != null) {
          throw CliFailure(
            'invalid_resolution',
            '更新任务请用 --id 关联原作品，核对字段后再执行独立 edit',
          );
        }
        job['phase'] = 'prepared';
      }
      await writeJsonFile('$home/jobs/$id.json', job);
      return {
        'job': id,
        'item_id': job['item_id'],
        'phase': job['phase'],
        'resume': 'mcdev upload --resume $id',
      };
    }, wait: false);
  }

  Future<String> _draftPrefix() async {
    final session = await LoginService.readLoginSession();
    if (session == null) {
      throw CliFailure('auth_required', '本机草稿需要邮箱会话以匹配 GUI 账号', exitCode: 3);
    }
    return 'resource_draft_v1:${session.email}:$category:';
  }

  Future<Object?> _draft(String action) async {
    final prefix = await _draftPrefix();
    if (action == 'list') {
      return [
        for (final key in store.getKeys().where((k) => k.startsWith(prefix)))
          {
            'id': key.substring(prefix.length),
            'draft': jsonDecode(store.getString(key)!),
          },
      ];
    }
    final id =
        (action == 'put'
            ? args.rest.skip(1).firstOrNull
            : args.rest.firstOrNull) ??
        'new';
    final key = '$prefix$id';
    if (action == 'delete') {
      await store.remove(key);
      return {'deleted': id};
    }
    if (action == 'put') {
      final data = await readObject(args.rest.first);
      final fields = objectMap(data['fields'] ?? data, 'draft');
      final draft = ResourceDraft(category: category, source: fields);
      await store.setString(key, jsonEncode(draft.values));
      return {'id': id, 'saved': true};
    }
    final value = store.getString(key);
    if (value == null) throw CliFailure('not_found', '未找到草稿 $id');
    return jsonDecode(value);
  }

  List<Map<String, dynamic>> _presets() {
    final raw = store.getString('income_presets_v1');
    if (raw == null) return [];
    return ResourceOptions.maps(jsonDecode(raw));
  }

  Future<Object?> _preset(String action) async {
    final list = _presets();
    if (action == 'list') return list;
    if (action == 'put') {
      final source = await readObject(args.rest.single);
      final id =
          source['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final existing = list.where((p) => p['id'] == id).firstOrNull;
      final value = <String, dynamic>{
        'id': id,
        'category': 'pe',
        'scope': 'all',
        'modIds': <String>[],
        'internalRatios': <String, dynamic>{},
        'neteaseRatios': <String, dynamic>{},
        'defaultInternalRatio': 1.0,
        'defaultNeteaseRatio': 0.39,
        'taxRate': 0.16,
        ...?existing,
        ...source,
      };
      if (value['name'] is! String || value['name'].toString().trim().isEmpty) {
        throw CliFailure('invalid_preset', '预设需要非空 name');
      }
      if (!['pe', 'java'].contains(value['category']) ||
          !['all', 'multiple', 'single'].contains(value['scope'])) {
        throw CliFailure('invalid_preset', 'category 或 scope 无效');
      }
      final ids = value['modIds'];
      if (ids is! List ||
          ids.any((e) => e is! String) ||
          (value['scope'] != 'all' && ids.isEmpty) ||
          (value['scope'] == 'single' && ids.length != 1)) {
        throw CliFailure('invalid_preset', 'modIds 必须是作品编号字符串数组，与 scope 匹配');
      }
      for (final key in [
        'defaultInternalRatio',
        'defaultNeteaseRatio',
        'taxRate',
      ]) {
        _ratio(value[key], key);
      }
      for (final key in ['internalRatios', 'neteaseRatios']) {
        for (final e in objectMap(value[key], key).entries) {
          _ratio(e.value, '$key.${e.key}');
        }
      }
      value['id'] = id;
      value['updatedAt'] = DateTime.now().toIso8601String();
      list.removeWhere((p) => p['id'] == id);
      list.add(value);
      await store.setString('income_presets_v1', jsonEncode(list));
      return value;
    }
    final id = args.rest.first;
    final value = list.where((p) => p['id'] == id).firstOrNull;
    if (value == null) throw CliFailure('not_found', '未找到预设 $id');
    if (action == 'get') return value;
    if (action == 'delete') list.remove(value);
    if (action == 'rename') {
      if (args.rest[1].trim().isEmpty) {
        throw CliFailure('invalid_name', '名称不能为空');
      }
      value['name'] = args.rest[1];
      value['updatedAt'] = DateTime.now().toIso8601String();
    }
    await store.setString('income_presets_v1', jsonEncode(list));
    return action == 'delete' ? {'deleted': id} : value;
  }
}
