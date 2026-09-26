part of mcdev_income_app;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _agree = true;
  bool _rememberPassword = true;
  bool _loading = false;
  String? _error;
  LoginSession? _session;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    final session = await LoginCookieHelper.readLoginSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = session;
      if (session != null) {
        _emailController.text = session.email;
      }
    });
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty) {
      setState(() => _error = '请输入账号');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = '账号格式错误');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    if (!_agree) {
      setState(() => _error = '您需要同意相关条款才能登录');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await LoginCookieHelper.loginWithEmail(
        email: email,
        password: password,
        rememberPassword: _rememberPassword,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _session = session;
      });
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _clearLogin() async {
    await LoginCookieHelper.clearLogin();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
      _passwordController.clear();
      _error = null;
    });
  }

  String _sessionLabel() {
    final session = _session;
    if (session == null) {
      return '未保存';
    }
    final expires = DateFormat('yyyy-MM-dd HH:mm').format(session.expiresAt);
    final kind = session.kind == LoginSessionKind.domestic ? '国内网易账号' : '海外账号';
    return '${session.email} · $kind · 有效至 $expires';
  }

  Widget _buildLoginCard(BuildContext context) {
    final theme = Theme.of(context);
    final actionWidth = OreTokens.controlHeightMd * 4.5;
    return OreCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('邮箱账号登录', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            enabled: !_loading,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '账号',
              prefixIcon: Icon(Icons.alternate_email),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            enabled: !_loading,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _loading ? null : _login(),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _agree,
            onChanged: _loading
                ? null
                : (value) => setState(() => _agree = value ?? false),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('我已经同意《隐私协议》和《用户协议》'),
          ),
          CheckboxListTile(
            value: _rememberPassword,
            onChanged: _loading
                ? null
                : (value) => setState(() => _rememberPassword = value ?? false),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('保存密码用于自动刷新凭证'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _loading ? null : _login,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('登录'),
                width: actionWidth,
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _clearLogin,
                icon: const Icon(Icons.logout),
                label: const Text('清除'),
                width: actionWidth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context) {
    final theme = Theme.of(context);
    return OreCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('凭证状态', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(_sessionLabel(), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildOreAppBar(context, title: '登录'),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            OreStrip(
              tone: OreStripTone.dark,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '开发者内容管理工具',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            _buildSessionCard(context),
            _buildLoginCard(context),
          ],
        ),
      ),
    );
  }
}
