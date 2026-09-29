part of '../main.dart';

class ResourceEditorPage extends StatefulWidget {
  const ResourceEditorPage({
    super.key,
    required this.category,
    this.item,
    this.apiFactory,
  });
  final ResourceCategory category;
  final ResourceItem? item;
  final McDevApi Function()? apiFactory;
  @override
  State<ResourceEditorPage> createState() => _ResourceEditorPageState();
}

class _ResourceEditorPageState extends State<ResourceEditorPage> {
  final _scroll = ScrollController();
  final _mediaScroll = ScrollController();
  final _detailsScroll = ScrollController();
  final _controllers = <String, TextEditingController>{};
  late ResourceDraft _draft;
  ResourceOptions? _options;
  ResourcePriceSettings? _priceSettings;
  McDevApi? _api;
  String? _id;
  String? _error;
  String? _notice;
  String? _uploadLabel;
  double _progress = 0;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _changed = false;
  final _editingDescriptions = <String>{};
  String? _localKey;
  String? _localDraft;
  Map<String, dynamic> _permissions = {};
  bool _saveUncertain = false;
  String? _savedPayload;
  String? _originalDlcType;
  bool get _busy => _saving || _uploadLabel != null;

  @override
  void initState() {
    super.initState();
    _id = widget.item?.id;
    _draft = ResourceDraft(category: widget.category.value);
    _bootstrap();
  }

  @override
  void dispose() {
    _api?.close();
    _scroll.dispose();
    _mediaScroll.dispose();
    _detailsScroll.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cookie = widget.apiFactory == null
          ? await LoginCookieHelper.buildCookieHeader()
          : '';
      if (widget.apiFactory == null && cookie.isEmpty) {
        throw StateError('请先在设置中登录');
      }
      final api =
          widget.apiFactory?.call() ??
          McDevApi(cookie: cookie, category: widget.category.value);
      _api?.close();
      _api = api;
      final options = await api.fetchResourceOptions();
      final profile = await api.fetchDeveloperProfile();
      final priceSettings = await api.fetchPlatformSettings(
        'item_price_setting',
      );
      final detail = _id == null
          ? null
          : await api.fetchResourceDetail(
              resourceCategory: widget.category.value,
              itemId: _id!,
            );
      final session = await LoginCookieHelper.readLoginSession();
      final localKey =
          'resource_draft_v1:${session?.email ?? 'test'}:${widget.category.value}:${_id ?? 'new'}';
      final prefs = await AppPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _options = options;
        _permissions = profile.userRaw ?? {};
        _priceSettings = ResourcePriceSettings(
          priceSettings,
          useRank: _permissions['use_price_rank'] == true,
          hasChannel: _permissions['can_office_channel'] == true,
        );
        _draft = ResourceDraft(
          category: widget.category.value,
          source: detail?.raw,
        );
        _originalDlcType = _draft.get('dlc_info.dlc_type')?.toString();
        _localKey = localKey;
        _localDraft = prefs.getString(localKey);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  TextEditingController _controller(String key) => _controllers.putIfAbsent(
    key,
    () => TextEditingController(text: _draft.text(key)),
  );

  void _set(String key, dynamic value) {
    setState(() {
      if (key == 'dlc_info.dlc_switch' &&
          value == true &&
          !['master', 'slave'].contains(_draft.text('dlc_info.dlc_type'))) {
        _draft.set('dlc_info.dlc_type', 'master');
      }
      _draft.set(key, value);
      _dirty = true;
    });
  }

  Widget _field(
    String key,
    String label, {
    int lines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _controller(key),
      enabled: !_busy,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => _set(key, value),
    ),
  );

  Widget _select(
    String key,
    String label,
    List<Map<String, dynamic>> choices, {
    VoidCallback? afterChange,
  }) {
    final current = _draft.get(key);
    final values = [...choices];
    if (current != null &&
        current != '' &&
        !values.any((e) => e['id'] == current)) {
      values.add({'id': current, 'title': '$current（当前值）'});
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<dynamic>(
        value: current == '' ? null : current,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: values
            .map(
              (e) => DropdownMenuItem<dynamic>(
                value: e['id'],
                child: Text(e['title']?.toString() ?? '${e['id']}'),
              ),
            )
            .toList(),
        onChanged: _busy
            ? null
            : (v) {
                _set(key, v);
                afterChange?.call();
              },
      ),
    );
  }

  Widget _toggle(String key, String label) {
    final value = _draft.get(key) == true || _draft.get(key) == 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          OreChoiceButtons(
            items: const [Text('否'), Text('是')],
            selectedIndex: value ? 1 : 0,
            buttonWidth: 64,
            onChanged: _busy
                ? null
                : (v) => _set(key, key == 'anti_cheat_enable' ? v : v == 1),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => OreCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  Widget _fieldGrid(List<Widget> fields) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >=
              440 * max(1, MediaQuery.textScalerOf(context).scale(14) / 14)
          ? 2
          : 1;
      final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        children: [
          for (final field in fields) SizedBox(width: width, child: field),
        ],
      );
    },
  );

  Future<void> _saveLocal() async {
    if (_localKey == null) return;
    final prefs = await AppPreferences.getInstance();
    await prefs.setString(_localKey!, jsonEncode(_draft.values));
    if (mounted) {
      setState(() {
        _dirty = false;
        _notice = '草稿已保存在本机，可稍后继续编辑';
      });
      showOreToast(context, Text('本机草稿已保存'));
    }
  }

  void _restoreLocal() {
    try {
      final values = Map<String, dynamic>.from(jsonDecode(_localDraft!) as Map);
      final restored = ResourceDraft(
        category: widget.category.value,
        source: values,
      );
      for (final entry in _controllers.entries) {
        entry.value.text = restored.text(entry.key);
      }
      setState(() {
        _draft = restored;
        _dirty = true;
        _localDraft = null;
        _notice = '已恢复本机草稿';
      });
    } catch (_) {
      setState(() => _error = '本机草稿已损坏，无法恢复');
    }
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String confirm = '确定',
  }) async =>
      await showOreDialog<bool>(
        context: context,
        builder: (ctx) => ResourceDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirm),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _save({bool review = false}) async {
    if (_busy || _api == null || _options == null || _saveUncertain) return;
    final errors = _draft.validate(_options!);
    errors.addAll(_priceSettings?.validate(_draft) ?? []);
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      _scroll.jumpTo(0);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final payload = _draft.toPayload();
      if (review && _id != null && _savedPayload == jsonEncode(payload)) {
        setState(() => _saving = false);
        await _openReview(payload);
        return;
      }
      var result = await _api!.saveResource(
        resourceCategory: widget.category.value,
        itemId: _id,
        payload: {...payload, 'is_check_apply': false},
      );
      if (!mounted) return;
      if (result['data']?['need_check_apply'] == true) {
        final queue = result['data']?['queue_length'];
        if (!await _confirm('处理队列较长', '当前队列有 $queue 个资源，是否继续保存？')) return;
        result = await _api!.saveResource(
          resourceCategory: widget.category.value,
          itemId: _id,
          payload: {...payload, 'is_check_apply': true},
        );
        if (result['data']?['need_check_apply'] == true) {
          throw StateError('平台仍要求确认排队，请稍后重试');
        }
      }
      final savedId = result['data']?['item_id']?.toString() ?? _id;
      if (savedId == null || savedId.isEmpty) {
        _saveUncertain = true;
      }
      if (savedId == null || savedId.isEmpty) {
        throw StateError('平台未返回资源编号，请刷新列表确认保存结果，避免重复创建');
      }
      _id = savedId; // Keep the ID even if the later review request fails.
      _draft.values['item_id'] = savedId;
      _changed = true;
      _dirty = false;
      _savedPayload = jsonEncode(_draft.toPayload());
      final prefs = await AppPreferences.getInstance();
      if (_localKey != null) {
        await prefs.remove(_localKey!);
        _localKey = _localKey!.replaceFirst(RegExp(r':[^:]+$'), ':$savedId');
      }
      if (!mounted) return;
      setState(() {
        _notice = '资源已保存，尚未提交审核';
        _saving = false;
        _localDraft = null;
      });
      if (!review) {
        showOreToast(context, Text('资源已保存到平台，尚未提交审核'));
      }
      if (review) {
        await _openReview(payload);
      }
    } catch (e) {
      if (_id == null &&
          (e is TimeoutException ||
              e is http.ClientException ||
              (e is McDevException && e.outcomeUnknown))) {
        _saveUncertain = true;
      }
      if (_saveUncertain) _changed = true;
      if (mounted) {
        setState(
          () => _error = _saveUncertain
              ? '保存结果尚未确认，请返回列表刷新核对，避免重复创建。\n$e'
              : e.toString(),
        );
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openReview(Map<String, dynamic> payload) async {
    final item = ResourceItem.fromJson(widget.category.value, {
      ...payload,
      'item_id': _id,
      'status': 'init',
    });
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ResourceReviewPage(item: item, apiFactory: widget.apiFactory),
      ),
    );
    if (mounted && submitted == true) Navigator.of(context).pop(true);
  }

  Future<UploadedResourceFile?> _upload({
    required String label,
    required String fileType,
    required List<String> extensions,
    int? width,
    int? height,
    int? maxBytes,
  }) async {
    if (_busy || _api == null) return null;
    final isImage = fileType == 'image' || fileType == 'png';
    setState(() {
      _uploadLabel = '选择$label';
      _error = null;
      _progress = 0;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: isImage,
        withReadStream: !isImage,
      );
      if (!mounted || selection == null) return null;
      final file = selection.files.single;
      final cropImage = fileType == 'image';
      if (!cropImage && maxBytes != null && file.size > maxBytes) {
        throw StateError('$label不能超过 ${maxBytes ~/ (1024 * 1024)} MB');
      }
      if (!extensions.contains(file.extension?.toLowerCase())) {
        throw StateError('文件格式不符合要求：${extensions.join(' / ')}');
      }
      var name = file.name;
      var length = file.size;
      Stream<List<int>>? stream =
          file.readStream ??
          (file.bytes == null ? null : Stream.value(file.bytes!));
      if (cropImage) {
        final bytes = file.bytes;
        if (bytes == null) throw StateError('无法读取所选图片，请重新选择');
        setState(() => _uploadLabel = '裁剪$label');
        final cropped = await showResourceImageCropDialog(
          context,
          bytes: bytes,
          label: label,
          width: width,
          height: height,
          maxBytes: maxBytes,
        );
        if (!mounted || cropped == null) return null;
        name = '${file.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}-cropped.png';
        length = cropped.length;
        stream = Stream.value(cropped);
      }
      if (stream == null) throw StateError('无法读取所选文件，请重新选择');
      if (!mounted) return null;
      setState(() => _uploadLabel = '正在上传 $label：$name');
      final upload = await _api!.uploadResourceFile(
        name: name,
        length: length,
        stream: stream,
        fileType: fileType,
        onProgress: (sent, total) {
          if (mounted) setState(() => _progress = sent / total);
        },
      );
      return upload;
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploadLabel = null);
    }
  }

  Future<void> _uploadPackage([int? replaceIndex]) async {
    final subtype = _options!
        .secondary(widget.category.value, _draft.values['pri_type'])
        .where((e) => e['id'] == _draft.values['sub_type'])
        .firstOrNull;
    final fileType = subtype?['fp_type']?.toString();
    final extensions = subtype?['file_type']?.toString().split(',');
    if (fileType == null || extensions == null) {
      setState(() => _error = '请先选择支持上传的资源类别');
      return;
    }
    final file = await _upload(
      label: '资源包',
      fileType: fileType,
      extensions: extensions,
    );
    if (file == null || !mounted) return;
    final entries = _draft.entries('res');
    final previous = replaceIndex == null
        ? <String, dynamic>{}
        : entries[replaceIndex];
    final resource = file.packageEntry(
      previous: previous,
      mcVersion: previous['mc_version'] ?? _draft.strings('mc_version'),
    );
    if (replaceIndex == null) {
      entries.add(resource);
    } else {
      entries[replaceIndex] = resource;
    }
    _set('res', entries);
  }

  Future<void> _uploadChannel(
    Map<String, dynamic> rule, {
    String field = 'channel',
  }) async {
    final file = await _upload(
      label: rule['title'].toString(),
      fileType: 'image',
      extensions: ['png', 'jpg', 'jpeg'],
      width: (rule['width'] as num?)?.toInt(),
      height: (rule['height'] as num?)?.toInt(),
    );
    if (file == null || !mounted) return;
    final channels = _draft.entries(field)
      ..removeWhere((e) => e['channel_id'] == rule['id']);
    channels.add({
      'channel_id': rule['id'],
      'channel_url': file.signedValue,
      if (rule['version'] != null) 'version': rule['version'],
    });
    _set(field, channels);
  }

  String? _imageUrl(dynamic value) {
    if (value is String && value.startsWith('https://')) return value;
    if (value is Map && value['body'] is String) {
      try {
        return jsonDecode(value['body'])['url']?.toString();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _insertImage(String field) async {
    final file = await _upload(
      label: '介绍图片',
      fileType: 'image',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    if (file == null || !mounted) return;
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    final tag =
        '<p><img src="${escape.convert(file.url)}" data-fp-body="${escape.convert(file.body)}" data-fp-sign="${escape.convert(file.signature)}"></p>';
    final c = _controller(field);
    c.text += tag;
    _set(field, c.text);
  }

  Widget _packageSection() {
    final resources = _draft.entries('res');
    return _section('资源文件', [
      Text(
        '选择类别后上传对应格式的文件。替换文件时保留资源编号，支持多个版本。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < resources.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${i + 1}. ${resources[i]['res_name'] ?? '资源文件'}'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _uploadPackage(i),
                    child: const Text('替换文件'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            resources.removeAt(i);
                            _set('res', resources);
                          },
                    child: const Text('移除'),
                  ),
                ],
              ),
              if (widget.category.value == 'comp') ...[
                const SizedBox(height: 8),
                Text('此文件适用版本'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _draft.strings('mc_version').map((v) {
                    final versions = (resources[i]['mc_version'] as List? ?? [])
                        .map((e) => e.toString())
                        .toList();
                    return OreButton(
                      variant: versions.contains(v)
                          ? OreButtonVariant.primary
                          : OreButtonVariant.secondary,
                      onPressed: _busy
                          ? null
                          : () {
                              versions.contains(v)
                                  ? versions.remove(v)
                                  : versions.add(v);
                              resources[i]['mc_version'] = versions;
                              _set('res', resources);
                            },
                      child: Text(v),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ElevatedButton.icon(
        onPressed: _busy ? null : _uploadPackage,
        icon: const Icon(Icons.upload_file),
        label: const Text('添加资源文件'),
      ),
    ]);
  }

  Widget _channelSection({String? category, String field = 'channel'}) {
    final rules = _options!.channels(
      category ?? widget.category.value,
      category == 'comp'
          ? _draft.get('sync_item_info.sub_type')
          : _draft.get('sub_type'),
    );
    return _section('展示图片', [
      if (rules.isEmpty)
        const Text('当前类别无需展示图片')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final scale = max(
              1,
              MediaQuery.textScalerOf(context).scale(14) / 14,
            );
            final columns = ((constraints.maxWidth + gap) / (200 * scale + gap))
                .floor()
                .clamp(1, 4);
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 16,
              children: [
                for (final rule in rules)
                  SizedBox(
                    key: ValueKey('channel-tile-$field-${rule['id']}'),
                    width: width,
                    child: _channelTile(rule, field),
                  ),
              ],
            );
          },
        ),
    ]);
  }

  Widget _channelTile(Map<String, dynamic> rule, String field) {
    final entry = _draft
        .entries(field)
        .where((e) => e['channel_id'] == rule['id'])
        .firstOrNull;
    final url = _imageUrl(entry?['channel_url']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${rule['title']}${rule['required'] == 1 ? '（必填）' : ''}'),
        const SizedBox(height: 2),
        Text(
          '${rule['width']} × ${rule['height']}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (url != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 80,
            width: double.infinity,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, _, _) => const Text('预览暂不可用，图片已保留'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OreButton(
              size: OreButtonSize.sm,
              onPressed: _busy
                  ? null
                  : () => _uploadChannel(rule, field: field),
              child: Text(entry == null ? '上传图片' : '替换图片'),
            ),
            if (entry != null)
              OreButton(
                size: OreButtonSize.sm,
                onPressed: _busy
                    ? null
                    : () => _set(
                        field,
                        _draft.entries(field)
                          ..removeWhere((e) => e['channel_id'] == rule['id']),
                      ),
                child: const Text('移除'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _rankSelector(String key, String label, String priceKey) => _select(
    key,
    label,
    _priceSettings!.choices(),
    afterChange: () {
      final rank = _draft.get(key) as int;
      final price = _priceSettings!.ranks[rank]['price'];
      _set(priceKey, price);
      _controller(priceKey).text = '$price';
    },
  );

  Widget _basicSection() {
    final category = widget.category.value;
    return _section('基本信息', [
      _field('item_name', '资源名称'),
      _fieldGrid([
        _select(
          'pri_type',
          '主类别',
          _options!.primary(category),
          afterChange: () {
            _set('sub_type', null);
            _set('mod_second_type', null);
          },
        ),
        _select(
          'sub_type',
          '次类别',
          _options!.secondary(category, _draft.values['pri_type']),
        ),
        if (category == 'pe' && _draft.values['pri_type'] == 2)
          _select(
            'mod_second_type',
            '模组分类',
            ResourceOptions.maps(
              (_options!.raw['mod_second_type'] as Map?)?['2'],
            ),
          ),
        _select(
          'price_type',
          '定价方式',
          _options!.prices.where((p) => p['id'] != 'gift').toList(),
          afterChange: () {
            if (_draft.text('price_type') == 'free') {
              _set('price', 0);
              _controller('price').text = '0';
            }
          },
        ),
        if (_draft.text('price_type') == 'diamond' &&
            _priceSettings?.ranked == true)
          _rankSelector('price_rank', '官方平台定价档位', 'price')
        else if (_draft.values['price_type'] != 'free')
          _field('price', '官方平台价格', number: true),
        if (_priceSettings?.hasChannel == true &&
            [
              'diamond',
              'unrestricted_diamond',
            ].contains(_draft.text('price_type')))
          if (_draft.text('price_type') == 'diamond' &&
              _priceSettings?.ranked == true)
            _rankSelector(
              'channel_price_rank',
              '渠道平台定价档位',
              'other_channel_price',
            )
          else
            _field('other_channel_price', '渠道平台价格', number: true),
        if (category == 'pe')
          _select(
            'mod_version',
            '适配手机版版本',
            _options!
                .strings('mod_version')
                .map((v) => {'id': v, 'title': v})
                .toList(),
          ),
        if (category == 'comp')
          _select(
            'available_scope',
            '运行范围',
            ResourceOptions.maps(_options!.raw['available_scope']),
          ),
      ]),
      if (category == 'comp') ...[
        const Text('适用游戏版本'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _options!.strings('mc_version').map((v) {
            final selected = _draft.strings('mc_version');
            return OreButton(
              variant: selected.contains(v)
                  ? OreButtonVariant.primary
                  : OreButtonVariant.secondary,
              onPressed: _busy
                  ? null
                  : () {
                      selected.contains(v)
                          ? selected.remove(v)
                          : selected.add(v);
                      _set('mc_version', selected);
                    },
              child: Text(v),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
      _field('brief', '简介', lines: 3),
      _fieldGrid([
        _field('update_summary', '更新纪要', lines: 3),
        _field('current_change_log', '更新日志', lines: 3),
      ]),
    ]);
  }

  Widget _descriptionSection() =>
      _section('资源介绍', [_descriptionContent('info')]);

  Widget _descriptionContent(String field) {
    final editing = _editingDescriptions.contains(field);
    final content = _draft.text(field);
    final theme = OreTheme.of(context);
    return Column(
      key: ValueKey('description-$field'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OreButton(
              size: OreButtonSize.sm,
              variant: editing
                  ? OreButtonVariant.secondary
                  : OreButtonVariant.primary,
              onPressed: _busy
                  ? null
                  : () => setState(() => _editingDescriptions.remove(field)),
              child: const Text('排版效果'),
            ),
            OreButton(
              size: OreButtonSize.sm,
              variant: editing
                  ? OreButtonVariant.primary
                  : OreButtonVariant.secondary,
              onPressed: _busy
                  ? null
                  : () => setState(() => _editingDescriptions.add(field)),
              child: const Text('编辑 HTML'),
            ),
            OreButton(
              size: OreButtonSize.sm,
              onPressed: _busy ? null : () => _insertImage(field),
              child: const Text('插入图片'),
            ),
            if (editing)
              OreButton(
                size: OreButtonSize.sm,
                onPressed: _busy
                    ? null
                    : () {
                        final c = _controller(field);
                        c.text = c.text
                            .split('\n')
                            .map(
                              (line) =>
                                  '<p>${const HtmlEscape().convert(line)}</p>',
                            )
                            .join();
                        _set(field, c.text);
                      },
                child: const Text('将纯文本转为段落'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (editing)
          _field(field, '详情内容（HTML 源码）', lines: 12)
        else if (content.trim().isEmpty)
          Text(
            '尚未填写详情内容，点击“编辑 HTML”或插入图片开始编写。',
            style: TextStyle(color: theme.colors.textMuted),
          )
        else
          OreSelectionArea(
            child: HtmlWidget(
              content,
              onLoadingBuilder: (_, _, _) => const OreLoadingIndicator(),
              key: ValueKey('description-preview-$field'),
              textStyle: theme.typography.body.copyWith(
                color: theme.colors.textPrimary,
                height: 1.5,
              ),
              onTapUrl: (_) async => false,
            ),
          ),
      ],
    );
  }

  Widget _multiSelect(
    String key,
    String title,
    List<Map<String, dynamic>> choices,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: choices.map((choice) {
          final selected = List<dynamic>.from(_draft.get(key) as List? ?? []);
          return OreButton(
            size: OreButtonSize.sm,
            variant: selected.contains(choice['id'])
                ? OreButtonVariant.primary
                : OreButtonVariant.secondary,
            onPressed: _busy
                ? null
                : () {
                    selected.contains(choice['id'])
                        ? selected.remove(choice['id'])
                        : selected.add(choice['id']);
                    _set(key, selected);
                  },
            child: Text('${choice['title']}'),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
    ],
  );

  Future<void> _uploadImageField(
    String key,
    String label, {
    int? width,
    int? height,
    bool urlOnly = false,
  }) async {
    final file = await _upload(
      label: label,
      fileType: 'image',
      extensions: ['png', 'jpg', 'jpeg'],
      width: width,
      height: height,
      maxBytes: 10 * 1024 * 1024,
    );
    if (file != null && mounted) {
      _set(key, urlOnly ? file.url : file.signedValue);
    }
  }

  Widget _imageField(
    String key,
    String label, {
    int? width,
    int? height,
    bool urlOnly = false,
  }) {
    final url = _imageUrl(_draft.get(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        if (url != null)
          Image.network(
            url,
            width: 200,
            height: 110,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text('图片已保留，预览暂不可用'),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _uploadImageField(
                      key,
                      label,
                      width: width,
                      height: height,
                      urlOnly: urlOnly,
                    ),
              child: Text(url == null ? '上传图片' : '替换图片'),
            ),
            if (url != null)
              OutlinedButton(
                onPressed: _busy ? null : () => _set(key, ''),
                child: const Text('移除'),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _uploadVideo(bool cover) async {
    final file = await _upload(
      label: cover ? '视频封面' : '展示视频',
      fileType: cover ? 'image' : 'video',
      extensions: cover ? ['png', 'jpg', 'jpeg'] : ['mp4'],
      width: cover ? 992 : null,
      height: cover ? 558 : null,
      maxBytes: (cover ? 10 : 50) * 1024 * 1024,
    );
    if (file == null || !mounted) return;
    final entry =
        _draft.entries('video_info_list').firstOrNull ?? <String, dynamic>{};
    entry[cover ? 'cover' : 'url'] = file.signedValue;
    if (!cover) entry['size'] = jsonDecode(file.body)['fsize'];
    _set('video_info_list', [entry]);
  }

  Widget _videoSection() {
    final video = _draft.entries('video_info_list').firstOrNull;
    return _section('展示视频与推广图', [
      const Text('视频要求：H.264 编码的 MP4，16:9，最大 50 MB。封面要求：992 × 558 像素。'),
      const SizedBox(height: 12),
      if (video?['url'] != null) const Text('已添加展示视频'),
      if (_imageUrl(video?['cover']) case final String url)
        Image.network(
          url,
          width: 200,
          height: 112,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('视频封面预览暂不可用'),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : () => _uploadVideo(false),
            child: const Text('上传 / 替换视频'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _uploadVideo(true),
            child: const Text('上传 / 替换视频封面'),
          ),
          if (video != null)
            OutlinedButton(
              onPressed: _busy ? null : () => _set('video_info_list', []),
              child: const Text('移除视频'),
            ),
        ],
      ),
      const SizedBox(height: 20),
      _imageField('banner_pic', '资源中心首页轮播推广图', urlOnly: true),
    ]);
  }

  Future<void> _addRequirement(String key, String category) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ResourceRequirementPicker(
          category: category,
          apiFactory: widget.apiFactory,
        ),
      ),
    );
    if (result != null && mounted) {
      if (category == 'pe') {
        _set(key, [result]);
        return;
      }
      final items = _draft.entries(key);
      if (!items.any((e) => e['item_id'] == result['item_id'])) {
        items.add(result);
        _set(key, items);
      }
    }
  }

  Widget _requirements(String key, String category) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('前置模组'),
      for (final item in _draft.entries(key))
        Row(
          children: [
            Expanded(child: Text('${item['item_name']} · ${item['item_id']}')),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _set(
                      key,
                      _draft.entries(key)
                        ..removeWhere((e) => e['item_id'] == item['item_id']),
                    ),
              child: const Text('移除'),
            ),
          ],
        ),
      OutlinedButton(
        onPressed: _busy ? null : () => _addRequirement(key, category),
        child: const Text('添加前置模组'),
      ),
      const SizedBox(height: 16),
    ],
  );

  Widget _extraSection() {
    final category = widget.category.value;
    final subtype = _options!
        .secondary(category, _draft.get('pri_type'))
        .where((e) => e['id'] == _draft.get('sub_type'))
        .firstOrNull;
    return _section('作品属性', [
      if (ResourceOptions.maps(subtype?['body_type']).isNotEmpty)
        _select(
          'body_type',
          '皮肤体型',
          ResourceOptions.maps(subtype?['body_type']),
        ),
      if (category == 'pe') ...[
        _multiSelect('label_type_list', '玩法与主题标签', [
          ...ResourceOptions.maps((_options!.raw['label_type'] as Map?)?['1']),
          ...ResourceOptions.maps((_options!.raw['label_type'] as Map?)?['2']),
        ]),
        const Text('自定义标签'),
        Wrap(
          spacing: 8,
          children: _draft
              .entries('tags')
              .map(
                (tag) => OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _set(
                          'tags',
                          _draft.entries('tags')
                            ..removeWhere((e) => e['name'] == tag['name']),
                        ),
                  child: Text('${tag['name']} ×'),
                ),
              )
              .toList(),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controllers.putIfAbsent(
                  '_newTag',
                  TextEditingController.new,
                ),
                decoration: const InputDecoration(labelText: '添加一个标签'),
              ),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      final value = _controllers['_newTag']!.text.trim();
                      if (value.isNotEmpty &&
                          !_draft
                              .entries('tags')
                              .any((t) => t['name'] == value)) {
                        _set('tags', [
                          ..._draft.entries('tags'),
                          {'name': value, 'source': 0},
                        ]);
                        _controllers['_newTag']!.clear();
                      }
                    },
              child: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      if (category == 'comp')
        _multiSelect(
          'tag',
          '作品标签',
          ResourceOptions.maps((_options!.raw['tag'] as Map?)?['comp']),
        ),
      _requirements(
        category == 'pe' ? 'prerequisite_items' : 'requirement',
        category,
      ),
      if (_draft.get('is_original') != true)
        _imageField('corp_proof_image', '非原创作品授权证明'),
    ]);
  }

  Future<void> _selectDlc() async {
    final selected = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ResourceRequirementPicker(
          category: 'pe',
          dlc: true,
          apiFactory: widget.apiFactory,
        ),
      ),
    );
    if (selected == null || !mounted || _api == null) return;
    if (selected['item_id'] == _id) {
      setState(() => _error = '不能关联作品自身');
      return;
    }
    try {
      if (_draft.text('dlc_info.dlc_type') == 'master') {
        final slaves = _draft.entries('dlc_info.slave_list');
        if (slaves.any((e) => e['item_id'] == selected['item_id'])) return;
        if (slaves.length >= 20) throw StateError('DLC 副包数量不能超过 20 个');
        _set('dlc_info.slave_list', [...slaves, selected]);
      } else {
        setState(() => _saving = true);
        final master = await _api!.fetchResourceDetail(
          resourceCategory: 'pe',
          itemId: selected['item_id'],
        );
        if (!mounted) return;
        final slaves = ResourceOptions.maps(
          master.raw['dlc_info']?['slave_list'],
        )..removeWhere((e) => e['item_id'] == _id);
        if (slaves.length >= 20) throw StateError('该主包已达到 20 个副包上限');
        _set('dlc_info.master', selected);
        _set('dlc_info.slave_list', [
          ...slaves,
          {'item_id': _id ?? '', 'item_name': _draft.text('item_name')},
        ]);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dlcSection() {
    final enabled = _draft.get('dlc_info.dlc_switch') == true;
    final type = _draft.text('dlc_info.dlc_type');
    final originalType = _originalDlcType;
    final locked = originalType != null && originalType != 'off';
    return _section('DLC 关联', [
      _toggle('dlc_info.dlc_switch', '启用主包 / 副包关联'),
      if (enabled) ...[
        if (!locked)
          _select(
            'dlc_info.dlc_type',
            '本作品的角色',
            const [
              {'id': 'master', 'title': '主包'},
              {'id': 'slave', 'title': '副包'},
            ],
            afterChange: () {
              _set('dlc_info.master', {});
              _set('dlc_info.slave_list', []);
            },
          )
        else
          Text(type == 'master' ? '本作品为主包' : '本作品为副包'),
        if (type == 'slave')
          Text('主包：${_draft.get('dlc_info.master.item_name') ?? '未选择'}'),
        for (final item in _draft.entries('dlc_info.slave_list'))
          Row(
            children: [
              Expanded(
                child: Text('副包：${item['item_name']} · ${item['item_id']}'),
              ),
              if (type == 'master')
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _set(
                          'dlc_info.slave_list',
                          _draft.entries('dlc_info.slave_list')..removeWhere(
                            (e) => e['item_id'] == item['item_id'],
                          ),
                        ),
                  child: const Text('移除'),
                ),
            ],
          ),
        if (['master', 'slave'].contains(type))
          OutlinedButton(
            onPressed: _busy ? null : _selectDlc,
            child: Text(type == 'master' ? '关联副包' : '选择主包'),
          ),
      ],
    ]);
  }

  Widget _syncSection() => _section('同步 PC 作品', [
    _toggle('sync_pc_flag', '同时维护 PC 版本'),
    if (_draft.get('sync_pc_flag') == true) ...[
      _field('sync_item_info.item_name', 'PC 作品名称'),
      _select(
        'sync_item_info.pri_type',
        'PC 主类别',
        _options!.primary('comp'),
        afterChange: () => _set('sync_item_info.sub_type', null),
      ),
      _select(
        'sync_item_info.sub_type',
        'PC 次类别',
        _options!.secondary('comp', _draft.get('sync_item_info.pri_type')),
      ),
      _select(
        'sync_item_info.available_scope',
        'PC 运行范围',
        ResourceOptions.maps(_options!.raw['available_scope']),
      ),
      _field('sync_item_info.brief', 'PC 简介', lines: 3),
      const Text('PC 详情介绍'),
      const SizedBox(height: 8),
      _descriptionContent('sync_item_info.info'),
      const SizedBox(height: 16),
      _requirements('sync_item_info.requirement', 'comp'),
      _channelSection(category: 'comp', field: 'sync_item_info.channel'),
      _toggle('sync_item_info.weak_offline', 'PC 作品弱下架'),
      if (_draft.get('sync_item_info.weak_offline') == true)
        _field('sync_item_info.weak_offline_reason', 'PC 弱下架原因', lines: 3),
    ],
  ]);

  Widget _actions() => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      ElevatedButton.icon(
        onPressed: _busy || _saveUncertain ? null : () => _save(review: true),
        icon: const Icon(Icons.fact_check),
        label: const Text('保存并提交审核'),
      ),
      OutlinedButton.icon(
        onPressed: _busy || _saveUncertain ? null : _save,
        icon: const Icon(Icons.save),
        label: Text(_saving ? '保存中…' : '保存到平台'),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _saveLocal,
        child: const Text('保存本机草稿'),
      ),
      OutlinedButton(onPressed: _busy ? null : _back, child: const Text('返回')),
    ],
  );

  Future<void> _back() async {
    if (_busy) return;
    if (_dirty &&
        !await _confirm('离开编辑', '尚有未保存的修改。可先取消并保存本机草稿。', confirm: '放弃修改')) {
      return;
    }
    if (mounted) Navigator.of(context).pop(_changed);
  }

  Widget _publicationSection() => _section('发布设置', [
    _toggle('is_original', '原创作品'),
    _toggle('force_encrypt', '资源加密'),
    _toggle('searchable', '允许搜索'),
    _toggle('version_compatible_enable', '开启版本兼容'),
    _toggle('anti_cheat_enable', '开启反作弊'),
    if (_permissions['can_set_item_update_push'] == true)
      _toggle('item_update_push', '向玩家推送更新'),
    if (_permissions['official'] == true)
      _field('pre_review_video', 'X19 外观界面视频播放信息', lines: 3),
    _toggle('weak_offline', '弱下架（更新并审核后生效）'),
    if (_draft.get('weak_offline') == true)
      _field('weak_offline_reason', '弱下架原因', lines: 3),
  ]);

  List<Widget> _feedbackSections() => [
    if (_error != null)
      _section('需要处理', [
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (_options == null)
          OutlinedButton(onPressed: _bootstrap, child: const Text('重试')),
      ]),
    if (_notice != null)
      Padding(padding: const EdgeInsets.all(12), child: Text(_notice!)),
    if (_localDraft != null)
      _section('本机草稿', [
        const Text('发现上次未完成的草稿。'),
        OutlinedButton(onPressed: _restoreLocal, child: const Text('恢复草稿')),
      ]),
  ];

  List<Widget> _linkedSections() => [
    if (widget.category.value == 'pe' &&
        (_permissions['can_sync_pc'] == true ||
            _draft.get('sync_pc_flag') == true))
      _syncSection(),
    if (widget.category.value == 'pe' && _permissions['can_set_dlc'] == true)
      _dlcSection(),
  ];

  Widget _editorPane(
    String name,
    ScrollController controller,
    List<Widget> sections,
  ) => Scrollbar(
    key: ValueKey('editor-pane-$name'),
    controller: controller,
    child: ListView.separated(
      controller: controller,
      primary: false,
      padding: const EdgeInsets.only(right: 24, bottom: 16),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, index) => sections[index],
    ),
  );

  Widget _editorBody() => LayoutBuilder(
    builder: (context, constraints) {
      final width =
          constraints.maxWidth /
          max(1, MediaQuery.textScalerOf(context).scale(14) / 14);
      final basicSections = _feedbackSections();
      List<Widget>? mediaSections;
      List<Widget>? detailSections;
      if (_options != null) {
        final basic = _basicSection();
        final media = [_packageSection(), _channelSection(), _videoSection()];
        final details = _descriptionSection();
        final attributes = _extraSection();
        final linked = _linkedSections();
        final publication = _publicationSection();
        if (width < 1000) {
          basicSections.addAll([
            basic,
            ...media,
            attributes,
            ...linked,
            details,
            publication,
          ]);
        } else if (width < 1600) {
          basicSections.addAll([basic, attributes, publication, ...linked]);
          mediaSections = [media[0], media[1], details, media[2]];
        } else {
          basicSections.addAll([basic, attributes]);
          mediaSections = media;
          detailSections = [details, publication, ...linked];
        }
      }
      // Keep the first pane in the same element position while resizing so its
      // controller and focused field are never attached to two scroll views.
      return Padding(
        padding: EdgeInsets.all(width < 1000 ? 12 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _editorPane('basic', _scroll, basicSections)),
            if (mediaSections != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _editorPane('media', _mediaScroll, mediaSections),
              ),
            ],
            if (detailSections != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _editorPane('details', _detailsScroll, detailSections),
              ),
            ],
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) _back();
    },
    child: Scaffold(
      appBar: buildOreAppBar(
        context,
        title: _id == null ? widget.category.uploadLabel : '编辑资源',
      ),
      bottomNavigationBar: _loading || _options == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_uploadLabel != null) ...[
                      Text(
                        _uploadLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      OreProgressBar(value: _progress),
                      const SizedBox(height: 12),
                    ],
                    _actions(),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: OreLoadingIndicator())
          : _editorBody(),
    ),
  );
}

class ResourceRequirementPicker extends StatefulWidget {
  const ResourceRequirementPicker({
    super.key,
    required this.category,
    this.apiFactory,
    this.dlc = false,
  });
  final bool dlc;
  final String category;
  final McDevApi Function()? apiFactory;
  @override
  State<ResourceRequirementPicker> createState() =>
      _ResourceRequirementPickerState();
}

class _ResourceRequirementPickerState extends State<ResourceRequirementPicker> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    McDevApi? api;
    try {
      final cookie = widget.apiFactory == null
          ? await LoginCookieHelper.buildCookieHeader()
          : '';
      api =
          widget.apiFactory?.call() ??
          McDevApi(cookie: cookie, category: widget.category);
      final items = widget.dlc
          ? await api.searchDlcResources(_query.text.trim())
          : await api.searchRequirements(widget.category, _query.text.trim());
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      api?.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: buildOreAppBar(
      context,
      title: widget.dlc ? '选择 DLC 关联作品' : '选择前置模组',
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('返回'),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  decoration: const InputDecoration(labelText: '模组名称 / ID'),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _loading ? null : _search,
                child: const Text('搜索'),
              ),
            ],
          ),
          if (_error != null) Text(_error!),
          if (_loading) const OreProgressBar(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final item = _items[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OreButton(
                    fullWidth: true,
                    onPressed: () => Navigator.pop(context, {
                      'item_id': item['item_id'].toString(),
                      'item_name': item['item_name'],
                    }),
                    child: Text('${item['item_name']} · ${item['item_id']}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
