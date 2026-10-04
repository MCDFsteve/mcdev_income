import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/development/launcher_service.dart';

void main() {
  test('player names respect the native 16-byte UTF-8 boundary', () {
    for (final name in [
      '1234567890123456',
      '测试史蒂夫',
      '测试史蒂夫1',
      '测试艾莉',
      '😀😀😀😀',
      'éééééééé',
      '  测试史蒂夫1  ',
    ]) {
      expect(validateDevelopmentPlayerName(name), isNull, reason: name);
    }
    for (final name in [
      '12345678901234567',
      '测试艾利克斯',
      '测试史蒂夫12',
      '😀😀😀😀a',
      'ééééééééa',
    ]) {
      expect(
        validateDevelopmentPlayerName(name),
        '玩家名字最多 16 字节，中文通常最多 5 个字。',
        reason: name,
      );
    }
  });

  test('player names still reject blank, controls and formatting codes', () {
    for (final name in ['', '  ', 'a\nb', '§a名字', 'bad\u0001name']) {
      expect(validateDevelopmentPlayerName(name), isNotNull, reason: name);
    }
  });

  test('suggested names remain unique and safe past four digit indices', () {
    expect(suggestedDevelopmentPlayerName([]), '测试玩家1');
    expect(suggestedDevelopmentPlayerName(['测试玩家1']), '测试玩家2');
    final reserved = [for (var i = 1; i <= 9999; i++) '测试玩家$i', '玩家10000'];
    final name = suggestedDevelopmentPlayerName(reserved);
    expect(name, '玩家10001');
    expect(reserved, isNot(contains(name)));
    expect(utf8.encode(name).length, lessThanOrEqualTo(16));
    expect(validateDevelopmentPlayerName(name), isNull);
  });
}
