part of mcdev_income_app;

class _ParsedRate {
  const _ParsedRate(this.value, {this.error, this.isDefault = false});

  final double value;
  final String? error;
  final bool isDefault;

  bool get isValid => error == null;
}

class _ShareResult {
  const _ShareResult(this.netValue, {this.error});

  final double netValue;
  final String? error;

  bool get isValid => error == null;
}

class _RangePickerPanel extends StatefulWidget {
  const _RangePickerPanel({
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_RangePickerPanel> createState() => _RangePickerPanelState();
}

class _RangePickerPanelState extends State<_RangePickerPanel> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  final _format = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.initialStart;
    _rangeEnd = widget.initialEnd;
  }

  void _onDateTapped(DateTime date) {
    if (_rangeStart == null || _rangeEnd != null) {
      setState(() {
        _rangeStart = date;
        _rangeEnd = null;
      });
      return;
    }
    var start = _rangeStart!;
    var end = date;
    if (end.isBefore(start)) {
      final temp = start;
      start = end;
      end = temp;
    }
    Navigator.of(context).pop(DateTimeRange(start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    final startLabel = _rangeStart == null
        ? '未选'
        : _format.format(_rangeStart!);
    final endLabel = _rangeEnd == null ? '未选' : _format.format(_rangeEnd!);
    final initialDate = _rangeEnd ?? _rangeStart ?? DateTime.now();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '选择时间范围',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('开始: $startLabel')),
                Expanded(child: Text('结束: $endLabel')),
              ],
            ),
            const SizedBox(height: 8),
            CalendarDatePicker(
              initialDate: initialDate,
              firstDate: DateTime(2020, 1, 1),
              lastDate: DateTime(DateTime.now().year + 1, 12, 31),
              onDateChanged: _onDateTapped,
            ),
            const SizedBox(height: 4),
            Text('点击起止日期后自动查询', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
