import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/preferences.dart';
import '../storage/file_lock.dart';
import 'development_storage.dart';
import 'download_io.dart';
import 'launcher_service.dart';
import 'mcs_api.dart';
import 'wine_patch_io.dart';

Future<DevelopmentLauncher> openDevelopmentLauncher(
  DevelopmentStorage storage,
  PreferenceStore preferences, {
  Future<String> Function()? cookieProvider,
}) async {
  final launcher = NativeDevelopmentLauncher(
    storage,
    preferences,
    cookieProvider: cookieProvider,
  );
  await launcher.refresh();
  return launcher;
}

/// No game or Wine is an application asset. Their installations are versioned
/// and committed only after verification, leaving previous installations usable.
class NativeDevelopmentLauncher extends DevelopmentLauncher {
  NativeDevelopmentLauncher(
    this.storage,
    this.preferences, {
    http.Client? client,
    Future<String> Function()? cookieProvider,
  }) : api = McsApi(client: client),
       _cookieProvider = cookieProvider ?? (() async => '') {
    selectedVersion = preferences.getString(_versionKey);
  }
  final Future<String> Function() _cookieProvider;
  String? _accountFingerprint;
  final DevelopmentStorage storage;
  final PreferenceStore preferences;
  final McsApi api;
  static const _versionKey = 'development_game_version_v1';
  bool _disposed = false;
  DownloadControl? _control;
  Process? _game;
  bool _stopRequested = false;
  bool _stopping = false;
  ServerSocket? _rpc;
  final List<Socket> _connections = [];
  String get runtime => p.join(storage.paths.runtimes, 'wine-11.0_1-mcs-v1');
  String get wine => p.join(runtime, 'bin/wine');
  String get gamePrefix => p.join(storage.paths.prefixes, 'game');
  String get _lock => storage.lockPath;
  String get _projectsFile => p.join(storage.paths.root, 'projects.json');
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _update(StorageMigrationProgress value) {
    progress = value;
    _notify();
  }

  Future<void> _requireStorage() async {
    if (!(await storage.inspect()).initialized) {
      throw const DevelopmentStorageException('请先配置可用的开发数据目录。');
    }
  }

  Future<void> _operation(Future<void> Function() action) async {
    if (busy || running) {
      throw const DevelopmentStorageException('请等待当前任务完成或退出测试游戏。');
    }
    busy = true;
    error = null;
    notice = null;
    _control = DownloadControl();
    _notify();
    try {
      await withFileLock(_lock, () async {
        await _requireStorage();
        await action();
      }, wait: false);
    } on DownloadCancelled {
      notice = '下载已暂停，重试时会继续。';
    } on FileSystemException {
      error = '无法读写开发目录，请检查磁盘连接、权限和剩余空间。';
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      progress = null;
      _control = null;
      if (_disposed) api.close();
      _notify();
    }
  }

  Future<void> _saveJson(File file, Object value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp-${Random.secure().nextInt(1 << 30)}');
    try {
      await temp.writeAsString(jsonEncode(value), flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> refresh() async {
    await _requireStorage();
    await _refreshAccount();
    runtimeReady = await patchedWineReady(runtime);
    final installed = <LocalGame>[];
    await for (final dir in Directory(
      storage.paths.games,
    ).list(followLinks: false)) {
      if (dir is! Directory || p.basename(dir.path).startsWith('.')) continue;
      if (await File(p.join(dir.path, 'Minecraft.Windows.exe')).exists() &&
          await File(p.join(dir.path, '.mcdev-game.json')).exists()) {
        final metadata = jsonDecode(
          await File(p.join(dir.path, '.mcdev-game.json')).readAsString(),
        );
        installed.add(
          LocalGame(
            p.basename(dir.path),
            dir.path,
            architecture:
                GameArchitecture.values
                    .where((value) => value.name == metadata['architecture'])
                    .firstOrNull ??
                GameArchitecture.unknown,
            channels: [
              for (final value in GameChannel.values)
                if (metadata['channels'] is List &&
                    (metadata['channels'] as List).contains(value.name))
                  value,
            ],
          ),
        );
      }
    }
    installed.sort((a, b) => compareGameVersions(b.version, a.version));
    games = installed;
    if (!games.any((g) => g.version == selectedVersion)) {
      selectedVersion = games.isEmpty ? null : games.first.version;
      if (selectedVersion != null &&
          !await preferences.setString(_versionKey, selectedVersion!)) {
        throw const DevelopmentStorageException('无法保存游戏版本选择。');
      }
    }
    final manifest = File(_projectsFile);
    final loaded = <ModPack>[];
    final selected = <String>{};
    if (await manifest.exists()) {
      for (final row in jsonDecode(await manifest.readAsString()) as List) {
        if (row['selected'] == true) selected.add(row['uuid']);
        loaded.add(
          ModPack(
            name: row['name'],
            uuid: row['uuid'],
            version: (row['version'] as List).cast<int>(),
            type: row['type'],
            directory: _expandProject(row['path']),
            projectRoot: row['projectRoot'] is String
                ? _expandProject(row['projectRoot'])
                : null,
          ),
        );
      }
    }
    packs = loaded;
    selectedPacks
      ..clear()
      ..addAll(
        selected.where((uuid) => packs.any((pack) => pack.uuid == uuid)),
      );
    _notify();
  }

  String _expandProject(String value) =>
      p.isAbsolute(value) ? value : p.join(storage.paths.root, value);
  Future<void> _saveProjects() => _saveJson(File(_projectsFile), [
    for (final pack in packs)
      {
        'name': pack.name,
        'uuid': pack.uuid,
        'version': pack.version,
        'type': pack.type,
        'selected': selectedPacks.contains(pack.uuid),
        'path': p.isWithin(storage.paths.root, pack.directory)
            ? p.relative(pack.directory, from: storage.paths.root)
            : pack.directory,
        if (pack.projectRoot != null)
          'projectRoot': p.isWithin(storage.paths.root, pack.projectRoot!)
              ? p.relative(pack.projectRoot!, from: storage.paths.root)
              : pack.projectRoot,
      },
  ]);

  @override
  Future<void> chooseVersion(String version) => _operation(() async {
    if (!games.any((game) => game.version == version)) {
      throw const DevelopmentStorageException('所选游戏版本不可用。');
    }
    if (!await preferences.setString(_versionKey, version)) {
      throw const DevelopmentStorageException('无法保存游戏版本选择。');
    }
    selectedVersion = version;
  });

  @override
  Future<void> togglePacks(Iterable<String> uuids, bool selected) =>
      _operation(() async {
        final previous = {...selectedPacks};
        final known = uuids
            .where((uuid) => packs.any((pack) => pack.uuid == uuid))
            .toList();
        selected ? selectedPacks.addAll(known) : selectedPacks.removeAll(known);
        try {
          await _saveProjects();
        } catch (_) {
          selectedPacks
            ..clear()
            ..addAll(previous);
          rethrow;
        }
      });

  Future<String> _refreshAccount() async {
    final cookie = await _cookieProvider();
    final fingerprint = sha256.convert(utf8.encode(cookie)).toString();
    if (fingerprint != _accountFingerprint) {
      api.session = null;
      catalog = null;
      _accountFingerprint = fingerprint;
    }
    loggedIn = cookie.isNotEmpty;
    return cookie;
  }

  Future<void> _connectAccount() async {
    final cookie = await _refreshAccount();
    final expiry = api.session?.expiresAt ?? 0;
    if (api.session == null ||
        expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60) {
      _update(const StorageMigrationProgress('验证现有开发者登录'));
      await api.authenticateDeveloper(cookie);
    }
  }

  @override
  Future<void> installWine() => _operation(() async {
    if (await patchedWineReady(runtime)) {
      runtimeReady = true;
      notice = 'Wine 已就绪。';
      return;
    }
    final archive = File(
      p.join(storage.paths.downloads, 'wine-stable-11.0_1.tar.xz'),
    );
    // University MacPorts archives depend on /opt/local and cannot be used here.
    // Every transport serves the exact same hash-pinned upstream portable asset.
    var downloaded = false;
    for (final url in [
      wineArchiveUrl,
      'https://gh-proxy.com/$wineArchiveUrl',
      'https://ghfast.top/$wineArchiveUrl',
    ]) {
      try {
        await downloadManaged(
          api.client,
          Uri.parse(url),
          archive,
          expectedSha256: wineArchiveHash,
          control: _control,
          onProgress: _update,
        );
        downloaded = true;
        break;
      } on DownloadCancelled {
        rethrow;
      } catch (_) {
        _control?.check();
      }
    }
    if (!downloaded) {
      throw const DevelopmentStorageException('Wine 下载线路均不可用，请稍后重试。');
    }
    final stage = await Directory(
      storage.paths.runtimes,
    ).createTemp('.wine-install-');
    try {
      _update(const StorageMigrationProgress('解压 Wine'));
      final extracted = await Process.run('/usr/bin/tar', [
        '-xJf',
        archive.path,
        '-C',
        stage.path,
      ]);
      if (extracted.exitCode != 0) {
        throw const DevelopmentStorageException('Wine 解压失败。');
      }
      final payload = p.join(
        stage.path,
        'Wine Stable.app',
        'Contents',
        'Resources',
        'wine',
      );
      _update(const StorageMigrationProgress('安装启动补丁'));
      await patchWine11(payload);
      _control?.check();
      if (await Directory(runtime).exists()) {
        throw const DevelopmentStorageException(
          '已有 Wine 目录校验未通过，请在 Finder 中保留备份后移走该目录再重试。',
        );
      }
      await Directory(payload).rename(runtime);
      runtimeReady = true;
      notice = 'Wine 与启动补丁已安装。';
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  });

  Map<String, String> _env(
    String prefix, {
    Map<String, String> overrides = const {},
  }) => {
    ...Platform.environment,
    'WINEPREFIX': prefix,
    'TMPDIR': p.join(storage.paths.prefixes, '.wine_tmp'),
    'WINELOADER': wine,
    'WINEDEBUG': '-all',
    'MVK_CONFIG_LOG_LEVEL': '1',
    'WINEDLLOVERRIDES': 'kerberos=',
    'LC_ALL': 'C',
    ...overrides,
  };

  Future<void> _killPrefix(String prefix) async {
    await Process.run(p.join(p.dirname(wine), 'wineserver'), [
      '-k',
    ], environment: _env(prefix)).timeout(const Duration(seconds: 15));
  }

  Future<ProcessResult> _wineRun(
    String prefix,
    List<String> args, {
    Map<String, String> overrides = const {},
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    await Directory(
      p.join(storage.paths.prefixes, '.wine_tmp'),
    ).create(recursive: true);
    final child = await Process.start(
      wine,
      args,
      environment: _env(prefix, overrides: overrides),
      workingDirectory: workingDirectory,
    );
    // Never persist native SDK/dependency output: it may include account details.
    final drains = [child.stdout.drain<void>(), child.stderr.drain<void>()];
    try {
      final code = await child.exitCode.timeout(timeout);
      await Future.wait(drains).timeout(const Duration(seconds: 15));
      return ProcessResult(child.pid, code, '', '');
    } on TimeoutException {
      child.kill(ProcessSignal.sigterm);
      await _killPrefix(prefix);
      throw const DevelopmentStorageException('Windows 依赖操作超时，请重试；已下载的安装包会保留。');
    }
  }

  Future<void> _ensurePrefix(String prefix) async {
    if (!await patchedWineReady(runtime)) {
      throw const DevelopmentStorageException('请先安装 Wine。');
    }
    final supported = await Process.run(wine, ['--version']);
    if (supported.exitCode != 0) {
      throw const DevelopmentStorageException(
        'Wine 无法运行。Apple 芯片 Mac 请先安装 Rosetta 2，再检查运行环境。',
      );
    }
    await Directory(prefix).create(recursive: true);
    if (!await File(p.join(prefix, 'system.reg')).exists()) {
      _update(const StorageMigrationProgress('准备 Windows 容器'));
      final result = await _wineRun(
        prefix,
        ['wineboot', '-u'],
        overrides: {'WINEDLLOVERRIDES': 'mscoree,mshtml='},
      );
      if (result.exitCode != 0) {
        throw const DevelopmentStorageException('Windows 容器初始化失败。');
      }
    }
  }

  String _winPath(String path) => 'Z:${p.absolute(path).replaceAll('/', '\\')}';

  Future<void> _loadCatalog() async {
    await _connectAccount();
    _update(const StorageMigrationProgress('查询可下载的游戏版本'));
    catalog = await api.catalog();
  }

  @override
  Future<void> queryLatest() => queryVersions();

  @override
  Future<void> queryVersions() => _operation(() async {
    await _loadCatalog();
    notice = '已获取 ${availableGames.length} 个可下载版本。';
  });

  @override
  Future<void> installLatest() => _operation(() async {
    await _loadCatalog();
    final package = catalog!.stable;
    if (package == null) {
      throw const DevelopmentStorageException('官方稳定版下载描述缺失。');
    }
    await _installPackage(package);
  });

  @override
  Future<void> installVersion(String version) => _operation(() async {
    // Refresh the official entry and download exactly the user's choice. Never
    // silently substitute stable when a preview or historical entry disappears.
    await _loadCatalog();
    final package = availableGames
        .where((package) => package.version == version)
        .firstOrNull;
    if (package == null) {
      throw const DevelopmentStorageException('该版本已不在官方清单中，请刷新版本列表。');
    }
    await _installPackage(package);
  });

  Future<void> _installPackage(GamePackage package) async {
    final destination = Directory(p.join(storage.paths.games, package.version));
    if (await File(p.join(destination.path, '.mcdev-game.json')).exists()) {
      await refresh();
      notice = '该游戏版本已安装，可在启动区切换使用。';
      return;
    }
    final patchFile = File(
      p.join(storage.paths.downloads, '${package.version}-patch.json'),
    );
    await downloadManaged(
      api.client,
      signMcsDownload(package.patchUrl),
      patchFile,
      expectedMd5: package.patchMd5,
      control: _control,
      onProgress: _update,
    );
    final patch = await patchFile.readAsString();
    final hashes = parseGamePatch(patch);
    if (await destination.exists()) {
      throw const DevelopmentStorageException('目标游戏目录已有未完成的数据，请保留备份后移走该目录再重试。');
    }
    final zip = File(
      p.join(storage.paths.downloads, 'minecraft-${package.version}.zip'),
    );
    await downloadManaged(
      api.client,
      signMcsDownload(package.zipUrl),
      zip,
      control: _control,
      onProgress: _update,
    );
    final stage = await Directory(
      storage.paths.games,
    ).createTemp('.game-install-');
    try {
      _update(const StorageMigrationProgress('解压游戏包'));
      final input = InputFileStream(zip.path);
      try {
        await extractZipSafe(
          ZipDecoder().decodeStream(input),
          stage.path,
          control: _control,
        );
      } finally {
        input.close();
      }
      var gameRoot = stage.path;
      if (!await File(p.join(gameRoot, 'Minecraft.Windows.exe')).exists()) {
        final candidates = <Directory>[];
        await for (final entry in stage.list(followLinks: false)) {
          if (entry is Directory &&
              await File(
                p.join(entry.path, 'Minecraft.Windows.exe'),
              ).exists()) {
            candidates.add(entry);
          }
        }
        if (candidates.length != 1) {
          throw const DevelopmentStorageException('游戏包中没有唯一的游戏目录。');
        }
        gameRoot = candidates.single.path;
      }
      await verifyGameFiles(
        gameRoot,
        hashes,
        control: _control,
        onProgress: _update,
      );
      await File(
        p.join(gameRoot, 'patch.json'),
      ).writeAsString(patch, flush: true);
      await _saveJson(File(p.join(gameRoot, '.mcdev-game.json')), {
        'version': package.version,
        'patch_md5': package.patchMd5,
        'architecture': package.architecture.name,
        'channels': package.channels.map((channel) => channel.name).toList(),
        'installed_at': DateTime.now().toUtc().toIso8601String(),
      });
      await Directory(gameRoot).rename(destination.path);
      await refresh();
      notice = '游戏 ${package.version} 已安装。';
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  @override
  Future<void> importGame(String directory) => _operation(() async {
    final source = await Directory(directory).resolveSymbolicLinks();
    final patchFile = File(p.join(source, 'patch.json'));
    if (!await File(p.join(source, 'Minecraft.Windows.exe')).exists() ||
        !await patchFile.exists()) {
      throw const DevelopmentStorageException(
        '请选择包含 Minecraft.Windows.exe 和 patch.json 的完整游戏目录。',
      );
    }
    final version = p.basename(source);
    if (!RegExp(r'^\d+(\.\d+){1,5}$').hasMatch(version)) {
      throw const DevelopmentStorageException('游戏文件夹名称必须是完整版本号。');
    }
    final target = Directory(p.join(storage.paths.games, version));
    if (await target.exists()) {
      throw const DevelopmentStorageException('此版本已有本机安装，未覆盖。');
    }
    final stage = await Directory(
      storage.paths.games,
    ).createTemp('.game-import-');
    try {
      _update(const StorageMigrationProgress('复制已有游戏'));
      if ((await Process.run('/usr/bin/ditto', [
            '--noextattr',
            '--norsrc',
            source,
            stage.path,
          ])).exitCode !=
          0) {
        throw const DevelopmentStorageException('复制已有游戏失败。');
      }
      await verifyGameFiles(
        stage.path,
        parseGamePatch(await patchFile.readAsString()),
        control: _control,
        onProgress: _update,
      );
      await _saveJson(File(p.join(stage.path, '.mcdev-game.json')), {
        'version': version,
        'imported': true,
      });
      await stage.rename(target.path);
      await refresh();
      notice = '已有游戏已导入。';
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  });

  @override
  Future<void> importMods(String path) => _operation(() async {
    var source = p.absolute(path);
    final type = await FileSystemEntity.type(source);
    Directory? stage;
    if (type == FileSystemEntityType.file) {
      final projects = await Directory(
        p.join(storage.paths.root, 'projects'),
      ).create(recursive: true);
      stage = await projects.createTemp('.import-');
      final input = InputFileStream(source);
      try {
        await extractZipSafe(
          ZipDecoder().decodeStream(input),
          stage.path,
          control: _control,
        );
      } finally {
        input.close();
      }
      source = stage.path;
    } else if (type != FileSystemEntityType.directory) {
      throw const DevelopmentStorageException('模组路径不可访问。');
    }
    try {
      final imported = await discoverModPacks(source);
      if (imported.isEmpty) {
        throw const DevelopmentStorageException(
          '没有找到有效 manifest.json；支持资源包、行为包、mcpack 和 mcaddon。',
        );
      }
      String? committed;
      if (stage != null) {
        committed = p.join(
          stage.parent.path,
          'import-${Random.secure().nextInt(1 << 30)}',
        );
        await stage.rename(committed);
      }
      final next = [...packs];
      for (final pack in imported) {
        final previous = next.where((old) => old.uuid == pack.uuid).firstOrNull;
        next.removeWhere((old) => old.uuid == pack.uuid);
        final actual = committed == null
            ? pack.directory
            : p.join(committed, p.relative(pack.directory, from: source));
        next.add(
          ModPack(
            name: pack.name,
            uuid: pack.uuid,
            version: pack.version,
            type: pack.type,
            directory: actual,
            projectRoot: pack.projectRoot == null
                ? previous?.projectRoot
                : committed == null
                ? pack.projectRoot
                : p.join(
                    committed,
                    p.relative(pack.projectRoot!, from: source),
                  ),
          ),
        );
        selectedPacks.add(pack.uuid);
      }
      packs = next;
      await _saveProjects();
      notice = '已导入 ${groupModProjects(imported).length} 个项目。测试前同步源文件。';
    } finally {
      if (stage != null && await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  });

  @override
  Future<void> removePack(String uuid) => removePacks([uuid]);

  @override
  Future<void> removePacks(Iterable<String> uuids) => _operation(() async {
    final ids = uuids.toSet();
    final previous = [...packs];
    final selected = {...selectedPacks};
    packs = packs.where((pack) => !ids.contains(pack.uuid)).toList();
    selectedPacks.removeAll(ids);
    try {
      await _saveProjects();
      notice = '项目已从列表移除，源文件保留。';
    } catch (_) {
      packs = previous;
      selectedPacks
        ..clear()
        ..addAll(selected);
      rethrow;
    }
  });

  Future<String> _roaming() async {
    final users = Directory(p.join(gamePrefix, 'drive_c', 'users'));
    await for (final dir in users.list(followLinks: false)) {
      if (dir is Directory &&
          ![
            'Public',
            'Default',
            'Default User',
            'All Users',
          ].contains(p.basename(dir.path))) {
        return p.join(dir.path, 'AppData', 'Roaming');
      }
    }
    throw const DevelopmentStorageException('Windows 用户目录尚未创建。');
  }

  @override
  Future<void> launchTest({
    required String worldName,
    required bool creative,
    required bool menuOnly,
  }) => _operation(() async {
    final game = games
        .where((game) => game.version == selectedVersion)
        .firstOrNull;
    if (game == null) throw const DevelopmentStorageException('请先下载或导入游戏。');
    await _connectAccount();
    await _ensurePrefix(gamePrefix);
    final chosen = packs
        .where((pack) => selectedPacks.contains(pack.uuid))
        .toList();
    final dataRoot = p.join(
      await _roaming(),
      'MinecraftPE_Netease',
      'games',
      'com.netease',
    );
    final behavior = <String>[], resources = <String>[];
    for (final pack in chosen) {
      _control?.check();
      final current = (await discoverModPacks(
        pack.directory,
      )).where((item) => item.uuid == pack.uuid).firstOrNull;
      if (current == null) {
        throw DevelopmentStorageException(
          '模组 ${pack.name} 的源文件已变化或无法访问，请重新导入。',
        );
      }
      final name = 'mcdev_${pack.uuid}';
      final target = Directory(
        p.join(
          dataRoot,
          pack.type == 'resources' ? 'resource_packs' : 'behavior_packs',
          name,
        ),
      );
      await target.parent.create(recursive: true);
      final staging = await target.parent.createTemp('.pack-');
      final backup = Directory('${target.path}.previous');
      try {
        if ((await Process.run('/usr/bin/ditto', [
              '--noextattr',
              '--norsrc',
              pack.directory,
              staging.path,
            ])).exitCode !=
            0) {
          throw DevelopmentStorageException('装配模组失败：${pack.name}');
        }
        await rejectTreeLinks(staging.path);
        if (await backup.exists()) await backup.delete(recursive: true);
        if (await target.exists()) await target.rename(backup.path);
        try {
          await staging.rename(target.path);
        } catch (_) {
          if (await backup.exists()) await backup.rename(target.path);
          rethrow;
        }
        if (await backup.exists()) await backup.delete(recursive: true);
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
      (pack.type == 'resources' ? resources : behavior).add(name);
    }
    IOSink? output;
    final subscriptions = <StreamSubscription<List<int>>>[];
    _stopRequested = false;
    try {
      _rpc = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _rpc!.listen((socket) {
        _connections.add(socket);
        socket.listen(
          (_) {},
          onError: (_) {},
          onDone: () => _connections.remove(socket),
        );
      });
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final config = File(
        p.join(gamePrefix, 'drive_c', 'MCDevTests', 'test.cppconfig'),
      );
      final args = <String>[
        'dc_tag1=${menuOnly ? 'mod_pc_no_launcher' : 'studio_no_launcher'}',
      ];
      if (!menuOnly) {
        await _saveJson(config, {
          'version': game.version,
          'MainComponentId': '',
          'LocalComponentPathsDict': {},
          'path': _winPath(config.path),
          'world_info': {
            'level_id': 'mcdev_test',
            'name': worldName.trim().isEmpty ? '模组测试' : worldName.trim(),
            'seed': '',
            'game_type': creative ? 1 : 0,
            'difficulty': 2,
            'permission_level': 1,
            'cheat': true,
            'cheat_info': {
              'pvp': true,
              'show_coordinates': true,
              'daylight_cycle': true,
              'fire_spreads': true,
              'tnt_explodes': true,
              'mob_spawn': true,
              'natural_regeneration': true,
              'mob_loot': true,
              'mob_griefing': true,
              'tile_drops': true,
              'entities_drop_loot': true,
              'weather_cycle': true,
              'command_blocks_enabled': true,
              'random_tick_speed': 1,
            },
            'resource_packs': resources,
            'behavior_packs': behavior,
            'world_type': 1,
            'start_with_map': false,
            'bonus_items': false,
          },
          'room_info': {
            'ip': '',
            'port': 0,
            'muiltClient': false,
            'token': base64Encode(
              List<int>.generate(32, (_) => Random.secure().nextInt(256)),
            ),
            'room_id': 0,
            'host_id': 0,
            'allow_pe': true,
            'is_pe': false,
            'item_ids': [],
          },
          'player_info': {
            'user_id':
                ((int.tryParse(api.session?.id ?? '') ?? 0) | 0x80000000) &
                0xffffffff,
            'user_name': 'Developer',
            'urs': '',
          },
          'skin_info': {
            'skin': _winPath(
              p.join(
                game.directory,
                'data',
                'skin_packs',
                'vanilla',
                'steve.png',
              ),
            ),
          },
          'anti_addiction_info': {
            'enable': false,
            'left_time': 0,
            'exp_multiplier': 1.0,
            'block_multplier': 1.0,
            'first_message': '',
          },
          'misc': {
            'multiplayer_game_type': 0,
            'launcher_port': _rpc!.port,
            'auth_server_url': 'https://g79authexpr1.nie.netease.com',
            'sensitive_word_file': '',
            'is_store_enabled': 1,
          },
          'web_server_url':
              api.web?.toString() ?? 'https://x19mclexpr.nie.netease.com',
          'core_server_url': 'https://x19exprcore.nie.netease.com:8443',
          'vip_using_mod': chosen.map((pack) => pack.uuid).toList(),
          'isCloud': false,
          'last_play_time': 0,
        });
        args.add('config=${_winPath(config.path)}');
      }
      logPath = p.join(storage.paths.logs, 'test-$stamp.log');
      args.add(
        'errorlog=${_winPath(p.join(storage.paths.logs, 'game-$stamp.log'))}',
      );
      await Directory(p.dirname(logPath!)).create(recursive: true);
      final assertDir = Directory(
        p.join(gamePrefix, 'drive_c', 'MCDevTests', 'assertions'),
      );
      await assertDir.create(recursive: true);
      await _saveJson(File(p.join(game.directory, 'netease_data.json')), {
        'Uid': api.session?.id ?? '',
        'Urs': '',
        'ServerName': 'MCS',
        'Product': 'mcstudio_mod_pc',
        'AssertCacheDir': _winPath(assertDir.path),
      });
      output = File(logPath!).openWrite();
      _game = await Process.start(
        wine,
        [_winPath(p.join(game.directory, 'Minecraft.Windows.exe')), ...args],
        workingDirectory: game.directory,
        environment: _env(gamePrefix),
      );
      running = true;
      notice = '测试游戏已启动。';
      _notify();
      final drains = <Future<void>>[];
      for (final stream in [_game!.stdout, _game!.stderr]) {
        final done = Completer<void>();
        subscriptions.add(
          stream.listen(
            output.add,
            onError: (Object e, StackTrace st) {
              if (!done.isCompleted) done.completeError(e, st);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
          ),
        );
        drains.add(done.future);
      }
      final drained = Future.wait(drains);
      // Attach immediately so an early stream error cannot become unhandled.
      unawaited(
        drained.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      progress = null;
      final code = await _game!.exitCode;
      try {
        await drained.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        await _killPrefix(gamePrefix);
      }
      if (code != 0 && !_stopRequested) {
        error = '测试游戏退出（$code），请打开日志查看。';
      } else {
        notice = '测试游戏已退出，存档保留在当前容器中。';
      }
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      try {
        await output?.close();
      } finally {
        running = false;
        _game = null;
        _stopping = false;
        await _closeRpc();
        _notify();
      }
    }
  });

  Future<void> _closeRpc() async {
    for (final socket in [..._connections]) {
      socket.destroy();
    }
    _connections.clear();
    await _rpc?.close();
    _rpc = null;
  }

  @override
  Future<void> stopGame() async {
    final child = _game;
    if (child == null || _stopping) return;
    _stopping = true;
    _stopRequested = true;
    try {
      // WM_CLOSE first; target this application's isolated prefix only.
      await _wineRun(gamePrefix, [
        'taskkill',
        '/im',
        'Minecraft.Windows.exe',
      ], timeout: const Duration(seconds: 15));
      await child.exitCode.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      await _killPrefix(gamePrefix);
    } on DevelopmentStorageException {
      await _killPrefix(gamePrefix);
    } finally {
      _stopping = false;
    }
  }

  @override
  void cancel() {
    _control?.cancelled = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _control?.cancelled = true;
    if (!running && !busy) api.close();
    super.dispose();
  }
}

String safeArchivePath(String name) {
  final value = name.replaceAll('\\', '/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value) ||
      value.split('/').contains('..') ||
      value.contains('\u0000')) {
    throw const DevelopmentStorageException('归档包含越界路径，未安装。');
  }
  return p.posix.normalize(value);
}

Future<void> extractZipSafe(
  Archive archive,
  String target, {
  DownloadControl? control,
}) async {
  final seen = <String>{};
  // Validate every entry before any write, including case-insensitive macOS conflicts.
  for (final entry in archive) {
    final relative = safeArchivePath(entry.name);
    if (entry.isSymbolicLink || !seen.add(relative.toLowerCase())) {
      throw const DevelopmentStorageException('归档包含链接或重复路径，未安装。');
    }
  }
  await Directory(target).create(recursive: true);
  for (final entry in archive) {
    control?.check();
    final relative = safeArchivePath(entry.name);
    final out = p.join(target, relative);
    if (!p.isWithin(p.normalize(target), p.normalize(out))) {
      throw const DevelopmentStorageException('归档路径不合法。');
    }
    if (entry.isFile) {
      await File(out).parent.create(recursive: true);
      final stream = OutputFileStream(out);
      try {
        entry.writeContent(stream);
      } finally {
        stream.close();
      }
    } else {
      await Directory(out).create(recursive: true);
    }
  }
}

Map<String, String> parseGamePatch(String text) {
  final data = jsonDecode(text);
  final entries = data['md5'];
  if (entries is! Map || entries.isEmpty) {
    throw const DevelopmentStorageException('游戏补丁清单无效。');
  }
  final hashes = <String, String>{};
  final lower = <String>{};
  for (final entry in entries.entries) {
    final key = safeArchivePath(entry.key as String);
    if (entry.value is! String ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(entry.value) ||
        !lower.add(key.toLowerCase())) {
      throw const DevelopmentStorageException('游戏清单包含无效摘要或重复路径。');
    }
    hashes[key] = entry.value.toLowerCase();
  }
  if (!hashes.containsKey('Minecraft.Windows.exe')) {
    throw const DevelopmentStorageException('游戏清单缺少主程序。');
  }
  return hashes;
}

Future<void> verifyGameFiles(
  String root,
  Map<String, String> hashes, {
  DownloadControl? control,
  void Function(StorageMigrationProgress)? onProgress,
}) async {
  await rejectTreeLinks(root);
  // The authoritative patch is the allowlist: extra DLLs must not be loaded.
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File) {
      final relative = p.relative(entity.path, from: root);
      if (!hashes.containsKey(relative) &&
          !['patch.json', '.mcdev-game.json'].contains(relative)) {
        await entity.delete();
      }
    }
  }
  var count = 0;
  for (final entry in hashes.entries) {
    control?.check();
    final path = p.join(root, entry.key);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        (await md5.bind(File(path).openRead()).first).toString() !=
            entry.value) {
      throw DevelopmentStorageException('游戏文件校验失败：${entry.key}');
    }
    count++;
    if (count % 100 == 0 || count == hashes.length) {
      onProgress?.call(
        StorageMigrationProgress(
          '校验游戏文件',
          completed: count,
          total: hashes.length,
        ),
      );
    }
  }
}

Future<void> rejectTreeLinks(String root) async {
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw const DevelopmentStorageException('游戏或模组文件包含符号链接，请使用完整的实际文件。');
    }
  }
}

Future<List<ModPack>> discoverModPacks(String root) async {
  final result = <ModPack>[];
  final uuids = <String>{};
  Future<void> visit(String directory, int depth) async {
    final file = File(p.join(directory, 'manifest.json'));
    if (await file.exists()) {
      final manifest = jsonDecode(await file.readAsString());
      final header = manifest['header'];
      final modules = manifest['modules'];
      if (header is! Map || modules is! List) {
        throw const DevelopmentStorageException('模组 manifest.json 结构无效。');
      }
      final uuid = header['uuid'];
      final version = header['version'];
      if (uuid is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
          ).hasMatch(uuid) ||
          version is! List ||
          version.length != 3 ||
          version.any((v) => v is! int || v < 0)) {
        throw const DevelopmentStorageException('模组 UUID 或版本无效。');
      }
      if (modules.isEmpty ||
          modules.any((m) => m is! Map || m['type'] is! String)) {
        throw const DevelopmentStorageException('模组模块声明无效。');
      }
      final types = modules.map((m) => m['type']).toSet();
      final type = types.contains('resources')
          ? 'resources'
          : types.any((t) => t == 'data' || t == 'script')
          ? 'data'
          : null;
      if (type == null) {
        throw const DevelopmentStorageException('模组不包含可测试的资源、行为或脚本模块。');
      }
      if (!uuids.add(uuid.toLowerCase())) {
        throw const DevelopmentStorageException('项目中存在重复 UUID。');
      }
      result.add(
        ModPack(
          name: header['name']?.toString() ?? p.basename(directory),
          uuid: uuid.toLowerCase(),
          version: version.cast<int>(),
          type: type,
          directory: directory,
        ),
      );
      return;
    }
    if (depth == 0) return;
    await for (final entry in Directory(directory).list(followLinks: false)) {
      if (entry is Directory &&
          !p.basename(entry.path).startsWith('.') &&
          !['build', 'node_modules'].contains(p.basename(entry.path))) {
        await visit(entry.path, depth - 1);
      }
    }
  }

  await visit(await Directory(root).resolveSymbolicLinks(), 4);
  // Each directory containing sibling packs is a project. Standard BP/RP
  // containers share their outer project directory. A single-pack import keeps
  // legacy name-based matching, allowing its companion to be imported later.
  if (result.length < 2) return result;
  return [
    for (final pack in result)
      ModPack(
        name: pack.name,
        uuid: pack.uuid,
        version: pack.version,
        type: pack.type,
        directory: pack.directory,
        projectRoot:
            [
              'behavior_packs',
              'resource_packs',
            ].contains(p.basename(p.dirname(pack.directory)).toLowerCase())
            ? p.dirname(p.dirname(pack.directory))
            : p.dirname(pack.directory),
      ),
  ];
}
