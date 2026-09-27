import 'dart:io';

import 'cli.dart';

/// Runs CLI commands in the desktop application's existing Dart isolate.
Future<bool> runHeadlessIfRequested(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first != '--headless') return false;

  final result = await McdevCli().run(arguments.skip(1).toList());
  await stdout.flush();
  await stderr.flush();
  exit(result);
}
