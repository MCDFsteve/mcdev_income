part of '../main.dart';

class ResourceDialog extends StatelessWidget {
  const ResourceDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) =>
      OreAlertDialog(title: title, content: content, actions: actions);
}

class ResourceScheduleDialog extends StatefulWidget {
  const ResourceScheduleDialog({super.key});
  @override
  State<ResourceScheduleDialog> createState() => _ResourceScheduleDialogState();
}

class _ResourceScheduleDialogState extends State<ResourceScheduleDialog> {
  late final _value = TextEditingController(
    text:
        '${DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)))} 10:00',
  );
  String? _error;
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _confirm() {
    try {
      final date = DateFormat(
        'yyyy-MM-dd HH:mm',
      ).parseStrict(_value.text.trim());
      if (!date.isAfter(DateTime.now())) throw const FormatException();
      Navigator.pop(context, DateFormat('yyyy-MM-dd HH:mm:00').format(date));
    } catch (_) {
      setState(() => _error = '请按 年-月-日 时:分 填写未来时间，例如 2027-01-01 10:00');
    }
  }

  @override
  Widget build(BuildContext context) => ResourceDialog(
    title: const Text('定时上架'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _value,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(labelText: '上架时间（本地时间，24 小时制）'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      ElevatedButton(onPressed: _confirm, child: const Text('确认时间')),
    ],
  );
}
