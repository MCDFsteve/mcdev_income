import 'package:flutter/services.dart';
import '../ui/ore_material.dart';
import 'window_title_bar.dart';
import 'game_chrome_backend.dart';

Future<void> runGameChrome(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final backend = createGameChromeBackend();
  final title = arguments.length > 2 && arguments[2].isNotEmpty
      ? arguments[2]
      : '我的世界测试';
  if (backend.nativeMenus) {
    WidgetsBinding.instance.platformMenuDelegate = DefaultPlatformMenuDelegate(
      channel: gameMenuChannel,
    );
  }
  await backend.initialize(title);
  runApp(
    GameChromeApp(
      backend: backend,
      gameVersion: arguments.isNotEmpty ? arguments.first : '',
      subtitle: arguments
          .take(2)
          .where((value) => value.isNotEmpty)
          .join(' · '),
      displayName: arguments.length > 2 && arguments[2].isNotEmpty
          ? arguments[2]
          : '我的世界测试',
    ),
  );
}

const gameMenuChannel = MethodChannel('mcdev_income/game_menu');

/// Keep menu labels and shortcuts in Flutter, but execute their actions in the
/// owning Cocoa process after AppKit finishes menu tracking.
class GameMenuItem extends PlatformMenuItem {
  GameMenuItem({
    required super.label,
    required this.action,
    this.argument,
    super.shortcut,
    WindowController bridge = const DesktopWindowBridge(),
  }) : super(onSelected: () => bridge.invoke(action, argument));

  final String action;
  final String? argument;

  @override
  Iterable<Map<String, Object?>> toChannelRepresentation(
    PlatformMenuDelegate delegate, {
    required MenuItemSerializableIdGenerator getId,
  }) => [
    {
      ...PlatformMenuItem.serialize(this, delegate, getId),
      'action': action,
      if (argument != null) 'argument': argument,
    },
  ];
}

List<PlatformMenuItem> gamePlatformMenus(
  WindowController bridge, {
  String displayName = '我的世界测试',
  String gameVersion = '',
}) => [
  PlatformMenu(
    label: displayName,
    menus: [
      GameMenuItem(label: '关于$displayName', action: 'about', bridge: bridge),
      PlatformMenuItemGroup(
        members: [
          GameMenuItem(
            label: '隐藏$displayName',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyH,
              meta: true,
            ),
            action: 'hide',
            bridge: bridge,
          ),
          GameMenuItem(label: '显示全部', action: 'showAll', bridge: bridge),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          GameMenuItem(
            label: '退出测试游戏',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyQ,
              meta: true,
            ),
            action: 'close',
            bridge: bridge,
          ),
        ],
      ),
    ],
  ),
  PlatformMenu(
    label: '游戏',
    menus: [
      for (final (label, key) in const [
        ('暂停 / 返回', 'escape'),
        ('物品栏', 'inventory'),
        ('聊天', 'chat'),
        ('输入命令', 'command'),
        ('切换视角', 'F5'),
        ('显示 / 隐藏界面', 'F1'),
      ])
        GameMenuItem(
          label: label,
          action: 'sendKey',
          argument: key,
          bridge: bridge,
        ),
    ],
  ),
  PlatformMenu(
    label: '功能键',
    menus: [
      // Default bindings verified in the local NetEase 3.8 and 3.10 binaries.
      // Keep the physical key as the argument; debug actions depend on the
      // active game context. Evidence: docs/game-function-keys.md.
      for (final (key, label) in [
        ('F1', '显示 / 隐藏界面（F1）'),
        ('F2', '截图（F2）'),
        ('F3', '调试信息下一页（F3）'),
        ('F4', '调试信息上一页（F4）'),
        ('F5', '切换视角（F5）'),
        ('F6', '穿墙飞行（F6，调试）'),
        ('F7', '未发现默认单键功能（F7）'),
        ('F8', '显示 / 隐藏纸娃娃（F8）'),
        ('F9', '模拟挂起 / 恢复（F9，调试）'),
        ('F10', '录像 / 显示隐藏提示（F10）'),
        (
          'F11',
          switch (gameVersion) {
            '3.10.0.420447' => '渲染帧捕获（F11，需 RenderDoc）',
            '3.8.0.313229' => '未发现默认单键功能（F11）',
            _ => '默认功能待核对（F11）',
          },
        ),
        ('F12', '播放回放（F12）'),
      ])
        GameMenuItem(
          label: label,
          action: 'sendKey',
          argument: key,
          bridge: bridge,
        ),
    ],
  ),
  PlatformMenu(
    label: '窗口',
    menus: [
      GameMenuItem(
        label: '最小化',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
        action: 'minimize',
        bridge: bridge,
      ),
      GameMenuItem(label: '缩放', action: 'zoom', bridge: bridge),
      GameMenuItem(
        label: '切换全屏',
        shortcut: const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          control: true,
        ),
        action: 'fullscreen',
        bridge: bridge,
      ),
    ],
  ),
];

class GameChromeApp extends StatelessWidget {
  const GameChromeApp({
    super.key,
    this.subtitle = '',
    this.displayName = '我的世界测试',
    this.gameVersion = '',
    this.backend,
  });
  final String subtitle;
  final String displayName;
  final String gameVersion;
  final GameChromeBackend? backend;

  @override
  Widget build(BuildContext context) {
    final platform = backend ?? createGameChromeBackend();
    final bridge = platform.window;
    final content = Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: OreWindowTitleBar(
          bridge: bridge,
          trafficLights: platform.trafficLights,
          title: displayName,
          subtitle: subtitle.isEmpty ? null : subtitle,
          actions: [
            OreIconButton(
              color: Colors.white,
              icon: const Icon(Icons.pause, color: Colors.white),
              tooltip: '暂停 / 返回',
              onPressed: () => bridge.invoke('sendKey', 'escape'),
            ),
            OreIconButton(
              color: Colors.white,
              icon: const Icon(Icons.fullscreen, color: Colors.white),
              tooltip: '切换全屏',
              onPressed: () => bridge.invoke('fullscreen'),
            ),
          ],
        ),
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: oreAppTheme(),
      darkTheme: oreAppTheme(brightness: Brightness.dark),
      home: platform.nativeMenus
          ? PlatformMenuBar(
              menus: gamePlatformMenus(
                bridge,
                displayName: displayName,
                gameVersion: gameVersion,
              ),
              child: content,
            )
          : content,
    );
  }
}
