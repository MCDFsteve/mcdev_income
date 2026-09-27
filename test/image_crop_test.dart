import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcdev_income/utils/image_crop.dart';
import 'package:mcdev_income/widgets/resource_image_crop_dialog.dart';
import 'package:oreui_flutter/oreui_flutter.dart';

Future<ui.Image> sampleImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 80, 100),
    Paint()..color = const Color(0xffff0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(80, 0, 80, 100),
    Paint()..color = const Color(0xff0000ff),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(160, 100);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> samplePng() async {
  final image = await sampleImage();
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<ui.Image> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<void> waitForCrop(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byKey(const ValueKey('image-crop-canvas')).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Image crop did not finish decoding');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'crop stays inside source and keeps required aspect under extreme edits',
    () {
      final random = math.Random(43);
      for (final aspect in [null, 16 / 9, 1.0, 9 / 16]) {
        for (final size in [
          const Size(160, 100),
          const Size(1, 5),
          const Size(8000, 500),
        ]) {
          final selection = ImageCropSelection(size, aspectRatio: aspect);
          for (var i = 0; i < 250; i++) {
            final delta = Offset(
              random.nextDouble() * 10000 - 5000,
              random.nextDouble() * 10000 - 5000,
            );
            switch (i % 4) {
              case 0:
                selection.resize(selection.rect, random.nextInt(4), delta);
              case 1:
                selection.move(selection.rect, delta);
              case 2:
                selection.zoom(
                  selection.rect,
                  math.exp(random.nextDouble() * 12 - 6),
                );
              case 3:
                selection.rotate();
            }
            final rect = selection.rect;
            expect(rect.left, greaterThanOrEqualTo(-1e-8));
            expect(rect.top, greaterThanOrEqualTo(-1e-8));
            expect(rect.right, lessThanOrEqualTo(selection.size.width + 1e-8));
            expect(
              rect.bottom,
              lessThanOrEqualTo(selection.size.height + 1e-8),
            );
            expect(rect.width, greaterThan(0));
            expect(rect.height, greaterThan(0));
            if (aspect != null) {
              expect(rect.width / rect.height, closeTo(aspect, 1e-8));
            }
          }
        }
      }
    },
  );

  test(
    'export selects actual pixels and upscales to exact channel dimensions',
    () async {
      final image = await sampleImage();
      addTearDown(image.dispose);
      final selection = ImageCropSelection(
        const Size(160, 100),
        aspectRatio: 16 / 9,
      );
      selection.zoom(selection.rect, .4);
      selection.move(selection.rect, const Offset(999, 0));
      final output = await decodePng(
        await encodeImageCrop(image, selection, width: 992, height: 558),
      );
      addTearDown(output.dispose);
      expect(
        Size(output.width.toDouble(), output.height.toDouble()),
        const Size(992, 558),
      );
      final rgba = (await output.toByteData())!.buffer.asUint8List();
      for (final pixel in [0, 991, 992 * 280 + 400, 992 * 558 - 1]) {
        expect(rgba.sublist(pixel * 4, pixel * 4 + 4), [0, 0, 255, 255]);
      }
    },
  );

  test('all rotations export correctly oriented opaque content', () async {
    final image = await sampleImage();
    addTearDown(image.dispose);
    final selection = ImageCropSelection(const Size(160, 100));
    for (var turn = 0; turn < 4; turn++) {
      final output = await decodePng(await encodeImageCrop(image, selection));
      final rgba = (await output.toByteData())!.buffer.asUint8List();
      expect(output.width, turn.isOdd ? 100 : 160);
      expect(output.height, turn.isOdd ? 160 : 100);
      expect(
        rgba.sublist(0, 4),
        turn < 2 ? [255, 0, 0, 255] : [0, 0, 255, 255],
      );
      expect(
        rgba.sublist(rgba.length - 4),
        turn < 2 ? [0, 0, 255, 255] : [255, 0, 0, 255],
      );
      output.dispose();
      selection.rotate();
    }
  });

  testWidgets(
    'dialog resizes on desktop and narrow screens, preserves crop and can cancel',
    (tester) async {
      final bytes = (await tester.runAsync(samplePng))!;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Uint8List? result;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [OreThemeData.dark()]),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showResourceImageCropDialog(
                    context,
                    bytes: bytes,
                    label: '封面',
                  );
                  closed = true;
                },
                child: const Text('选图'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选图'));
      await waitForCrop(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('放大'));
      await tester.pumpAndSettle();
      expect(find.textContaining('128 × 80'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('image-crop-canvas')),
        const Offset(20, 10),
      );
      await tester.pumpAndSettle();
      for (final size in [
        const Size(390, 844),
        const Size(844, 390),
        const Size(1280, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.text('裁剪并上传').hitTestable(), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('image-crop-canvas')))
              .height,
          greaterThan(90),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('旋转'));
      await tester.pumpAndSettle();
      expect(find.textContaining('100 × 160'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    },
  );

  testWidgets('malformed images show a recoverable error and cannot upload', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResourceImageCropDialog(
          bytes: Uint8List.fromList([1, 2, 3]),
          label: '封面',
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.textContaining('无法读取这张图片'), findsOneWidget);
    expect(
      tester
          .widget<OreButton>(find.widgetWithText(OreButton, '裁剪并上传'))
          .onPressed,
      isNull,
    );
    expect(find.text('取消').hitTestable(), findsOneWidget);
  });
}
