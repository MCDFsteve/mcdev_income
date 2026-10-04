part of '../core.dart';

/// Only the public fields used by the resource dialog are retained.
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

/// A read-only public comment. Account identifiers and session data are omitted.
class LeaderboardResourceComment {
  LeaderboardResourceComment.fromJson(
    Map<String, dynamic> json, {
    this.isPinned = false,
    this.isHot = false,
  }) : id = LeaderboardResourceDetail._text(json['comment_id']),
       author = LeaderboardResourceDetail._text(json['nickname']),
       text = LeaderboardResourceDetail._text(json['user_comment']),
       rating = _rating(json['stars']),
       publishedAt = _publishedAt(json['publish_time']),
       likes = LeaderboardResourceDetail._count(json['good_num']),
       replyCount = LeaderboardResourceDetail._count(json['commented_num']),
       avatarUrl = LeaderboardResourceDetail._imageUrl(json['head_image']),
       isDeveloper = json['is_developer'] == 1 || json['is_developer'] == true;

  final String id, author, text;
  final double? rating;
  final DateTime? publishedAt;
  final int? likes, replyCount;
  final String? avatarUrl;
  final bool isDeveloper, isPinned, isHot;

  static double? _rating(Object? value) {
    final number = LeaderboardResourceDetail._number(value)?.toDouble();
    // Zero means the author did not rate this resource.
    return number != null && number > 0 && number <= 5 ? number : null;
  }

  static DateTime? _publishedAt(Object? value) {
    final seconds = LeaderboardResourceDetail._number(value);
    if (seconds == null || seconds <= 0 || seconds > 8640000000000) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).toInt(),
      isUtc: true,
    );
  }
}

/// The H5 endpoint returns a growing prefix, not an offset-based page.
/// Replace the previous comments with this list when requesting more.
class LeaderboardResourceComments {
  LeaderboardResourceComments.fromJson(
    Map<String, dynamic> json, {
    required this.requestedLength,
  }) : total = LeaderboardResourceDetail._count(json['master_comment_count']),
       _regularCount = (json['comment_list'] as List? ?? const []).length,
       comments = _comments(json);

  /// Top-level comments, including pinned comments and excluding replies.
  /// This differs from the detail endpoint's comment_count, which includes replies.
  final int? total;
  final int requestedLength;
  final int _regularCount;
  final List<LeaderboardResourceComment> comments;

  bool get hasMore =>
      _regularCount >= requestedLength &&
      (total == null || comments.length < total!);

  static List<LeaderboardResourceComment> _comments(Map<String, dynamic> json) {
    final comments = <String, LeaderboardResourceComment>{};
    for (final key in [
      'top_comment_list',
      'hot_comment_list',
      'comment_list',
    ]) {
      final values = json[key];
      if (values is! List) continue;
      for (final value in values) {
        if (value is! Map<String, dynamic>) continue;
        final comment = LeaderboardResourceComment.fromJson(
          value,
          isPinned: key == 'top_comment_list',
          isHot: key == 'hot_comment_list',
        );
        if (RegExp(r'^[1-9]\d*$').hasMatch(comment.id)) {
          // Pinned/hot rows may also appear in the ordinary list.
          comments.putIfAbsent(comment.id, () => comment);
        }
      }
    }
    return List.unmodifiable(comments.values);
  }
}
