library mcdev_income_app;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'core.dart';
export 'core.dart';
import 'cli/unsupported_entry.dart'
    if (dart.library.io) 'cli/desktop_entry.dart' as desktop_cli;
import 'storage/app_preferences.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mcdev_income/logging/app_logger.dart' as app_logger;
import 'package:mcdev_income/utils/csv_file_saver.dart' as csv_file_saver;
import 'package:mcdev_income/ui/ore_material.dart';
import 'package:mcdev_income/widgets/resource_image_crop_dialog.dart';

part 'services/login_cookie_helper.dart';
part 'app/app.dart';
part 'widgets/ore_app_bar.dart';
part 'widgets/resource_dialog.dart';
part 'widgets/placeholder_page.dart';
part 'app/home_shell.dart';
part 'pages/home_page.dart';
part 'pages/mailbox_page.dart';
part 'widgets/mailbox_button.dart';
part 'pages/mods_page.dart';
part 'pages/resource_management_page.dart';
part 'pages/resource_editor_page.dart';
part 'pages/resource_review_page.dart';
part 'pages/resource_price_dialog.dart';
part 'pages/income/income_preset.dart';
part 'pages/income/income_page_support.dart';
part 'pages/income/income_page.dart';
part 'pages/income/income_page_view.dart';
part 'pages/settings_page.dart';
part 'pages/login_page.dart';

Future<void> main(List<String> arguments) async {
  if (await desktop_cli.runHeadlessIfRequested(arguments)) return;

  runZonedGuarded(
    () async {
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
    },
    (error, stack) {
      app_logger.error('Uncaught zone error', error, stack);
    },
  );
}
