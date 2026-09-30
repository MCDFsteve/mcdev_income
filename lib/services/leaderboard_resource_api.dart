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
}
