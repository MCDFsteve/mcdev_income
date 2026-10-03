import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/game_graphics.dart';
import 'package:mcdev_income/development/mcs_api.dart';

void main() {
  test('official Haldra references label their channels and architecture', () {
    final catalog = GameCatalog.fromJson({
      'stable_x64': '3.8.0.1',
      'stable_haldra_x64': '3.9.0.2',
      'stable_new_haldra_x64': '3.9.0.2',
      'beta_haldra_x64': '3.10.0.3',
      'entities': {
        for (final version in ['3.8.0.1', '3.9.0.2', '3.10.0.3'])
          version: {
            'url': 'https://g79.gdl.netease.com/$version/patch.json',
            'md5': 'a' * 32,
          },
      },
    });
    expect(catalog.packages.first.clientType, GameClientType.haldra);
    expect(catalog.packages.first.architecture, GameArchitecture.x64);
    expect(catalog.packages.first.channels, [GameChannel.beta]);
    expect(catalog.packages[1].channels, [
      GameChannel.stable,
      GameChannel.preview,
    ]);
    expect(catalog.stable!.clientType, GameClientType.openGL);
  });
  test(
    'truncated UTF-8 username recovers without losing other saved options',
    () async {
      final temporary = await Directory.systemTemp.createTemp('mcdev-options-');
      addTearDown(() => temporary.delete(recursive: true));
      final file = File('${temporary.path}/options.txt');
      // The native client wrote 16 bytes of an 18-byte name, leaving an
      // incomplete final Chinese character. This previously blocked relaunch.
      await file.writeAsBytes([
        ...utf8.encode('mp_username:'),
        ...utf8.encode('测试艾利克斯').take(16),
        ...utf8.encode('\r\ngfx_viewdistance:96\r\ncustom:保留此项\r\n'),
      ]);
      final source = await file.readAsString(encoding: gameOptionsEncoding);
      final repaired = mergeGameOptions(source, {'mp_username': '测试艾莉'});
      expect(
        repaired,
        'mp_username:测试艾莉\r\ngfx_viewdistance:96\r\ncustom:保留此项\r\n',
      );
      await file.writeAsString(repaired);
      expect(await file.readAsString(), repaired);
    },
  );

  test(
    'renderer choices match MCS version boundary and configuration enums',
    () {
      for (final version in [
        null,
        'PCLauncher_x64',
        '3.8.0.313229',
        '2.9.1.4',
      ]) {
        expect(supportsRendererSwitch(version), isFalse);
      }
      for (final version in ['3.9.0.401155', '3.10.0.420447', '4.0.0.1']) {
        expect(supportsRendererSwitch(version), isTrue);
      }
      expect(rendererConfig(GameRenderer.openGL, GameClientType.haldra), {
        'render_engine': 0,
        'client_type': 1,
      });
      expect(rendererConfig(GameRenderer.renderDragon, GameClientType.openGL), {
        'render_engine': 1,
        'client_type': 0,
      });
    },
  );
  test(
    'frame choices remove VSync and all launch-side frame caps when unlimited',
    () {
      expect(frameLimitOptions(true)['gfx_max_framerate'], '60');
      expect(frameLimitOptions(true, nativePacing: true), {
        'gfx_max_framerate': '0',
        'gfx_ne_vsync': '0',
        'frame_pacing_enabled': '0',
      });
      expect(frameLimitOptions(false), {
        'gfx_max_framerate': '0',
        'gfx_ne_vsync': '0',
        'frame_pacing_enabled': '0',
      });
    },
  );

  test(
    'merging preserves quality, unknown keys, comments and colon-containing values',
    () {
      const source =
          '\uFEFFgfx_viewdistance:128\r\n# custom\r\nurl:https://example.test:443/x\r\ngfx_max_framerate:80\r\ngfx_ne_vsync:1\r\ngfx_max_framerate:120\r\n';
      final result = mergeGameOptions(source, frameLimitOptions(false));
      expect(
        result,
        contains(
          'gfx_viewdistance:128\r\n# custom\r\nurl:https://example.test:443/x\r\n',
        ),
      );
      expect('gfx_max_framerate:'.allMatches(result).length, 1);
      expect(result, contains('gfx_max_framerate:0\r\n'));
      expect(result, contains('gfx_ne_vsync:0\r\n'));
      expect(result, endsWith('frame_pacing_enabled:0\r\n'));
    },
  );
}
