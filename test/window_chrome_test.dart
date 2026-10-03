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
      final menus = gamePlatformMenus(const DesktopWindowBridge());
      final keys = menus.whereType<PlatformMenu>().singleWhere(
        (menu) => menu.label == '功能键',
      );
      expect(keys.menus.map((item) => item.label), [
        for (var i = 1; i <= 12; i++) 'F$i',
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

  testWidgets(
    'game titlebar registers native menus and fits a narrow window',
    (tester) async {
      tester.view.physicalSize = const Size(360, 48);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final menuCalls = <MethodCall>[];
      final windowCalls = <MethodCall>[];
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
        const MethodChannel('flutter/menu'),
        (call) async {
          menuCalls.add(call);
          return null;
        },
      );
      await tester.pumpWidget(
        const GameChromeApp(
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
        const MethodChannel('flutter/menu'),
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
