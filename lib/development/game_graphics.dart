/// MCS uses options.txt for frame limits (0 means unlimited). VSync's enum
/// values in the supported developer game are Off=0, On=1, Adaptive=2.
/// Keep unrelated options, including quality and render distance, verbatim.
String mergeGameOptions(String source, Map<String, String> changes) {
  final newline = source.contains('\r\n') ? '\r\n' : '\n';
  final remaining = Map<String, String>.of(changes);
  final lines = <String>[];
  for (final line
      in source.replaceFirst(RegExp(r'^\uFEFF'), '').split(RegExp(r'\r?\n'))) {
    final colon = line.indexOf(':');
    final key = colon < 0 ? '' : line.substring(0, colon);
    if (changes.containsKey(key)) {
      // Remove duplicates so the game cannot load an older conflicting value.
      final value = remaining.remove(key);
      if (value != null) lines.add('$key:$value');
    } else {
      lines.add(line);
    }
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  lines.addAll(remaining.entries.map((entry) => '${entry.key}:${entry.value}'));
  return '${lines.join(newline)}$newline';
}

Map<String, String> frameLimitOptions(
  bool limit60, {
  bool nativePacing = false,
}) => {
  // Use one clock. The supported DLL supplies its own calibrated 60 Hz pacing;
  // adding the game's limiter can make the two wait paths interfere.
  'gfx_max_framerate': limit60 && !nativePacing ? '60' : '0',
  // The verified patch runs with swap interval 0. A driver VSync clock plus
  // QPC pacing can miss alternating refresh deadlines and fall near 30 FPS.
  'gfx_ne_vsync': '0',
  'frame_pacing_enabled': '0',
};

enum GameRenderer {
  openGL('OpenGL', 0),
  renderDragon('渲染龙', 1);

  const GameRenderer(this.label, this.configValue);
  final String label;
  final int configValue;
}

/// The official catalog has separate *_haldra_x64 clients. This identifies
/// the installed binary; render_engine selects the test world's render path.
enum GameClientType { openGL, haldra }

/// MCS 1.1.59 CppGameCreateViewModel.CheckRenderEngineVisible: 3.9 and later.
bool supportsRendererSwitch(String? version) {
  if (version == null || !RegExp(r'^\d+(\.\d+){1,5}$').hasMatch(version)) {
    return false;
  }
  final parts = version.split('.').map(int.parse).toList();
  return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 9);
}

Map<String, int> rendererConfig(GameRenderer renderer, GameClientType client) =>
    {
      'render_engine': renderer.configValue,
      'client_type': client == GameClientType.haldra ? 1 : 0,
    };
