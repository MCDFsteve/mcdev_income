part of '../main.dart';

class ResourcePriceDialog extends StatefulWidget {
  const ResourcePriceDialog({
    super.key,
    required this.item,
    required this.settings,
    required this.options,
  });
  final ResourceItem item;
  final ResourcePriceSettings settings;
  final ResourceOptions options;
  @override
  State<ResourcePriceDialog> createState() => _ResourcePriceDialogState();
}

class _ResourcePriceDialogState extends State<ResourcePriceDialog> {
  late final _draft = ResourceDraft(
    category: widget.item.category,
    source: widget.item.raw,
  );
  late final _price = TextEditingController(text: _draft.text('price'));
  late final _channel = TextEditingController(
    text: _draft.text('other_channel_price'),
  );
  String? _error;
  bool get _ranked =>
      widget.settings.ranked && widget.item.priceType == 'diamond';
  bool get _hasChannel =>
      widget.settings.hasChannel &&
      ['diamond', 'unrestricted_diamond'].contains(widget.item.priceType);

  @override
  void dispose() {
    _price.dispose();
    _channel.dispose();
    super.dispose();
  }

  Widget _rank(String key, String label, String priceKey) {
    final options = widget.settings.choices(
      current: int.tryParse('${widget.item.raw[key]}'),
    );
    final current = _draft.get(key);
    return DropdownButtonFormField<int>(
      value: options.any((e) => e['id'] == current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options
          .map(
            (e) =>
                DropdownMenuItem<int>(value: e['id'], child: Text(e['title'])),
          )
          .toList(),
      onChanged: (value) => setState(() {
        _draft.set(key, value);
        _draft.set(priceKey, widget.settings.ranks[value!]['price']);
      }),
    );
  }

  void _accept() {
    if (!_ranked) {
      _draft.set('price', _price.text);
      if (_hasChannel) _draft.set('other_channel_price', _channel.text);
    }
    final errors = widget.settings.validate(_draft);
    final rule = widget.options.prices
        .where((r) => r['id'] == widget.item.priceType)
        .firstOrNull;
    final price = int.tryParse(_draft.text('price'));
    final min = (rule?['min'] as num?)?.toInt() ?? 0;
    final max = (rule?['max'] as num?)?.toInt();
    final step = (rule?['step'] as num?)?.toInt() ?? 1;
    if (price == null ||
        price < min ||
        (max != null && price > max) ||
        (step > 0 && price % step != 0)) {
      errors.add('价格不符合平台规则：最低 $min，步进 $step${max == null ? '' : '，最高 $max'}');
    }
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'price_type': widget.item.priceType,
      'price': price,
      if (_ranked) 'price_rank': _draft.get('price_rank'),
      if (_hasChannel)
        'other_channel_price': int.parse(_draft.text('other_channel_price')),
      if (_hasChannel && _ranked)
        'channel_price_rank': _draft.get('channel_price_rank'),
    });
  }

  @override
  Widget build(BuildContext context) => ResourceDialog(
    title: const Text('调整价格'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.name),
            const SizedBox(height: 16),
            if (_ranked)
              _rank('price_rank', '官方平台定价档位', 'price')
            else
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:
                      '官方平台价格（${widget.item.priceType == 'point' ? '绿宝石' : '钻石'}）',
                ),
              ),
            if (_hasChannel) ...[
              const SizedBox(height: 16),
              if (_ranked)
                _rank('channel_price_rank', '渠道平台定价档位', 'other_channel_price')
              else
                TextField(
                  controller: _channel,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '渠道平台价格'),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      ElevatedButton(onPressed: _accept, child: const Text('确认价格')),
    ],
  );
}
