part of '../core.dart';

extension LeaderboardResourceApi on McDevApi {
  /// Public resource queries. Never use the authenticated platform helpers:
  /// these hosts do not need the developer cookie or any WeChat credentials.
  Future<LeaderboardResourceDetail> fetchLeaderboardResource(
    LeaderboardEntry entry,
  ) async {
    if (!entry.hasResourceDetails) throw ArgumentError('该条目没有有效的资源 ID');
    final uri = entry.isDesktop
        ? Uri.https('x19mclobt.nie.netease.com', '/item/query/search-by-iid')
        : Uri.https(
            'g79apigatewayobt.nie.netease.com',
            '/h5/pe-item-detail-v2',
          );
    final body = <String, dynamic>{
      if (!entry.isDesktop) 'channel_id': 5,
      'item_id': entry.id,
    };
    if (!entry.isDesktop) {
      // Public H5 sharing-page signature; this salt is not an account secret.
      body['sign'] = md5
          .convert(
            utf8.encode('channel_id=5&item_id=${entry.id}&mc#h5page#web'),
          )
          .toString();
    }

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw McDevException('资源详情暂时无法获取，请稍后重试', uri);
      }
      final result = jsonDecode(utf8.decode(response.bodyBytes));
      if (result is! Map<String, dynamic>) {
        throw McDevException('资源详情响应格式异常', uri);
      }
      if (result['code'] != 0) {
        throw McDevException(
          result['code'] == 16 ? '暂时找不到该资源，可能已下架' : '资源详情暂时无法获取，请稍后重试',
          uri,
        );
      }
      final entity = result['entity'];
      if (entity is! Map<String, dynamic> ||
          '${entity['item_id'] ?? entity['entity_id']}' != entry.id) {
        throw McDevException('资源详情响应格式异常', uri);
      }
      return LeaderboardResourceDetail.fromJson(
        entity,
        isDesktop: entry.isDesktop,
      );
    } on TimeoutException {
      throw McDevException('资源详情请求超时，请重试', uri);
    } on FormatException {
      throw McDevException('资源详情响应格式异常', uri);
    } on http.ClientException {
      throw McDevException('无法连接资源服务，请检查网络后重试', uri);
    }
  }

  /// Public mobile comments, with newest ordinary comments first.
  /// [length] is the cumulative number of ordinary comments, not a page size.
  /// Pinned and hot comments are returned separately by the service and merged
  /// by the model. No developer cookie or WeChat credentials are sent.
  Future<LeaderboardResourceComments> fetchLeaderboardResourceComments(
    LeaderboardEntry entry, {
    int length = 20,
  }) async {
    if (!entry.hasResourceDetails) throw ArgumentError('该条目没有有效的资源 ID');
    if (entry.isDesktop) {
      // A PC item passed to the PE endpoint misleadingly succeeds with no rows.
      throw UnsupportedError('当前公开接口暂不提供端游评论');
    }
    if (length <= 0) throw ArgumentError.value(length, 'length', '必须大于 0');

    final uri = Uri.https(
      'g79apigatewayobt.nie.netease.com',
      '/h5/pe-user-comment',
    );
    final body = <String, dynamic>{
      'item_id': entry.id,
      'length': length,
      'sort_type': 0,
      'order': 0,
    };
    final keys = body.keys.toList()..sort();
    body['sign'] = md5
        .convert(
          utf8.encode(
            '${keys.map((key) => '$key=${body[key]}&').join()}mc#h5page#web',
          ),
        )
        .toString();

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw McDevException('评论暂时无法获取，请稍后重试', uri);
      }
      final result = jsonDecode(utf8.decode(response.bodyBytes));
      if (result is! Map<String, dynamic>) {
        throw McDevException('评论响应格式异常', uri);
      }
      if (result['code'] != 0) {
        throw McDevException(
          result['code'] == 16 ? '暂时找不到该资源，可能已下架' : '评论暂时无法获取，请稍后重试',
          uri,
        );
      }
      final entity = result['entity'];
      if (entity is! Map<String, dynamic> ||
          '${entity['entity_id']}' != entry.id ||
          entity['comment_list'] is! List ||
          (entity['top_comment_list'] != null &&
              entity['top_comment_list'] is! List) ||
          (entity['hot_comment_list'] != null &&
              entity['hot_comment_list'] is! List)) {
        throw McDevException('评论响应格式异常', uri);
      }
      return LeaderboardResourceComments.fromJson(
        entity,
        requestedLength: length,
      );
    } on TimeoutException {
      throw McDevException('评论请求超时，请重试', uri);
    } on FormatException {
      throw McDevException('评论响应格式异常', uri);
    } on http.ClientException {
      throw McDevException('无法连接评论服务，请检查网络后重试', uri);
    }
  }
}
