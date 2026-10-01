// Explicit read-only diagnostic, excluded from normal test discovery.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/core.dart';
import 'package:mcdev_income/storage/file_preferences.dart';
import 'package:mcdev_income/development/mcs_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'inspect official game catalog using existing login',
    () async {
      if (Platform.environment['MCDEV_LIVE_DEVELOPMENT'] != '1') {
        throw StateError('Explicit MCDEV_LIVE_DEVELOPMENT=1 required');
      }
      final preferences = await FilePreferences.open(mcdevHome());
      CoreRuntime.preferences = () async => preferences;
      CoreRuntime.system = 'Mac';
      final api = McsApi();
      try {
        await api.authenticateDeveloper(
          await LoginService.buildCookieHeader(allowCache: false),
        );
        final catalog = await api.catalog();
        final publicPath = Platform.environment['MCDEV_PUBLIC_CATALOG_OUTPUT'];
        if (publicPath != null) {
          await File(publicPath).writeAsString(
            jsonEncode([
              for (final package in catalog.packages)
                {
                  'version': package.version,
                  'patch_url': package.patchUrl.toString(),
                  'patch_md5': package.patchMd5,
                  'architecture': package.architecture.name,
                  'client_type': package.clientType.name,
                  'channels': package.channels
                      .map((channel) => channel.name)
                      .toList(),
                  'size': package.size,
                },
            ]),
          );
        }
        print(
          jsonEncode({
            'versions': catalog.packages.length,
            'architectures': {
              for (final architecture in GameArchitecture.values)
                architecture.label: catalog.packages
                    .where((game) => game.architecture == architecture)
                    .length,
            },
            'channels_x64': {
              for (final channel in GameChannel.values)
                channel.label: catalog.packages
                    .where(
                      (game) =>
                          game.architecture == GameArchitecture.x64 &&
                          game.channels.contains(channel),
                    )
                    .map((game) => game.version)
                    .toList(),
            },
            'newest_entries': catalog.packages
                .take(5)
                .map((game) => game.version)
                .toList(),
          }),
        );
        expect(catalog.packages, isNotEmpty);
        expect(catalog.stable, isNotNull);
        final probes = {
          catalog.packages.first,
          ...catalog.packages.where(
            (game) =>
                game.architecture == GameArchitecture.x64 &&
                game.channels.contains(GameChannel.beta),
          ),
        };
        for (final package in probes) {
          final response = await api.client.head(
            signMcsDownload(package.patchUrl),
          );
          print(
            'Patch HEAD ${package.version}: HTTP ${response.statusCode}, length=${response.headers['content-length']}',
          );
          expect(response.statusCode, 200);
        }
      } finally {
        api.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
