part of '../main.dart';

class MailboxButton extends StatefulWidget {
  const MailboxButton({super.key, this.refreshToken, this.apiFactory});
  final Object? refreshToken;
  final McDevApi Function()? apiFactory;
  @override
  State<MailboxButton> createState() => _MailboxButtonState();
}

class _MailboxButtonState extends State<MailboxButton>
    with WidgetsBindingObserver {
  int? _count;
  int _request = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MailboxButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    McDevApi? api;
    try {
      if (widget.apiFactory != null) {
        api = widget.apiFactory!();
      } else {
        final cookie = await LoginCookieHelper.buildCookieHeader();
        if (cookie.isEmpty) {
          if (mounted && request == _request) setState(() => _count = null);
          return;
        }
        api = McDevApi(cookie: cookie, category: 'pe');
      }
      final count = await api.fetchUnreadMailCount();
      if (mounted && request == _request) setState(() => _count = count);
    } catch (_) {
      if (mounted && request == _request) setState(() => _count = null);
    } finally {
      api?.close();
    }
  }

  Future<void> _open() async {
    await showOreDialog<void>(
      context: context,
      builder: (_) =>
          MailboxPage(apiFactory: widget.apiFactory, onRead: _refresh),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 58,
    height: 48,
    child: Stack(
      children: [
        Positioned.fill(
          child: OreIconButton(
            key: const ValueKey('mailbox-entry'),
            icon: const Icon(Icons.mail_outline),
            color: Colors.white,
            tooltip: _count != null && _count! > 0 ? '邮件（$_count 封未读）' : '邮件',
            onPressed: _open,
          ),
        ),
        if (_count != null && _count! > 0)
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: Text(
                _count! > 99 ? '99+' : '$_count',
                style: const TextStyle(
                  color: Color(0xffffd45a),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
