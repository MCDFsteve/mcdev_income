import 'dart:io';
import 'package:mcdev_income/cli/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await McdevCli().run(arguments);
}
