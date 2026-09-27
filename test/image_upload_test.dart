import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mcdev_income/main.dart';
import 'package:mcdev_income/widgets/resource_image_crop_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_crop_test.dart' show samplePng, decodePng, waitForCrop;
import 'resource_workflow_test.dart' as fixtures;
import 'widget_test.dart' show host;

class _Picker extends FilePicker {
  _Picker(this.bytes);
  final Uint8List bytes;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(name: 'test.png', size: bytes.length, bytes: bytes),
  ]);
}

class _UploadApi {
  _UploadApi(this.resource);
  final Map<String, dynamic> resource;
  final uploads = <({String name, String type, int length, Uint8List bytes})>[];
  final tokenTypes = <String>[];
  late final api = McDevApi(
    cookie: '',
    category: 'pe',
    client: MockClient((request) async {
      if (request.url.path == '/items/mc_consts/') {
        return fixtures.ok(fixtures.testOptions);
      }
      if (request.url.path.startsWith('/users/') ||
          request.url.path.startsWith('/setting/')) {
        return fixtures.ok({});
      }
      if (request.url.path == '/filepicker/file_token') {
        tokenTypes.add(request.url.queryParameters['file_type']!);
        return fixtures.ok({'token': 'test-upload-token'});
      }
      if (request.url.host == 'fp.ps.netease.com') {
        final multipart = latin1.decode(request.bodyBytes);
        final name = RegExp(
          'filename="([^"]+)"',
        ).firstMatch(multipart)!.group(1)!;
        final start =
            multipart.indexOf('\r\n\r\n', multipart.indexOf('filename="')) + 4;
        final end = multipart.lastIndexOf('\r\n--');
        final bytes = request.bodyBytes.sublist(start, end);
        uploads.add((
          name: name,
          type: tokenTypes.last,
          length: bytes.length,
          bytes: bytes,
        ));
        return http.Response(
          '<!DOCTYPE HTML><html><head></head><body>'
          '<script>document.domain="netease.com";</script>'
          '<textarea>{"url":"cropped-image"}</textarea></body></html>',
          200,
          headers: {
            'content-type': 'text/html; charset=utf-8',
            'x-ntes-signature': 'test-signature',
          },
        );
      }
      return fixtures.ok(resource);
    }),
  );
}

void main() {
  testWidgets(
    'wrong size opens crop; cancel preserves image; confirmation uploads exact output',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final bytes = (await tester.runAsync(samplePng))!;
      final oldPicker = FilePicker.platform;
      FilePicker.platform = _Picker(bytes);
      addTearDown(() => FilePicker.platform = oldPicker);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _UploadApi(fixtures.testResource());
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            item: ResourceItem.fromJson('pe', fixtures.testResource()),
            apiFactory: () => api.api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cover = find.byKey(const ValueKey('channel-tile-channel-3'));
      await tester.tap(find.descendant(of: cover, matching: find.text('替换图片')));
      await waitForCrop(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('992 × 558'), findsWidgets);
      expect(api.uploads, isEmpty);
      expect(api.tokenTypes, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存本机草稿'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      var saved = jsonDecode(prefs.getString('resource_draft_v1:test:pe:123')!);
      expect(saved['channel'][0]['channel_url'], 'saved-image');
      expect(api.uploads, isEmpty);

      await tester.tap(find.descendant(of: cover, matching: find.text('替换图片')));
      await waitForCrop(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('裁剪并上传'));
      for (var i = 0; i < 100 && api.uploads.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(api.uploads, hasLength(1));
      final upload = api.uploads.single;
      expect(upload.name, 'test-cropped.png');
      expect(upload.type, 'image');
      expect(upload.length, upload.bytes.length);
      await tester.runAsync(() async {
        final image = await decodePng(upload.bytes);
        expect(image.width, 992);
        expect(image.height, 558);
        image.dispose();
      });
      // Let the earlier draft-saved snackbar clear the bottom actions.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存本机草稿'));
      await tester.pumpAndSettle();
      saved = jsonDecode(prefs.getString('resource_draft_v1:test:pe:123')!);
      final channels = saved['channel'] as List;
      expect(
        channels.firstWhere((e) => e['channel_id'] == 3)['channel_url']['sign'],
        'test-signature',
      );
      expect(
        channels.firstWhere((e) => e['channel_id'] == 5)['channel_url'],
        'saved-image',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'skin PNG package bypasses media crop and retains original bytes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final bytes = (await tester.runAsync(samplePng))!;
      final oldPicker = FilePicker.platform;
      FilePicker.platform = _Picker(bytes);
      addTearDown(() => FilePicker.platform = oldPicker);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resource = fixtures.testResource()
        ..['pri_type'] = 4
        ..['sub_type'] = 13;
      final api = _UploadApi(resource);
      await tester.pumpWidget(
        host(
          ResourceEditorPage(
            category: const ResourceCategory(
              value: 'pe',
              label: 'PE',
              uploadLabel: '新建',
            ),
            item: ResourceItem.fromJson('pe', resource),
            apiFactory: () => api.api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('替换文件'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceImageCropDialog), findsNothing);
      expect(api.uploads, hasLength(1));
      expect(api.uploads.single.type, 'png');
      expect(api.uploads.single.name, 'test.png');
      expect(api.uploads.single.bytes, bytes);
      expect(tester.takeException(), isNull);
    },
  );
}
