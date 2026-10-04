import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'mod_log_filter.dart';

class ModLogCapture {
  const ModLogCapture(this.marker, this.sources);
  final String marker;
  final ModLogSources sources;
}

/// Only call on staged copies. Original project files are never rewritten.
/// Each script package installs the capture before its own __init__/modMain,
/// independent of the engine's unordered pack-loading order.
Future<ModLogCapture> prepareModLogCapture(List<Directory> snapshots) async {
  final nonce = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final marker = 'MCDEV_MOD_OUTPUT_$nonce';
  final modules = <String>{};
  final paths = <String>{};
  final identifiers = <String>{};
  final scriptRoots = <Directory>[];
  for (final pack in snapshots) {
    paths.add(pack.path);
    paths.add(p.basename(pack.path));
    await for (final entity in pack.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: pack.path);
      final parts = p.split(relative);
      if (parts.length >= 2 &&
          (p.basename(entity.path) == 'modMain.py' ||
              p.basename(entity.path) == 'modMain.pyc')) {
        final root = Directory(p.join(pack.path, parts.first));
        if (!scriptRoots.any((item) => item.path == root.path)) {
          scriptRoots.add(root);
        }
      }
      if (p.extension(relative) == '.py' || p.extension(relative) == '.pyc') {
        if (parts.length >= 2) {
          modules.add(parts.first);
        } else {
          modules.add(p.basenameWithoutExtension(relative));
        }
      }
      if (p.extension(relative).toLowerCase() != '.json') continue;
      // A qualified content path is attributable; a generic filename such as
      // player.json or manifest.json is also used by the engine/vanilla packs.
      if (parts.length >= 2) paths.add(relative);
      if (await entity.length() > 2 * 1024 * 1024) continue;
      try {
        final value = jsonDecode(await entity.readAsString());
        void visit(Object? item) {
          if (item is Map) {
            for (final entry in item.entries) {
              if ((entry.key == 'identifier' ||
                      entry.key == 'identifier_name') &&
                  entry.value is String &&
                  (entry.value as String).contains(':') &&
                  !(entry.value as String).startsWith('minecraft:')) {
                identifiers.add(entry.value as String);
              }
              visit(entry.value);
            }
          } else if (item is List) {
            for (final child in item) {
              visit(child);
            }
          } else if (item is String && item.startsWith('textures/')) {
            paths.add(item);
          }
        }

        visit(value);
      } on FormatException {
        // Invalid mod JSON is reported by the game; do not prevent its launch.
      }
    }
  }
  final bootstrap = _bootstrap
      .replaceAll('__MARKER__', jsonEncode(marker))
      .replaceAll('__MODULES__', jsonEncode(modules.toList()))
      .replaceAll('__STATE__', jsonEncode('__mcdev_modlog_$nonce'));
  for (final directory in scriptRoots) {
    final init = File(p.join(directory.path, '__init__.py'));
    final compiled = File(p.join(directory.path, '__init__.pyc'));
    var source = await init.exists() ? await init.readAsBytes() : <int>[];
    var bytecode =
        source.isEmpty && !await init.exists() && await compiled.exists()
        ? await compiled.readAsBytes()
        : null;
    // LAN guests copy the host's mounted snapshot, which already has capture.
    // Recover the original init before installing this guest's session marker.
    final lines = utf8.decode(source, allowMalformed: true).split('\n');
    const originalTag = '# MCDEV_ORIGINAL_INIT_V1 ';
    if (lines.length > 1 && lines[1].startsWith(originalTag)) {
      final original =
          jsonDecode(lines[1].substring(originalTag.length)) as Map;
      final bytes = base64.decode(original['data'] as String);
      if (original['type'] == 'bytecode') {
        bytecode = bytes;
        source = [];
      } else {
        source = bytes;
        bytecode = null;
      }
    }
    // Execute the original source separately: encoding declarations, module
    // docstrings and future imports retain their normal semantics and errors
    // retain the original line numbers. No prefix is added to user modMain.
    final original = bytecode == null
        ? 'compile(__import__("base64").b64decode("${base64Encode(source)}"), '
              '${jsonEncode('${p.basename(directory.path)}/__init__.py')}, "exec")'
        : '__import__("marshal").loads(__import__("base64").b64decode('
              '"${base64Encode(bytecode)}")[8:])';
    await init.writeAsString(
      '# -*- coding: utf-8 -*-\n'
      '$originalTag${jsonEncode({'type': bytecode == null ? 'source' : 'bytecode', 'data': base64Encode(bytecode ?? source)})}\n'
      'exec compile(__import__("base64").b64decode('
      '"${base64Encode(utf8.encode(bootstrap))}"), '
      '"<mcdev mod logging>", "exec") in {}\n'
      'exec $original in globals()\n',
    );
    // Source must win over cached bytecode. This is only the staged copy.
    if (await compiled.exists()) await compiled.delete();
  }
  return ModLogCapture(
    marker,
    ModLogSources(modules: modules, paths: paths, identifiers: identifiers),
  );
}

const _bootstrap = r'''import sys
import base64

MARKER = __MARKER__
MODULES = tuple(__MODULES__)
STATE = __STATE__
try:
    text_type = unicode
except NameError:
    text_type = str


def owner(frame, walk=False):
    while frame is not None:
        name = frame.f_globals.get("__name__", "")
        if any(name == root or name.startswith(root + ".") for root in MODULES):
            return name
        if not walk:
            break
        frame = frame.f_back
    return None


class Writer(object):
    def __init__(self, original, kind):
        self.original = original
        self.kind = kind
        self.softspace = getattr(original, "softspace", 0)
        self.marker = MARKER

    def write(self, value):
        name = owner(sys._getframe(1), self.kind == "E")
        if name is None:
            return self.original.write(value)
        data = value.encode("utf-8", "replace") if isinstance(value, text_type) else value
        if not data:
            return
        # ASCII framing avoids the engine interpreting print text as its own
        # [INFO]/[ERROR] logger records. The Flutter writer restores each chunk.
        start = 0
        while start < len(data):
            end = min(start + 12000, len(data))
            while end < len(data) and end > start and ord(data[end]) & 0xc0 == 0x80:
                end -= 1
            if end == start:
                end = min(start + 12000, len(data))
            self.original.write(MARKER + ":" + self.kind + ":" +
                                base64.b64encode(name.encode("utf-8")) + ":" +
                                base64.b64encode(data[start:end]) + "\n")
            start = end

    def flush(self):
        if hasattr(self.original, "flush"):
            return self.original.flush()

    def __getattr__(self, name):
        return getattr(self.original, name)


# A client/server interpreter or a logger reinitialization can replace stdout.
# Reinstall per script package, but never stack wrappers for the same session.
for name, kind in (("stdout", "P"), ("stderr", "E")):
    stream = getattr(sys, name)
    if getattr(stream, "marker", None) != MARKER:
        setattr(sys, name, Writer(stream, kind))
setattr(sys, STATE, True)
''';
