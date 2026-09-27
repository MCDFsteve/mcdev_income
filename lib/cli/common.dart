import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
export '../storage/file_lock.dart';

String credentialFingerprint(String value) =>
    sha256.convert(utf8.encode(value)).toString();

class CliFailure implements Exception {
  CliFailure(this.code, this.message, {this.exitCode = 2, this.details});
  final String code;
  final String message;
  final int exitCode;
  final Object? details;
}

Map<String, dynamic> objectMap(dynamic value, String label) {
  if (value is! Map) throw CliFailure('invalid_input', '$label 必须是 JSON 对象');
  return Map<String, dynamic>.from(value);
}

Future<Map<String, dynamic>> readObject(String path) async {
  try {
    return objectMap(jsonDecode(await File(path).readAsString()), path);
  } on FormatException {
    throw CliFailure('invalid_json', '$path 不是有效 JSON');
  }
}

DateTime parseDate(String value) {
  try {
    return DateFormat('yyyy-MM-dd').parseStrict(value);
  } on FormatException {
    throw CliFailure('invalid_date', '日期格式应为 YYYY-MM-DD：$value');
  }
}

int integer(String? value, String name, {int? fallback, int? min, int? max}) {
  final result = value == null ? fallback : int.tryParse(value);
  if (result == null ||
      (min != null && result < min) ||
      (max != null && result > max)) {
    throw CliFailure(
      'invalid_argument',
      '$name 必须是${min == null ? '' : '不小于 $min 的'}整数${max == null ? '' : '，最大 $max'}',
    );
  }
  return result;
}

void mergeFields(Map<String, dynamic> target, Map<String, dynamic> source) {
  for (final entry in source.entries) {
    if (entry.value is Map && target[entry.key] is Map) {
      final nested = objectMap(target[entry.key], entry.key);
      mergeFields(nested, objectMap(entry.value, entry.key));
      target[entry.key] = nested;
    } else {
      target[entry.key] = entry.value;
    }
  }
}

Future<void> writeJsonFile(String path, Object? value) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final temp = File('$path.$pid.${Random.secure().nextInt(1 << 32)}.tmp');
  await temp.create();
  if (!Platform.isWindows) {
    final permission = await Process.run('chmod', ['600', temp.path]);
    if (permission.exitCode != 0) {
      throw FileSystemException('无法限制文件权限', temp.path);
    }
  }
  try {
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    await temp.rename(path);
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}

String csvCell(Object? value) =>
    '"${(value ?? '').toString().replaceAll('"', '""')}"';
