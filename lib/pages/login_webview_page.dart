part of mcdev_income_app;

class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key});

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String _status = '请在此页面登录，并进入收益页面后点击“完成登录”。';

  Future<void> _syncCookies() async {
    final cookieMap = await LoginCookieHelper.readCookies(allowCache: false);
    if (!mounted) {
      return;
    }

    if (cookieMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未读取到 Cookie，请确认已登录并打开收益页面。')),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildOreAppBar(
        context,
        title: 'WebView 登录',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
          TextButton(onPressed: _syncCookies, child: const Text('完成登录')),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialSettings: InAppWebViewSettings(
                sharedCookiesEnabled: true,
                incognito: false,
                cacheEnabled: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri('https://mcdev.webapp.163.com/'),
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (_, __) {
                setState(() {
                  _loading = true;
                });
              },
              onLoadStop: (_, __) {
                setState(() {
                  _loading = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
