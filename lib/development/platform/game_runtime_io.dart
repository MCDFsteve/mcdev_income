import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../development_storage.dart';
import '../download_io.dart';
import '../launcher_service.dart' show TestPlayerSkin;
import 'development_capabilities.dart';
import 'game_diagnostics.dart';

/// One backend per test session. Downloads, accounts, mods and world selection
/// remain in the shared launcher; OS paths and process lifetimes live here.
abstract class GameRuntime {
  GameRuntime(this.storage, this.sessionId);
  final DevelopmentStorage storage;
  final String sessionId;
  DevelopmentCapabilities get capabilities;
  Future<GameDiagnostics> createDiagnostics() async =>
      const NoGameDiagnostics();
  String get prefix => p.join(
    storage.paths.prefixes,
    sessionId == 'default' ? 'game' : 'game-$sessionId',
  );
  String get baseRuntime;
  String? activeRuntime;
  String? get wine;
  String get testDirectory;
  String gamePath(String path);
  String testFilePath(String name);
  Future<Map<String, Object>> prepareSkin(
    TestPlayerSkin skin,
    String gameDirectory,
  );
  Future<String> roaming();
  Future<bool> ready();
  Future<void> install(
    http.Client client,
    DownloadControl? control,
    void Function(StorageMigrationProgress) onProgress,
  );
  Future<void> prepare(void Function(StorageMigrationProgress) onProgress);
  Map<String, String> environment({Map<String, String> overrides = const {}});
  Future<Process> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required String version,
    required String displayName,
    required String renderer,
    required bool fullscreenShortcut,
    Map<String, String> overrides = const {},
  });
  Future<void> stop(Process child);
  Future<void> terminateHelpers();
}
