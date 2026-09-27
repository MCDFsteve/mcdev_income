part of '../core.dart';

extension ResourceWorkflowApi on McDevApi {
  Future<List<Map<String, dynamic>>> searchDlcResources(String query) async {
    final result = await _getJson(
      Uri.https('mc-launcher.webapp.163.com', '/items/categories/pe/', {
        'start': '0',
        'span': '10',
        'item_name': query,
        'mc_status': '1',
      }),
    );
    return ResourceOptions.maps(result['data']?['item']);
  }

  Future<List<Map<String, dynamic>>> searchRequirements(
    String resourceCategory,
    String query,
  ) async {
    if (resourceCategory == 'pe') {
      final result = await _getJson(
        Uri.https('mc-launcher.webapp.163.com', '/items/categories/pe/', {
          'pri_type': '9',
          'item_name': query,
          'start': '0',
          'span': '20',
        }),
      );
      return ResourceOptions.maps(
        result['data']?['item'] ?? result['data']?['list'],
      );
    }
    final result = await _getJson(
      Uri.https(
        'mc-launcher.webapp.163.com',
        '/items/categories/comp/requirements',
        {'query_str': query, 'start': '0', 'span': '100'},
      ),
    );
    return ResourceOptions.maps(result['data']?['item']);
  }

  Future<Map<String, dynamic>> resourcePostAction({
    required String resourceCategory,
    required String itemId,
    required String action,
    required Map<String, dynamic> payload,
  }) => _postJson(
    Uri.https(
      'mc-launcher.webapp.163.com',
      '/items/categories/$resourceCategory/$itemId/$action',
    ),
    payload,
  );

  Future<ResourceOptions> fetchResourceOptions() async {
    final result = await _getJson(
      Uri.https('mc-launcher.webapp.163.com', '/items/mc_consts/'),
    );
    if (result['data'] is! Map) {
      throw McDevException('平台配置返回异常', Uri.parse('/items/mc_consts/'));
    }
    return ResourceOptions(Map<String, dynamic>.from(result['data']));
  }

  Future<Map<String, dynamic>> fetchPlatformSettings(String name) async {
    final result = await _getJson(
      Uri.https('mc-launcher.webapp.163.com', '/setting/common/', {
        'name': name,
      }),
    );
    return Map<String, dynamic>.from(result['data']?['setting'] ?? {});
  }

  Future<Map<String, dynamic>> submitResourceReview({
    required String resourceCategory,
    required String itemId,
    required String notes,
    bool confirmQueue = false,
    int? conflictNotify,
    List<int>? conflictTypes,
  }) => changeResourceStatus(
    resourceCategory: resourceCategory,
    itemId: itemId,
    action: 'apply_review',
    payload: {
      'apply_review_text': notes.trim(),
      'is_check_apply': confirmQueue,
      'conflict_notify': ?conflictNotify,
      if (conflictTypes != null && !conflictTypes.contains(0))
        'conflict_notify_type': conflictTypes,
    },
  );

  Future<UploadedResourceFile> uploadResourceFile({
    required String name,
    required int length,
    required Stream<List<int>> stream,
    required String fileType,
    bool secure = false,
    void Function(int, int)? onProgress,
  }) async {
    if (length <= 0) throw ArgumentError('不能上传空文件');
    final tokenUri = Uri.https(
      'mc-launcher.webapp.163.com',
      '/filepicker/file_token',
      {'file_type': fileType, 'secure': secure.toString()},
    );
    final tokenResult = await _getJson(tokenUri);
    final token = tokenResult['data']?['token']?.toString();
    if (token == null || token.isEmpty) {
      throw McDevException('未获取到上传凭证', tokenUri);
    }
    final uri = Uri.https(
      secure ? 'pfp.ps.netease.com' : 'fp.ps.netease.com',
      secure ? '/x19s/file/new/' : '/x19/file/new/',
    );
    var sent = 0;
    final bodyStream = stream.map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent, length);
      return chunk;
    });
    // Filepicker is a different origin: send only its scoped upload token.
    final request = http.MultipartRequest('POST', uri)
      // Without JSON negotiation, Filepicker can return an iframe HTML page
      // containing a successful, signed result inside a textarea.
      ..headers.addAll({
        'Accept': 'application/json',
        'Origin': 'https://mcdev.webapp.163.com',
        'Referer': 'https://mcdev.webapp.163.com/',
      })
      ..fields['Authorization'] = token
      ..files.add(
        http.MultipartFile('fpfile', bodyStream, length, filename: name),
      );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(minutes: 10)),
    ).timeout(const Duration(minutes: 10));
    final result = _decodeResourceUploadResponse(response, uri);
    final signature = response.headers['x-ntes-signature'];
    final url = result['url']?.toString();
    if (signature == null || signature.isEmpty || url == null || url.isEmpty) {
      throw McDevException('上传响应缺少地址或签名，文件尚未加入资源', uri);
    }
    // Match the website's signed JSON serialization exactly.
    final signedBody = jsonEncode(
      result,
    ).replaceAll('":', '": ').replaceAll(',', ', ');
    return UploadedResourceFile(
      url: url,
      name: name,
      fileType: fileType,
      body: signedBody,
      signature: signature,
    );
  }

  Map<String, dynamic> _decodeResourceUploadResponse(
    http.Response response,
    Uri uri,
  ) {
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final message = switch (status) {
        401 || 403 => '文件上传凭证失效或被拒绝，请重新上传以获取新凭证',
        413 => '文件服务器拒绝上传：文件超过大小限制',
        415 => '文件服务器不支持此文件格式',
        429 => '上传过于频繁，请稍后重试',
        _ => '文件上传失败：HTTP $status，请稍后重试',
      };
      throw McDevException(message, uri, outcomeUnknown: status >= 500);
    }

    Map<String, dynamic>? result;
    try {
      var body = utf8.decode(response.bodyBytes).trim();
      if (body.startsWith('<') &&
          (response.headers['x-ntes-signature']?.isNotEmpty ?? false)) {
        // Parse markup as inert data; never load this page or execute scripts.
        // An HTML parser also decodes entities in the textarea correctly.
        final textareas = html_parser.parse(body).querySelectorAll('textarea');
        if (textareas.length == 1) body = textareas.single.text.trim();
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) result = decoded;
    } on FormatException {
      // Report the upload failure without exposing raw HTML, tokens or cookies.
    }
    if (result == null) {
      throw McDevException(
        '文件服务器响应格式异常（HTTP $status），文件尚未加入作品，请重试',
        uri,
        outcomeUnknown: true,
      );
    }
    if (result['status'] != null && result['status'] != 'ok') {
      final message =
          result['message'] ??
          result['msg'] ??
          result['error'] ??
          result['status'];
      throw McDevException('文件服务器拒绝上传：$message', uri);
    }
    return result;
  }
}
