part of '../core.dart';

/// Only the public fields used by the leaderboard dialog are retained.
class LeaderboardResourceDetail {
  LeaderboardResourceDetail.fromJson(
    Map<String, dynamic> json, {
    required this.isDesktop,
  }) : name = _text(json[isDesktop ? 'name' : 'res_name']),
       author = _text(json['developer_name']),
       version = _text(json[isDesktop ? 'item_version' : 'mod_version']),
       description = _text(json[isDesktop ? 'brief_summary' : 'info']),
       componentCode = _text(json['vanity_number']).isNotEmpty
           ? _text(json['vanity_number'])
           : _text(json['normal_number']),
       downloads = _count(json['download_num']),
       likes = _count(json['like_num']),
       rating = _number(json['stars'])?.toDouble(),
       ratingCount = _count(json['remark_num']),
       commentCount = _count(json['comment_count']),
       diamonds = _count(json['diamond']),
       points = _count(json['points']),
       iconUrl = _imageUrl(json['title_image_url']),
       images = List.unmodifiable({
         if (json['pic_url_list'] is List)
           for (final value in json['pic_url_list'] as List)
             if (_imageUrl(value) case final String url)
               if (url != _imageUrl(json['title_image_url'])) url,
       });

  final bool isDesktop;
  final String name, author, version, description, componentCode;
  final int? downloads, likes, ratingCount, commentCount, diamonds, points;
  final double? rating;
  final String? iconUrl;
  final List<String> images;

  String? get priceLabel {
    if ((diamonds ?? 0) > 0) return '$diamonds 钻石';
    if ((points ?? 0) > 0) return '$points 绿宝石';
    // Missing prices must not turn into an invented "free" label.
    return diamonds == 0 && points == 0 ? '免费' : null;
  }

  static String _text(Object? value) =>
      value is String || value is num ? '$value'.trim() : '';

  static num? _number(Object? value) {
    final number = num.tryParse(_text(value));
    return number != null && number.isFinite && number >= 0 ? number : null;
  }

  static int? _count(Object? value) => _number(value)?.toInt();

  static String? _imageUrl(Object? value) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    return uri != null &&
            ['https', 'http'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? text
        : null;
  }
}
