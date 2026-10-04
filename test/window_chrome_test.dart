import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mcdev_income/desktop/game_chrome.dart';
import 'package:mcdev_income/desktop/window_title_bar.dart';
import 'package:mcdev_income/development/game_window_chrome_io.dart';
import 'package:mcdev_income/ui/ore_material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'game menu routes every function key and common action locally',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopWindowBridge.channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DesktopWindowBridge.channel, null),
      );
      final menus = gamePlatformMenus(
        const DesktopWindowBridge(),
        gameVersion: '3.10.0.420447',
      );
      final keys = menus.whereType<PlatformMenu>().singleWhere(
        (menu) => menu.label == '功能键',
      );
      expect(keys.menus.map((item) => item.label), [
        '显示 / 隐藏界面（F1）',
        '截图（F2）',
        '调试信息下一页（F3）',
        '调试信息上一页（F4）',
        '切换视角（F5）',
        '穿墙飞行（F6，调试）',
        '未发现默认单键功能（F7）',
        '显示 / 隐藏纸娃娃（F8）',
        '模拟挂起 / 恢复（F9，调试）',
        '录像 / 显示隐藏提示（F10）',
        '渲染帧捕获（F11，需 RenderDoc）',
        '播放回放（F12）',
      ]);
      for (final item in keys.menus) {
        item.onSelected!();
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method).toSet(), {'sendKey'});
      expect(calls.map((call) => call.arguments), [
        for (var i = 1; i <= 12; i++) 'F$i',
      ]);
      final game = menus.whereType<PlatformMenu>().singleWhere(
        (menu) => menu.label == '游戏',
      );
      game.menus.first.onSelected!();
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.arguments, 'escape');
    },
  );

  test('F11 only names RenderDoc for the verified game build', () {
    String f11Label(String version) =>
        gamePlatformMenus(const DesktopWindowBridge(), gameVersion: version)
            .whereType<PlatformMenu>()
            .singleWhere((menu) => menu.label == '功能键')
            .menus
            .whereType<GameMenuItem>()
            .singleWhere((item) => item.argument == 'F11')
            .label;

    expect(f11Label('3.8.0.313229'), '未发现默认单键功能（F11）');
    expect(f11Label('unknown'), '默认功能待核对（F11）');
  });

  testWidgets(
    'game titlebar registers native menus and fits a narrow window',
    (tester) async {
      tester.view.physicalSize = const Size(360, 48);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final menuCalls = <MethodCall>[];
      final windowCalls = <MethodCall>[];
      final previousDelegate = WidgetsBinding.instance.platformMenuDelegate;
      WidgetsBinding.instance.platformMenuDelegate =
          DefaultPlatformMenuDelegate(channel: gameMenuChannel);
      addTearDown(() {
        WidgetsBinding.instance.platformMenuDelegate = previousDelegate;
        gameMenuChannel.setMethodCallHandler(null);
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopWindowBridge.channel,
        (call) async {
          windowCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DesktopWindowBridge.channel,
          null,
        ),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        gameMenuChannel,
        (call) async {
          menuCalls.add(call);
          return null;
        },
      );
      await tester.pumpWidget(
        const GameChromeApp(
          gameVersion: '3.10.0.420447',
          subtitle: '3.10.0.420447 · 渲染龙',
          displayName: '我的世界测试 · 草地方块与海洋世界',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OreWindowTitleBar), findsOneWidget);
      expect(
        find.text('我的世界测试 · 草地方块与海洋世界 · 3.10.0.420447 · 渲染龙'),
        findsOneWidget,
      );
      expect(find.byType(Material), findsWidgets);
      expect(menuCalls.any((call) => call.method == 'Menu.setMenus'), isTrue);
      expect(menuCalls.last.arguments.toString(), contains('草地方块与海洋世界'));
      final representation = menuCalls.last.arguments as Map;
      final leaves = <Map>[];
      void collect(List items) {
        for (final item in items.cast<Map>()) {
          if (item['children'] is List) {
            collect(item['children'] as List);
          } else if (item['isDivider'] != true) {
            leaves.add(item);
          }
        }
      }

      collect(representation['0'] as List);
      expect(leaves, hasLength(25));
      expect(
        leaves.singleWhere((item) => item['argument'] == 'F11')['label'],
        '渲染帧捕获（F11，需 RenderDoc）',
      );
      expect(leaves.every((item) => item['action'] != null), isTrue);
      expect(
        leaves
            .where((item) => item['action'] == 'sendKey')
            .map((item) => item['argument']),
        [
          'escape',
          'inventory',
          'chat',
          'command',
          'F5',
          'F1',
          for (var i = 1; i <= 12; i++) 'F$i',
        ],
      );
      expect(
        leaves.singleWhere(
          (item) => item['action'] == 'close',
        )['shortcutTrigger'],
        LogicalKeyboardKey.keyQ.keyId,
      );
      final region =
          windowCalls
                  .singleWhere((call) => call.method == 'setDragRegion')
                  .arguments
              as Map;
      expect(region['x'], greaterThanOrEqualTo(86));
      expect(
        (region['x'] as double) + (region['width'] as double),
        lessThan(300),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        gameMenuChannel,
        null,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test(
    'chrome preserves the input guard and carries only its local configuration',
    () {
      const chrome = GameWindowChrome(
        '/runtime/chrome.dylib',
        '/Applications/管理器.app',
      );
      final env = chrome.environment(
        loader: '/runtime/我的世界测试.app/Contents/MacOS/wine',
        version: '3.10.0.420447',
        renderer: '渲染龙',
        displayName: '我的世界测试 · 草地',
        inherited: {'DYLD_INSERT_LIBRARIES': '/runtime/input.dylib'},
      );
      expect(
        env['DYLD_INSERT_LIBRARIES'],
        '/runtime/input.dylib:/runtime/chrome.dylib',
      );
      expect(
        env['MCDEV_CHROME_LOADER'],
        '/runtime/我的世界测试.app/Contents/MacOS/wine',
      );
      expect(
        env['MCDEV_CHROME_APP'],
        '/Applications/管理器.app/Contents/Frameworks/App.framework',
      );
      expect(env['MCDEV_CHROME_DISPLAY_NAME'], '我的世界测试 · 草地');
    },
  );

  test(
    'window bridge cache verifies and repairs the bundled component',
    () async {
      final temp = await Directory.systemTemp.createTemp('mcdev-chrome-test-');
      addTearDown(() => temp.delete(recursive: true));
      final app = p.join(temp.path, 'Client.app');
      for (final path in [
        'FlutterMacOS.framework/FlutterMacOS',
        'App.framework/App',
      ]) {
        final file = File(p.join(app, 'Contents/Frameworks', path));
        await file.parent.create(recursive: true);
        await file.writeAsString('framework fixture');
      }
      final chrome = await prepareGameWindowChrome(
        p.join(temp.path, 'runtimes'),
        application: app,
      );
      final file = File(chrome.library);
      expect(
        sha256.convert(await file.readAsBytes()).toString(),
        gameWindowChromeHash,
      );
      await file.writeAsString('damaged');
      await prepareGameWindowChrome(
        p.join(temp.path, 'runtimes'),
        application: app,
      );
      expect(
        sha256.convert(await file.readAsBytes()).toString(),
        gameWindowChromeHash,
      );
    },
  );
}
