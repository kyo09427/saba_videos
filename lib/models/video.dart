import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'user_profile.dart';

/// 動画データモデル
/// 
/// YouTube動画の情報を保持するモデルクラス。
/// Supabaseのvideosテーブルとマッピングされます。
@immutable
class Video {
  /// 動画の一意識別子（UUID）
  final String id;

  /// 作成日時（JSTに変換済み）
  final DateTime createdAt;

  /// 動画のタイトル
  final String title;

  /// YouTube動画のURL
  final String url;

  /// 投稿者のユーザーID
  final String userId;

  /// メインカテゴリ（雑談/ゲーム/音楽/ネタ）
  final String mainCategory;

  /// サブカテゴリタグのリスト
  final List<String> tags;

  /// 投稿者のプロフィール情報（JOIN時のみ取得）
  final UserProfile? userProfile;

  /// 再生時間（主観入力）例: "12:45" や "1:23:45"
  final String? duration;

  /// YouTube oEmbed APIで取得したタイトル
  final String? youtubeTitle;

  const Video({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.url,
    required this.userId,
    required this.mainCategory,
    this.tags = const [],
    this.userProfile,
    this.duration,
    this.youtubeTitle,
  });

  /// Supabaseから取得したJSONデータからVideoオブジェクトを生成
  /// 
  /// エラー時もフォールバック値を使用して必ず有効なオブジェクトを返します。
  /// 
  /// [json] Supabaseから取得したJSONデータ
  /// 
  /// Returns: Videoオブジェクト
  factory Video.fromJson(Map<String, dynamic> json) {
    try {
      // タグの解析
      List<String> tagsList = [];
      if (json['tags'] != null) {
        if (json['tags'] is List) {
          tagsList = (json['tags'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }

      return Video(
        id: _extractString(json, 'id', ''),
        createdAt: _extractDateTime(json, 'created_at'),
        title: _extractString(json, 'title', '無題の動画'),
        url: _extractString(json, 'url', ''),
        userId: _extractString(json, 'user_id', ''),
        mainCategory: _extractString(json, 'main_category', '雑談'),
        tags: tagsList,
        duration: json['duration'] as String?,
        youtubeTitle: json['youtube_title'] as String?,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing Video from JSON: $e');
        debugPrint('   JSON data: $json');
      }

      // エラー時のフォールバック
      return Video(
        id: '',
        createdAt: DateTime.now(),
        title: '読み込みエラー',
        url: '',
        userId: '',
        mainCategory: '雑談',
        tags: const [],
      );
    }
  }

  /// プロフィール情報を含むJSONからVideoオブジェクトを生成
  /// 
  /// videos.select('*, profiles(*)')の結果を解析します。
  factory Video.fromJsonWithProfile(Map<String, dynamic> json) {
    try {
      UserProfile? profile;
      if (json['profiles'] != null) {
        profile = UserProfile.fromJson(json['profiles'] as Map<String, dynamic>);
      }

      // タグの解析
      List<String> tagsList = [];
      if (json['tags'] != null) {
        if (json['tags'] is List) {
          tagsList = (json['tags'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }

      return Video(
        id: _extractString(json, 'id', ''),
        createdAt: _extractDateTime(json, 'created_at'),
        title: _extractString(json, 'title', '無題の動画'),
        url: _extractString(json, 'url', ''),
        userId: _extractString(json, 'user_id', ''),
        mainCategory: _extractString(json, 'main_category', '雑談'),
        tags: tagsList,
        userProfile: profile,
        duration: json['duration'] as String?,
        youtubeTitle: json['youtube_title'] as String?,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing Video with profile from JSON: $e');
        debugPrint('   JSON data: $json');
      }

      return Video(
        id: '',
        createdAt: DateTime.now(),
        title: '読み込みエラー',
        url: '',
        userId: '',
        mainCategory: '雑談',
        tags: const [],
      );
    }
  }

  /// JSONから文字列値を安全に抽出
  static String _extractString(
    Map<String, dynamic> json,
    String key,
    String defaultValue,
  ) {
    try {
      final value = json[key];
      if (value == null) {
        if (kDebugMode && defaultValue.isEmpty) {
          debugPrint('⚠️ Missing required field: $key');
        }
        return defaultValue;
      }

      if (value is String) {
        return value.trim();
      }

      if (kDebugMode) {
        debugPrint('⚠️ Unexpected type for $key: ${value.runtimeType}');
      }
      return value.toString().trim();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error extracting $key: $e');
      }
      return defaultValue;
    }
  }

  /// JSONからDateTimeを安全に抽出
  static DateTime _extractDateTime(
    Map<String, dynamic> json,
    String key,
  ) {
    try {
      final value = json[key];
      if (value == null) {
        if (kDebugMode) {
          debugPrint('⚠️ Missing datetime field: $key, using current time');
        }
        return DateTime.now();
      }

      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ Failed to parse datetime string: $value');
          }
          return DateTime.now();
        }
      }

      if (value is DateTime) {
        return value;
      }

      if (kDebugMode) {
        debugPrint('⚠️ Unexpected type for datetime: ${value.runtimeType}');
      }
      return DateTime.now();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error extracting datetime from $key: $e');
      }
      return DateTime.now();
    }
  }

  /// SupabaseへinsertするためのJSONデータに変換
  /// 
  /// idとcreated_atは自動生成されるため含めません。
  /// tagsは別途video_tagsテーブルに保存されます。
  /// 
  /// Returns: insert用のマップ
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'user_id': userId,
      'main_category': mainCategory,
      if (duration != null && duration!.isNotEmpty) 'duration': duration,
      if (youtubeTitle != null && youtubeTitle!.isNotEmpty) 'youtube_title': youtubeTitle,
    };
  }

  /// YouTube動画IDを抽出（URLから）
  /// 
  /// Returns: 11文字のビデオID、抽出できない場合null
  String? get videoId {
    if (url.isEmpty) {
      return null;
    }

    try {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        return null;
      }

      // youtu.be形式: https://youtu.be/VIDEO_ID
      if (uri.host == 'youtu.be' || uri.host == 'www.youtu.be') {
        if (uri.pathSegments.isEmpty) {
          return null;
        }
        final id = uri.pathSegments[0].split('?')[0];
        return _isValidVideoId(id) ? id : null;
      }

      // youtube.com形式: https://www.youtube.com/watch?v=VIDEO_ID
      // m.youtube.com形式にも対応
      if (uri.host.contains('youtube.com')) {
        final id = uri.queryParameters['v'];
        if (id != null && _isValidVideoId(id)) {
          return id;
        }

        // /embed/VIDEO_ID 形式
        if (uri.pathSegments.contains('embed') &&
            uri.pathSegments.length > 1) {
          final index = uri.pathSegments.indexOf('embed');
          if (index + 1 < uri.pathSegments.length) {
            final id = uri.pathSegments[index + 1].split('?')[0];
            return _isValidVideoId(id) ? id : null;
          }
        }

        // /v/VIDEO_ID 形式
        if (uri.pathSegments.contains('v') && uri.pathSegments.length > 1) {
          final index = uri.pathSegments.indexOf('v');
          if (index + 1 < uri.pathSegments.length) {
            final id = uri.pathSegments[index + 1].split('?')[0];
            return _isValidVideoId(id) ? id : null;
          }
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error extracting video ID: $e');
      }
      return null;
    }
  }

  /// ビデオIDが有効な形式かチェック
  static bool _isValidVideoId(String? id) {
    if (id == null || id.isEmpty) {
      return false;
    }
    // YouTubeのビデオIDは11文字の英数字とハイフン、アンダースコア
    return id.length == 11 && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id);
  }

  /// YouTubeサムネイルURLを取得
  /// 
  /// Returns: サムネイルURL、ビデオIDが無効な場合null
  String? get thumbnailUrl {
    final id = videoId;
    if (id == null || id.isEmpty) {
      return null;
    }
    // 高画質サムネイル (480x360)
    return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }

  /// 最高画質のサムネイルURLを取得
  /// 
  /// Returns: サムネイルURL、ビデオIDが無効な場合null
  String? get maxResThumbnailUrl {
    final id = videoId;
    if (id == null || id.isEmpty) {
      return null;
    }
    // 最高画質サムネイル (1280x720)
    return 'https://img.youtube.com/vi/$id/maxresdefault.jpg';
  }

  /// 投稿日時を日本語形式で表示（JST）
  /// 
  /// フォーマット: 2026年02月07日 15:30
  String get formattedDate {
    try {
      final jst = createdAt.toLocal();
      return DateFormat('yyyy年MM月dd日 HH:mm', 'ja_JP').format(jst);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error formatting date: $e');
      }
      return '日時不明';
    }
  }

  /// 短い形式の日付表示
  /// 
  /// フォーマット: 02/07 15:30
  String get shortFormattedDate {
    try {
      final jst = createdAt.toLocal();
      return DateFormat('MM/dd HH:mm', 'ja_JP').format(jst);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error formatting short date: $e');
      }
      return '';
    }
  }

  /// 相対時間を表示するヘルパー (例: 2時間前)
  /// 
  /// Returns: 相対時間の文字列
  String get relativeTime {
    try {
      final now = DateTime.now();
      final difference = now.difference(createdAt);

      if (difference.inDays > 365) {
        final years = (difference.inDays / 365).floor();
        return '$years年前';
      } else if (difference.inDays > 30) {
        final months = (difference.inDays / 30).floor();
        return '$months か月前';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}日前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}時間前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分前';
      } else {
        return 'たった今';
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calculating relative time: $e');
      }
      return '';
    }
  }

  /// このVideoオブジェクトが有効かチェック
  /// 
  /// Returns: 必須フィールドがすべて設定されている場合true
  bool get isValid {
    return id.isNotEmpty &&
        title.isNotEmpty &&
        url.isNotEmpty &&
        userId.isNotEmpty &&
        videoId != null;
  }

  /// Videoオブジェクトのコピーを作成（一部のフィールドを変更可能）
  /// 
  /// 不変オブジェクトを安全に更新するために使用します。
  Video copyWith({
    String? id,
    DateTime? createdAt,
    String? title,
    String? url,
    String? userId,
    String? mainCategory,
    List<String>? tags,
    UserProfile? userProfile,
    String? duration,
    String? youtubeTitle,
  }) {
    return Video(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      url: url ?? this.url,
      userId: userId ?? this.userId,
      mainCategory: mainCategory ?? this.mainCategory,
      tags: tags ?? this.tags,
      userProfile: userProfile ?? this.userProfile,
      duration: duration ?? this.duration,
      youtubeTitle: youtubeTitle ?? this.youtubeTitle,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Video &&
        other.id == id &&
        other.createdAt == createdAt &&
        other.title == title &&
        other.url == url &&
        other.userId == userId &&
        other.userProfile == userProfile;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      createdAt,
      title,
      url,
      userId,
      userProfile,
    );
  }

  @override
  String toString() {
    return 'Video(id: $id, title: $title, url: $url, userId: $userId, createdAt: $createdAt)';
  }
}