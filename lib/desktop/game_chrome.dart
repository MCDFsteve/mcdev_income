import 'package:flutter/services.dart';
import '../ui/ore_material.dart';
import 'window_title_bar.dart';

void runGameChrome(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    GameChromeApp(
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

List<PlatformMenuItem> gamePlatformMenus(
  DesktopWindowBridge bridge, {
  String displayName = '我的世界测试',
}) => [
  PlatformMenu(
    label: displayName,
    menus: [
      PlatformMenuItem(
        label: '关于$displayName',
        onSelected: () => bridge.invoke('about'),
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: '隐藏$displayName',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyH,
              meta: true,
            ),
            onSelected: () => bridge.invoke('hide'),
          ),
          PlatformMenuItem(
            label: '显示全部',
            onSelected: () => bridge.invoke('showAll'),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: '退出测试游戏',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyQ,
              meta: true,
            ),
            onSelected: () => bridge.invoke('close'),
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
        PlatformMenuItem(
          label: label,
          onSelected: () => bridge.invoke('sendKey', key),
        ),
    ],
  ),
  PlatformMenu(
    label: '功能键',
    menus: [
      for (var key = 1; key <= 12; key++)
        PlatformMenuItem(
          label: 'F$key',
          onSelected: () => bridge.invoke('sendKey', 'F$key'),
        ),
    ],
  ),
  PlatformMenu(
    label: '窗口',
    menus: [
      PlatformMenuItem(
        label: '最小化',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
        onSelected: () => bridge.invoke('minimize'),
      ),
      PlatformMenuItem(label: '缩放', onSelected: () => bridge.invoke('zoom')),
      PlatformMenuItem(
        label: '切换全屏',
        shortcut: const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          control: true,
        ),
        onSelected: () => bridge.invoke('fullscreen'),
      ),
    ],
  ),
];

class GameChromeApp extends StatelessWidget {
  const GameChromeApp({
    super.key,
    this.subtitle = '',
    this.displayName = '我的世界测试',
  });
  final String subtitle;
  final String displayName;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: oreAppTheme(),
    darkTheme: oreAppTheme(brightness: Brightness.dark),
    home: PlatformMenuBar(
      menus: gamePlatformMenus(
        const DesktopWindowBridge(),
        displayName: displayName,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: OreWindowTitleBar(
          title: displayName,
          subtitle: subtitle.isEmpty ? null : subtitle,
          actions: [
            OreIconButton(
              color: Colors.white,
              icon: const Icon(Icons.pause, color: Colors.white),
              tooltip: '暂停 / 返回',
              onPressed: () =>
                  const DesktopWindowBridge().invoke('sendKey', 'escape'),
            ),
            OreIconButton(
              color: Colors.white,
              icon: const Icon(Icons.fullscreen, color: Colors.white),
              tooltip: '切换全屏',
              onPressed: () => const DesktopWindowBridge().invoke('fullscreen'),
            ),
          ],
        ),
      ),
    ),
  );
}
