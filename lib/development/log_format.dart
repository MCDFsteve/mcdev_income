enum DevelopmentLogLevel {
  error('错误'),
  warning('警告'),
  info('信息'),
  debug('调试'),
  other('其他');

  const DevelopmentLogLevel(this.label);
  final String label;
}

final _explicitLevel = RegExp(
  r'\[(error|err|fatal|warning|warn|info|debug|trace|fixme)\]|'
  r'\b(?:[0-9a-f]{3,}:)+(err|warn|fixme|trace):|'
  r'"(?:level|severity)"\s*:\s*"(error|fatal|warning|warn|info|debug|trace)"|'
  r'^\s*(?:\d{4}-\d\d-\d\d[ T][\d:.+Z-]+\s+)?'
  r'(ERROR|FATAL|WARNING|WARN|INFO|DEBUG|TRACE)\b',
  caseSensitive: false,
);

DevelopmentLogLevel classifyLogLine(
  String text, {
  DevelopmentLogLevel continuation = DevelopmentLogLevel.other,
}) {
  final match = _explicitLevel.firstMatch(text);
  if (match != null) {
    final level = [
      for (var i = 1; i <= match.groupCount; i++)
        if (match.group(i) != null) match.group(i)!.toLowerCase(),
    ].first;
    return switch (level) {
      'error' || 'err' || 'fatal' => DevelopmentLogLevel.error,
      'warning' || 'warn' => DevelopmentLogLevel.warning,
      'info' => DevelopmentLogLevel.info,
      _ => DevelopmentLogLevel.debug,
    };
  }
  if (RegExp(
    r'^\s*(?:Unhandled|Uncaught)\s+(?:exception|error)|'
    r'^\s*\w*(?:Error|Exception)[:\s]',
    caseSensitive: false,
  ).hasMatch(text)) {
    return DevelopmentLogLevel.error;
  }
  // Stack frames stay with their preceding diagnostic when filtering by level.
  if (RegExp(r'^\s+\S|^\s*(?:at |#\d+ |Caused by:)').hasMatch(text)) {
    return continuation;
  }
  return DevelopmentLogLevel.other;
}

enum LogTokenKind {
  plain,
  timestamp,
  level,
  string,
  key,
  path,
  number,
  keyword,
}

class LogToken {
  const LogToken(this.text, this.kind);
  final String text;
  final LogTokenKind kind;
}

final _tokens = RegExp(
  r'(\b\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:[.,]\d+)?(?:Z|[+-]\d\d:\d\d)?|\b\d\d:\d\d:\d\d(?:[.,]\d+)?)|'
  r'("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27|`[^`]*`)|'
  r'([A-Z]:[\\/][^\s"\x27<>]+|(?:/[^\s/"\x27<>]+){2,})|'
  r'(\b(?:ERROR|ERR|FATAL|WARNING|WARN|INFO|DEBUG|TRACE|FIXME)\b)|'
  r'(\b(?:0x[0-9a-f]+|\d+(?:\.\d+)*)\b)|'
  r'(\b(?:true|false|null|undefined|const|let|var|function|return|if|else|class|def|import)\b)',
  caseSensitive: false,
);

/// Small, deterministic lexer for diagnostic text and embedded JSON/code.
/// Concatenating the tokens always reproduces the input exactly.
List<LogToken> highlightLogLine(String text) {
  final tokens = <LogToken>[];
  var cursor = 0;
  for (final match in _tokens.allMatches(text)) {
    if (match.start > cursor) {
      tokens.add(
        LogToken(text.substring(cursor, match.start), LogTokenKind.plain),
      );
    }
    final kind = match.group(1) != null
        ? LogTokenKind.timestamp
        : match.group(2) != null
        ? RegExp(r'^\s*:').hasMatch(text.substring(match.end))
              ? LogTokenKind.key
              : LogTokenKind.string
        : match.group(3) != null
        ? LogTokenKind.path
        : match.group(4) != null
        ? LogTokenKind.level
        : match.group(5) != null
        ? LogTokenKind.number
        : LogTokenKind.keyword;
    tokens.add(LogToken(match.group(0)!, kind));
    cursor = match.end;
  }
  if (cursor < text.length) {
    tokens.add(LogToken(text.substring(cursor), LogTokenKind.plain));
  }
  return tokens;
}
