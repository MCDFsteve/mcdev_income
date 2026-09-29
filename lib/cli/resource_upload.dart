import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../core.dart';
import 'common.dart';
import 'media.dart';

class ResourceUpload {
  ResourceUpload({
    required this.api,
    required this.home,
    required this.owner,
    required this.category,
    required this.options,
    required this.prices,
    this.progress,
  });
  final McDevApi api;
  final String home;
  final String owner;
  final String category;
  final ResourceOptions options;
  final ResourcePriceSettings prices;
  final void Function(String)? progress;

  Future<Map<String, dynamic>> execute(
    Map<String, dynamic> manifest, {
    String? itemId,
    bool dryRun = false,
    bool submit = false,
    bool confirmQueue = false,
    String? resume,
  }) async {
    if (resume != null) _validJobId(resume);
    if (resume != null && dryRun) {
      throw CliFailure('invalid_resume', '恢复任务不能同时 dry-run');
    }
    final notes = manifest['notes'] ?? '';
    if (notes is! String || notes.trim().length > 500) {
      throw CliFailure('invalid_notes', '审核备注必须是最多 500 字的字符串');
    }
    final notify = manifest['conflict_notify'],
        types = manifest['conflict_types'];
    if (notify != null && (notify is! int || notify < 0 || notify > 2)) {
      throw CliFailure('invalid_conflict', 'conflict_notify 必须为 0、1、2');
    }
    if (types != null &&
        (types is! List ||
            types.isEmpty ||
            types.any(
              (e) => e is! int || !resourceConflictTypes.containsKey(e),
            ))) {
      throw CliFailure(
        'invalid_conflict',
        'conflict_types 必须为非空有效类型编号数组，参考 schema',
      );
    }
    final jobId =
        resume ??
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    Future<Map<String, dynamic>> run() => _execute(
      manifest,
      jobId: jobId,
      itemId: itemId,
      dryRun: dryRun,
      submit: submit,
      confirmQueue: confirmQueue,
      resume: resume,
    );
    if (dryRun) return run();
    return withFileLock('$home/jobs/$jobId.lock', run, wait: false);
  }

  Future<Map<String, dynamic>> _execute(
    Map<String, dynamic> manifest, {
    required String jobId,
    String? itemId,
    bool dryRun = false,
    bool submit = false,
    bool confirmQueue = false,
    String? resume,
  }) async {
    Map<String, dynamic> job;
    final prepared = <int, PreparedMedia>{};
    if (resume != null) {
      _validJobId(resume);
      job = await readObject('$home/jobs/$resume.json');
      if (job['owner'] != owner || job['category'] != category) {
        throw CliFailure(
          'job_account_mismatch',
          '任务属于其他账号或类别，请使用原账号和 --category',
        );
      }
      if (['saving', 'unknown'].contains(job['phase'])) {
        throw CliFailure(
          'outcome_unknown',
          '上次保存结果不明，先核对列表，再使用 jobs resolve 关联已保存编号',
          exitCode: 6,
          details: {'job': resume},
        );
      }
      if (job['phase'] == 'complete') return _result(job);
      submit = submit || job['submit'] == true;
      itemId = job['item_id']?.toString();
    } else {
      Map<String, dynamic>? source;
      if (itemId != null) {
        final item = await api.fetchResourceDetail(
          resourceCategory: category,
          itemId: itemId,
        );
        if (category == 'comp' && item.raw['sync_pc_flag'] == true) {
          throw CliFailure(
            'synced_resource',
            '请编辑关联 PE 作品',
            details: {'pe_id': item.raw['relate_item_id']},
          );
        }
        source = item.raw;
      }
      final draft = ResourceDraft(category: category, source: source);
      mergeFields(draft.values, objectMap(manifest['fields'] ?? {}, 'fields'));
      final tasks = _tasks(manifest, draft);
      // Validate every local file before any upload. No partial upload on a bad path.
      final preview = ResourceDraft(category: category, source: draft.values);
      for (var i = 0; i < tasks.length; i++) {
        final media = await _prepare(tasks[i]);
        prepared[i] = media;
        tasks[i]['prepared'] = media.description;
        _apply(
          preview,
          tasks[i],
          UploadedResourceFile(
            url: 'pending:${media.name}',
            name: media.name,
            fileType: media.type,
            body: jsonEncode({'fsize': media.length}),
            signature: 'pending',
          ),
        );
      }
      final errors = [
        ...preview.validate(options),
        ...prices.validate(preview),
      ];
      final primary = preview.get('pri_type'),
          secondary = preview.get('sub_type');
      if (!options.primary(category).any((e) => e['id'] == primary) ||
          !options
              .secondary(category, primary)
              .any((e) => e['id'] == secondary)) {
        errors.add('作品类别不存在，请使用 resource options 获取有效类别');
      }
      if (errors.isNotEmpty) {
        throw CliFailure(
          'validation_failed',
          '作品校验未通过',
          details: {'errors': errors},
        );
      }
      if (dryRun) {
        return {
          'dry_run': true,
          'valid': true,
          'category': category,
          'item_id': itemId,
          'payload': preview.toPayload(),
          'uploads': tasks.map((t) => t['prepared']).toList(),
        };
      }
      final id = jobId;
      job = {
        'id': id,
        'owner': owner,
        'category': category,
        'item_id': itemId,
        'submit': submit,
        'phase': 'prepared',
        'values': draft.values,
        'tasks': tasks,
        'uploaded': <int>[],
        'notes': manifest['notes'] ?? '',
        'conflict_notify': manifest['conflict_notify'],
        'conflict_types': manifest['conflict_types'],
        'created_at': DateTime.now().toIso8601String(),
      };
      await _persist(job);
    }
    final draft = ResourceDraft(
      category: category,
      source: objectMap(job['values'], 'job.values'),
    );
    try {
      if (job['phase'] != 'saved' &&
          job['phase'] != 'reviewing' &&
          job['phase'] != 'review_queue') {
        final tasks = ResourceOptions.maps(job['tasks']);
        final uploaded = (job['uploaded'] as List).cast<int>().toSet();
        // A resumed job also validates all remaining paths before uploading any.
        for (var i = 0; i < tasks.length; i++) {
          if (!uploaded.contains(i)) {
            prepared[i] ??= await _prepare(tasks[i]);
            if (tasks[i]['prepared']?['sha256'] != prepared[i]!.digest) {
              throw CliFailure(
                'file_changed',
                '预检后文件已更改，请恢复原文件再继续',
                details: {'path': tasks[i]['path']},
              );
            }
          }
        }
        for (var i = 0; i < tasks.length; i++) {
          if (uploaded.contains(i)) continue;
          job['phase'] = 'uploading';
          await _persist(job);
          progress?.call('上传 ${i + 1}/${tasks.length}：${prepared[i]!.name}');
          final file = await uploadPrepared(api, prepared[i]!);
          _apply(draft, tasks[i], file);
          uploaded.add(i);
          job['uploaded'] = uploaded.toList();
          job['values'] = draft.values;
          await _persist(job);
        }
        final queuePreviouslyRequested = job['phase'] == 'save_queue';
        if (queuePreviouslyRequested && !confirmQueue) _queue(job, '保存需要确认排队');
        job['phase'] = 'saving';
        await _persist(job);
        var result = await api.saveResource(
          resourceCategory: category,
          itemId: itemId,
          payload: {
            ...draft.toPayload(),
            'is_check_apply': queuePreviouslyRequested && confirmQueue,
          },
        );
        if (result['data']?['need_check_apply'] == true) {
          job['phase'] = 'save_queue';
          job['queue_length'] = result['data']?['queue_length'];
          await _persist(job);
          if (!confirmQueue || queuePreviouslyRequested) {
            _queue(job, '保存需要确认排队');
          }
          job['phase'] = 'saving';
          await _persist(job);
          result = await api.saveResource(
            resourceCategory: category,
            itemId: itemId,
            payload: {...draft.toPayload(), 'is_check_apply': true},
          );
          if (result['data']?['need_check_apply'] == true) {
            job['phase'] = 'save_queue';
            await _persist(job);
            _queue(job, '平台仍要求排队确认');
          }
        }
        itemId = result['data']?['item_id']?.toString() ?? itemId;
        if (itemId == null || itemId.isEmpty) {
          job['phase'] = 'unknown';
          await _persist(job);
          throw CliFailure(
            'outcome_unknown',
            '平台未返回作品编号，请核对列表，勿重复创建',
            exitCode: 6,
          );
        }
        job['item_id'] = itemId;
        job['phase'] = 'saved';
        await _persist(job);
      }
      if (submit) {
        if (job['phase'] == 'reviewing') {
          final current = await api.fetchResourceDetail(
            resourceCategory: category,
            itemId: itemId!,
          );
          if ([
            'preparing',
            'reviewing',
            'accept',
            'online',
          ].contains(current.status)) {
            job['phase'] = 'complete';
            job['submitted'] = true;
            await _persist(job);
            return _result(job);
          }
          if (current.status != 'init') {
            throw CliFailure(
              'review_state_changed',
              '请核对作品状态后独立提审',
              details: {'status': current.status},
            );
          }
        }
        final queuePreviouslyRequested = job['phase'] == 'review_queue';
        if (queuePreviouslyRequested && !confirmQueue) _queue(job, '审核需要确认排队');
        final notes = job['notes'].toString();
        if (notes.trim().length > 500) {
          throw CliFailure('invalid_notes', '审核备注不能超过 500 字');
        }
        Future<Map<String, dynamic>> review(bool confirm) =>
            api.submitResourceReview(
              resourceCategory: category,
              itemId: itemId!,
              notes: notes,
              confirmQueue: confirm,
              conflictNotify: job['conflict_notify'] as int?,
              conflictTypes: (job['conflict_types'] as List?)?.cast<int>(),
            );
        job['phase'] = 'reviewing';
        await _persist(job);
        var result = await review(queuePreviouslyRequested && confirmQueue);
        if (result['data']?['need_check_apply'] == true) {
          job['phase'] = 'review_queue';
          job['queue_length'] = result['data']?['queue_length'];
          await _persist(job);
          if (!confirmQueue || queuePreviouslyRequested) {
            _queue(job, '审核需要确认排队');
          }
          job['phase'] = 'reviewing';
          await _persist(job);
          result = await review(true);
          if (result['data']?['need_check_apply'] == true) {
            job['phase'] = 'review_queue';
            await _persist(job);
            _queue(job, '平台仍要求排队确认');
          }
        }
        job['submitted'] = true;
      }
      job['phase'] = 'complete';
      await _persist(job);
      return _result(job);
    } catch (error) {
      if (job['phase'] == 'saving') {
        job['phase'] =
            error is TimeoutException ||
                error is http.ClientException ||
                (error is McDevException && error.outcomeUnknown)
            ? 'unknown'
            : 'prepared';
      }
      await _persist(job);
      final unknown = job['phase'] == 'unknown';
      throw CliFailure(
        error is CliFailure
            ? error.code
            : unknown
            ? 'outcome_unknown'
            : 'upload_failed',
        error is CliFailure
            ? error.message
            : error is McDevException
            ? error.message
            : error.toString(),
        exitCode: unknown
            ? 6
            : error is CliFailure
            ? error.exitCode
            : 4,
        details: {
          ..._result(job),
          if (error is CliFailure && error.details != null)
            'cause': error.details,
          'resume': 'mcdev upload --resume ${job['id']} --category $category',
        },
      );
    }
  }

  Never _queue(Map<String, dynamic> job, String message) => throw CliFailure(
    'queue_confirmation_required',
    '$message；添加 --confirm-queue 后恢复任务',
    exitCode: 5,
    details: {'queue_length': job['queue_length']},
  );
  Map<String, dynamic> _result(Map<String, dynamic> job) => {
    'job': job['id'],
    'category': job['category'],
    'item_id': job['item_id'],
    'phase': job['phase'],
    'submitted': job['submitted'] == true,
  };
  Future<void> _persist(Map<String, dynamic> job) =>
      writeJsonFile('$home/jobs/${job['id']}.json', job);
  static void _validJobId(String id) {
    if (!RegExp(r'^\d+-\d+$').hasMatch(id)) {
      throw CliFailure('invalid_job', '无效任务编号');
    }
  }

  Future<PreparedMedia> _prepare(Map<String, dynamic> task) => prepareMedia(
    task['path'],
    type: task['type'],
    width: task['width'] as int?,
    height: task['height'] as int?,
    maxBytes: task['max_bytes'] as int?,
    extensions: (task['extensions'] as List?)?.cast<String>(),
  );

  List<Map<String, dynamic>> _tasks(
    Map<String, dynamic> manifest,
    ResourceDraft draft,
  ) {
    final result = <Map<String, dynamic>>[];
    final base = manifest['base_dir']?.toString() ?? Directory.current.path;
    String path(dynamic value) {
      if (value is! String || value.isEmpty) {
        throw CliFailure('invalid_path', '文件路径必须是非空字符串');
      }
      return File(
        File(value).isAbsolute ? value : '$base${Platform.pathSeparator}$value',
      ).absolute.path;
    }

    void imageTask(
      dynamic value,
      String kind, {
      String? field,
      int? width,
      int? height,
      int? maxBytes,
      Map<String, dynamic>? extra,
    }) {
      result.add({
        'path': path(value),
        'type': 'image',
        'extensions': ['png', 'jpg', 'jpeg'],
        'kind': kind,
        'field': field,
        'width': width,
        'height': height,
        'max_bytes': maxBytes,
        ...?extra,
      });
    }

    final subtype = options
        .secondary(category, draft.get('pri_type'))
        .where((e) => e['id'] == draft.get('sub_type'))
        .firstOrNull;
    final packages = manifest['packages'] ?? [];
    if (packages is! List) {
      throw CliFailure('invalid_packages', 'packages 必须是数组');
    }
    for (final raw in packages) {
      final package = raw is String ? {'path': raw} : objectMap(raw, 'package');
      final type = subtype?['fp_type']?.toString();
      if (type == null) throw CliFailure('invalid_category', '此类别不支持上传资源包');
      final replace = package['replace'];
      if (replace != null &&
          (replace is! int ||
              replace < 0 ||
              replace >= draft.entries('res').length)) {
        throw CliFailure('invalid_replace_index', 'replace 必须是现有资源文件的零起始下标');
      }
      result.add({
        'kind': 'package',
        'path': path(package['path']),
        'type': type,
        'extensions': subtype!['file_type']
            .toString()
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .toList(),
        'replace': replace,
        'mc_version': package['mc_version'],
        'java_version': package['java_version'],
      });
    }
    void channels(
      dynamic raw,
      String platform,
      String field,
      dynamic secondary,
    ) {
      final images = objectMap(raw ?? {}, 'images');
      for (final entry in images.entries) {
        final rule = options
            .channels(platform, secondary)
            .where((e) => '${e['id']}' == entry.key || e['title'] == entry.key)
            .firstOrNull;
        if (rule == null) {
          throw CliFailure(
            'invalid_channel',
            '找不到图片渠道 ${entry.key}，请查看 resource options',
          );
        }
        imageTask(
          entry.value,
          'channel',
          field: field,
          width: (rule['width'] as num?)?.toInt(),
          height: (rule['height'] as num?)?.toInt(),
          extra: {'channel_id': rule['id'], 'version': rule['version']},
        );
      }
    }

    channels(manifest['images'], category, 'channel', draft.get('sub_type'));
    void descriptionImages(dynamic raw, String field) {
      if (raw == null) return;
      if (raw is! List) {
        throw CliFailure('invalid_images', 'description_images 必须是路径数组');
      }
      for (final value in raw) {
        imageTask(value, 'description', field: field);
      }
    }

    descriptionImages(manifest['description_images'], 'info');
    if (manifest['sync'] != null) {
      final sync = objectMap(manifest['sync'], 'sync');
      channels(
        sync['images'],
        'comp',
        'sync_item_info.channel',
        draft.get('sync_item_info.sub_type'),
      );
      descriptionImages(sync['description_images'], 'sync_item_info.info');
    }
    if (manifest['proof'] != null) {
      imageTask(
        manifest['proof'],
        'field',
        field: 'corp_proof_image',
        maxBytes: 10 * 1024 * 1024,
      );
    }
    if (manifest['banner'] != null) {
      imageTask(
        manifest['banner'],
        'url',
        field: 'banner_pic',
        maxBytes: 10 * 1024 * 1024,
      );
    }
    if (manifest['video'] != null) {
      final video = objectMap(manifest['video'], 'video');
      if (video['path'] != null) {
        result.add({
          'kind': 'video',
          'field': 'url',
          'type': 'video',
          'path': path(video['path']),
          'extensions': ['mp4'],
          'max_bytes': 50 * 1024 * 1024,
        });
      }
      if (video['cover'] != null) {
        imageTask(
          video['cover'],
          'video',
          field: 'cover',
          width: 992,
          height: 558,
          maxBytes: 10 * 1024 * 1024,
        );
      }
    }
    return result;
  }

  void _apply(
    ResourceDraft draft,
    Map<String, dynamic> task,
    UploadedResourceFile file,
  ) {
    final field = task['field']?.toString() ?? '';
    switch (task['kind']) {
      case 'package':
        final resources = draft.entries('res');
        final index = task['replace'] as int?;
        final previous = index == null ? <String, dynamic>{} : resources[index];
        final resource = file.packageEntry(
          previous: previous,
          mcVersion:
              task['mc_version'] ??
              previous['mc_version'] ??
              draft.strings('mc_version'),
          javaVersion: task['java_version'],
        );
        if (index == null) {
          resources.add(resource);
        } else {
          resources[index] = resource;
        }
        draft.set('res', resources);
      case 'channel':
        final images = draft.entries(field)
          ..removeWhere((e) => e['channel_id'] == task['channel_id']);
        images.add({
          'channel_id': task['channel_id'],
          'channel_url': file.signedValue,
          if (task['version'] != null) 'version': task['version'],
        });
        draft.set(field, images);
      case 'description':
        const escape = HtmlEscape(HtmlEscapeMode.attribute);
        draft.set(
          field,
          '${draft.text(field)}<p><img src="${escape.convert(file.url)}" data-fp-body="${escape.convert(file.body)}" data-fp-sign="${escape.convert(file.signature)}"></p>',
        );
      case 'video':
        final videos = draft.entries('video_info_list');
        if (videos.isEmpty) videos.add({});
        videos[0][field] = file.signedValue;
        if (field == 'url') videos[0]['size'] = jsonDecode(file.body)['fsize'];
        draft.set('video_info_list', videos);
      case 'field':
        draft.set(field, file.signedValue);
      case 'url':
        draft.set(field, file.url);
    }
  }
}
