/// Shared business library: deliberately independent of Flutter and dart:ui.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'core/preferences.dart';
export 'core/preferences.dart';

part 'models/models.dart';
part 'models/dashboard.dart';
part 'models/resource_workflow.dart';
part 'services/mcdev_api.dart';
part 'services/dashboard_api.dart';
part 'services/leaderboard_export.dart';
part 'services/resource_api.dart';
part 'core/login_service.dart';

class IncomeDateRange {
  const IncomeDateRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
}

class CoreRuntime {
  static Future<PreferenceStore> Function() preferences = () async =>
      throw StateError('Storage not configured');
  static void Function(String) log = (_) {};
  static String system = 'Unknown';
}
