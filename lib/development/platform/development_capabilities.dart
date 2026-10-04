/// UI depends on capabilities, never on the host operating system.
class DevelopmentCapabilities {
  const DevelopmentCapabilities({
    required this.requiresWine,
    this.metalRenderer = false,
    this.performancePatch = false,
    this.commandShiftFullscreen = false,
  });

  final bool requiresWine;
  final bool metalRenderer;
  final bool performancePatch;
  final bool commandShiftFullscreen;

  static const windows = DevelopmentCapabilities(requiresWine: false);
  static const macOS = DevelopmentCapabilities(
    requiresWine: true,
    metalRenderer: true,
    performancePatch: true,
    commandShiftFullscreen: true,
  );
}
