library mcdev_income_app;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mcdev_income/logging/app_logger.dart' as app_logger;
import 'package:mcdev_income/ui/ore_material.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'models/models.dart';
part 'services/login_cookie_helper.dart';
part 'services/mcdev_api.dart';
part 'app/app.dart';
part 'widgets/ore_app_bar.dart';
part 'widgets/placeholder_page.dart';
part 'app/home_shell.dart';
part 'pages/home_page.dart';
part 'pages/mods_page.dart';
part 'pages/income/income_preset.dart';
part 'pages/income/income_page_support.dart';
part 'pages/income/income_page.dart';
part 'pages/income/income_page_view.dart';
part 'pages/settings_page.dart';
part 'pages/login_webview_page.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await app_logger.init(appFolderName: 'ConsMelt');

    FlutterError.onError = (details) {
      app_logger.flutterError(details);
    };

    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      app_logger.error('Uncaught platform error', error, stack);
      return true;
    };

    runApp(const McDevIncomeApp());
  }, (error, stack) {
    app_logger.error('Uncaught zone error', error, stack);
  });
}
