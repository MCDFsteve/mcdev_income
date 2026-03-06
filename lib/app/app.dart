part of mcdev_income_app;

class McDevIncomeApp extends StatefulWidget {
  const McDevIncomeApp({super.key});

  @override
  State<McDevIncomeApp> createState() => _McDevIncomeAppState();
}

class _McDevIncomeAppState extends State<McDevIncomeApp> {
  final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final stored = await ThemeModeStore.load();
    if (!mounted) {
      return;
    }
    _themeModeNotifier.value = stored;
  }

  @override
  void dispose() {
    _themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeController(
      notifier: _themeModeNotifier,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeModeNotifier,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'MC开发者收益助手',
            themeMode: themeMode,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
              scaffoldBackgroundColor: OreColors.light().background,
              canvasColor: OreColors.light().background,
              useMaterial3: true,
              extensions: <ThemeExtension<dynamic>>[
                OreThemeData.light(),
              ],
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.dark,
              ),
              brightness: Brightness.dark,
              scaffoldBackgroundColor: OreColors.dark().background,
              canvasColor: OreColors.dark().background,
              useMaterial3: true,
              extensions: <ThemeExtension<dynamic>>[
                OreThemeData.dark(),
              ],
            ),
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

class AppThemeController extends InheritedNotifier<ValueNotifier<ThemeMode>> {
  const AppThemeController({
    super.key,
    required ValueNotifier<ThemeMode> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<ThemeMode> of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<AppThemeController>();
    assert(widget != null, 'AppThemeController not found in context.');
    return widget!.notifier!;
  }
}

class ThemeModeStore {
  const ThemeModeStore._();

  static const _key = 'theme_mode';

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
    }
    return ThemeMode.system;
  }

  static String _serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key));
  }

  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _serialize(mode));
  }
}
