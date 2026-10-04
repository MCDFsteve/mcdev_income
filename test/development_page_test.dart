import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcdev_income/main.dart';
import 'package:mcdev_income/development/development_storage.dart';
import 'package:mcdev_income/development/development_panel.dart';
import 'package:mcdev_income/development/storage_backend_io.dart';
import 'development_test.dart' show MemoryPreferences;
import 'development_widget_test.dart' show host;

class SetupStorage extends NativeDevelopmentStorage {
  SetupStorage({
    required super.preferences,
    required super.defaultRoot,
    required super.lockPath,
  });

  int initializations = 0;
  bool fail = false;

  @override
  Future<void> initialize({String? root}) async {
    initializations++;
    if (fail) throw const DevelopmentStorageException('目录不可写');
    await super.initialize(root: root);
  }
}

Future<void> settlePage(WidgetTester tester) async {
  // Real disk I/O must run outside the widget binding's fake async clock.
  await tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.text('正在读取开发环境…').evaluate().isEmpty &&
          (find.byType(DevelopmentEnvironmentPanel).evaluate().isEmpty ||
              find.text('本地项目').evaluate().isNotEmpty)) {
        return;
      }
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  late Directory temp;
  late MemoryPreferences preferences;
  late SetupStorage storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('mcdev-page-');
    preferences = MemoryPreferences();
    storage = SetupStorage(
      preferences: preferences,
      defaultRoot: p.join(temp.path, 'development'),
      lockPath: p.join(temp.path, 'config', 'storage.lock'),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        HomeShell(
          developmentSupported: true,
          developmentPageBuilder: (_) =>
              DevelopmentPage(storageFactory: () async => storage),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(storage.initializations, 0);
    await tester.tap(find.text('开发'));
    await settlePage(tester);
  }

  testWidgets(
    'fresh development tab initializes storage and shows full workflow',
    (tester) async {
      await openPage(tester);
      expect(storage.initializations, 1);
      expect(find.text('创建此目录'), findsNothing);
      expect(find.text('游戏版本'), findsOneWidget);
      expect(find.text('浏览可下载版本').hitTestable(), findsOneWidget);
      expect(find.text('导入项目文件夹').hitTestable(), findsOneWidget);
      expect(find.text('启动游戏'), findsOneWidget);
      expect(find.text('安装游戏').hitTestable(), findsOneWidget);
      await tester.tap(find.text('刷新状态'));
      await settlePage(tester);
      expect(storage.initializations, 1);
      expect(tester.takeException(), isNull);
    },
    skip: !(Platform.isWindows || Platform.isMacOS),
  );

  testWidgets(
    'unavailable saved location is preserved with recovery controls',
    (tester) async {
      preferences.values[DevelopmentStorage.preferenceKey] = storage.paths.root;
      await openPage(tester);
      expect(storage.initializations, 0);
      expect(find.textContaining('数据目录暂不可访问'), findsOneWidget);
      expect(find.text('管理目录').hitTestable(), findsOneWidget);
      expect(
        await tester.runAsync(() => Directory(storage.paths.root).exists()),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid existing default is not overwritten', (tester) async {
    final keep = File(p.join(storage.paths.root, 'keep.txt'));
    await tester.runAsync(() async {
      await Directory(storage.paths.root).create();
      await keep.writeAsString('keep');
    });
    await openPage(tester);
    expect(storage.initializations, 0);
    expect(find.textContaining('此目录不是本应用创建'), findsOneWidget);
    expect(await tester.runAsync(keep.readAsString), 'keep');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed automatic setup retains controls and can be retried',
    (tester) async {
      storage.fail = true;
      await openPage(tester);
      expect(storage.initializations, 1);
      expect(find.text('目录不可写'), findsOneWidget);
      expect(find.text('管理目录').hitTestable(), findsOneWidget);
      expect(find.text('创建此目录').hitTestable(), findsOneWidget);
      storage.fail = false;
      await tester.tap(find.text('刷新状态'));
      await settlePage(tester);
      expect(storage.initializations, 2);
      expect(find.text('目录不可写'), findsNothing);
      expect(find.text('本地项目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !(Platform.isWindows || Platform.isMacOS),
  );
}
