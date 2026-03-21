import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// YouTube oEmbed APIのレスポンスを格納するデータクラス
class YouTubeVideoInfo {
  /// 動画タイトル
  final String title;

  /// サムネイルURL
  final String? thumbnailUrl;

  /// チャンネル（投稿者）名
  final String? authorName;

  const YouTubeVideoInfo({
    required this.title,
    this.thumbnailUrl,
    this.authorName,
  });
}

/// サムネイル画質の種類
enum ThumbnailQuality {
  /// デフォルト (120x90)
  defaultQuality,
  
  /// 中品質 (320x180)
  medium,
  
  /// 高品質 (480x360) - 推奨
  high,
  
  /// 標準品質 (640x480)
  standard,
  
  /// 最高品質 (1280x720)
  maxRes,
}

/// YouTube関連の機能を提供するサービスクラス
/// 
/// このクラスは、YouTube URLの解析、サムネイル取得、
/// 動画の起動などの機能を提供します。
class YouTubeService {
  // プライベートコンストラクタ（ユーティリティクラス）
  YouTubeService._();

  /// サポートされているYouTubeドメイン
  static const List<String> _supportedDomains = [
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
    'www.youtu.be',
  ];

  /// YouTube URLからビデオIDを抽出
  /// 
  /// サポートされている形式:
  /// - https://www.youtube.com/watch?v=VIDEO_ID
  /// - https://youtu.be/VIDEO_ID
  /// - https://m.youtube.com/watch?v=VIDEO_ID
  /// - https://www.youtube.com/embed/VIDEO_ID
  /// - https://www.youtube.com/v/VIDEO_ID
  /// 
  /// [url] YouTube動画のURL
  /// 
  /// Returns: ビデオID（11文字）、抽出できない場合null
  static String? extractVideoId(String url) {
    if (url.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ Empty URL provided to extractVideoId');
      }
      return null;
    }

    try {
      final uri = Uri.tryParse(url.trim());
      if (uri == null) {
        if (kDebugMode) {
          debugPrint('⚠️ Invalid URL format: $url');
        }
        return null;
      }

      // youtu.be形式: https://youtu.be/VIDEO_ID または https://youtu.be/VIDEO_ID?t=123
      if (uri.host == 'youtu.be' || uri.host == 'www.youtu.be') {
        if (uri.pathSegments.isEmpty) {
          return null;
        }
        
        // パスの最初のセグメントを取得し、クエリパラメータを除去
        final videoId = uri.pathSegments[0].split('?')[0].split('&')[0];
        return _validateVideoId(videoId);
      }

      // youtube.com形式
      if (uri.host.contains('youtube.com')) {
        // クエリパラメータからvを取得: ?v=VIDEO_ID
        final videoId = uri.queryParameters['v'];
        if (videoId != null && videoId.isNotEmpty) {
          return _validateVideoId(videoId);
        }

        // /embed/VIDEO_ID 形式
        if (uri.pathSegments.contains('embed')) {
          final index = uri.pathSegments.indexOf('embed');
          if (index + 1 < uri.pathSegments.length) {
            final id = uri.pathSegments[index + 1].split('?')[0].split('&')[0];
            return _validateVideoId(id);
          }
        }

        // /v/VIDEO_ID 形式
        if (uri.pathSegments.contains('v')) {
          final index = uri.pathSegments.indexOf('v');
          if (index + 1 < uri.pathSegments.length) {
            final id = uri.pathSegments[index + 1].split('?')[0].split('&')[0];
            return _validateVideoId(id);
          }
        }

        // /watch 形式（v パラメータなし）
        if (uri.pathSegments.contains('watch')) {
          if (kDebugMode) {
            debugPrint('⚠️ /watch path found but no v parameter');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('⚠️ Could not extract video ID from: $url');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error extracting video ID: $e');
      }
      return null;
    }
  }

  /// ビデオIDの検証
  /// 
  /// YouTubeのビデオIDは正確に11文字の英数字と記号で構成されます
  static String? _validateVideoId(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }

    final trimmedId = id.trim();
    
    // YouTubeのビデオIDは11文字
    if (trimmedId.length != 11) {
      if (kDebugMode) {
        debugPrint('⚠️ Invalid video ID length: ${trimmedId.length} (expected 11)');
      }
      return null;
    }

    // 英数字、ハイフン、アンダースコアのみ許可
    final validPattern = RegExp(r'^[a-zA-Z0-9_-]{11}$');
    if (!validPattern.hasMatch(trimmedId)) {
      if (kDebugMode) {
        debugPrint('⚠️ Invalid video ID format: $trimmedId');
      }
      return null;
    }

    return trimmedId;
  }

  /// YouTube URLが有効かをチェック
  /// 
  /// [url] チェックするURL
  /// 
  /// Returns: 有効なYouTube URLの場合true
  static bool isValidYouTubeUrl(String url) {
    if (url.trim().isEmpty) {
      return false;
    }

    try {
      final uri = Uri.tryParse(url.trim());
      if (uri == null) {
        return false;
      }

      // サポートされているドメインかチェック
      final isSupported = _supportedDomains.any((domain) => uri.host == domain);
      if (!isSupported) {
        if (kDebugMode) {
          debugPrint('⚠️ Unsupported domain: ${uri.host}');
        }
        return false;
      }

      // ビデオIDが抽出できるかチェック
      final videoId = extractVideoId(url);
      return videoId != null && videoId.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error validating YouTube URL: $e');
      }
      return false;
    }
  }

  /// サムネイルURLを生成
  /// 
  /// [videoId] YouTubeビデオID（11文字）
  /// [quality] サムネイルの品質（デフォルト: high）
  /// 
  /// Returns: サムネイルURL、無効なビデオIDの場合null
  static String? getThumbnailUrl(
    String videoId, {
    ThumbnailQuality quality = ThumbnailQuality.high,
  }) {
    final validId = _validateVideoId(videoId);
    if (validId == null) {
      return null;
    }

    final qualityMap = {
      ThumbnailQuality.defaultQuality: 'default',
      ThumbnailQuality.medium: 'mqdefault',
      ThumbnailQuality.high: 'hqdefault',
      ThumbnailQuality.standard: 'sddefault',
      ThumbnailQuality.maxRes: 'maxresdefault',
    };

    final qualityStr = qualityMap[quality]!;
    return 'https://img.youtube.com/vi/$validId/$qualityStr.jpg';
  }

  /// 複数の画質のサムネイルURLを取得
  /// 
  /// [videoId] YouTubeビデオID
  /// 
  /// Returns: 画質名とURLのマップ、無効なビデオIDの場合空のマップ
  static Map<String, String> getThumbnailUrls(String videoId) {
    final validId = _validateVideoId(videoId);
    if (validId == null) {
      return {};
    }

    return {
      'default': 'https://img.youtube.com/vi/$validId/default.jpg',
      'medium': 'https://img.youtube.com/vi/$validId/mqdefault.jpg',
      'high': 'https://img.youtube.com/vi/$validId/hqdefault.jpg',
      'standard': 'https://img.youtube.com/vi/$validId/sddefault.jpg',
      'maxres': 'https://img.youtube.com/vi/$validId/maxresdefault.jpg',
    };
  }

  /// YouTube動画を外部アプリ/ブラウザで開く
  /// 
  /// Androidでは可能な限りYouTubeアプリで開き、
  /// インストールされていない場合はブラウザで開きます。
  /// 
  /// [url] YouTube動画のURL
  /// 
  /// Returns: 動画を開けた場合true、失敗した場合false
  static Future<bool> launchVideo(String url) async {
    if (url.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ Empty URL provided to launchVideo');
      }
      return false;
    }

    try {
      if (kDebugMode) {
        debugPrint('🎬 Attempting to launch video: $url');
      }

      final uri = Uri.parse(url.trim());

      // URLが開けるかチェック
      if (!await canLaunchUrl(uri)) {
        if (kDebugMode) {
          debugPrint('⚠️ Cannot launch URL: $url');
        }
        return false;
      }

      // 外部アプリケーションで開く
      final result = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (kDebugMode) {
        if (result) {
          debugPrint('✅ Successfully launched video');
        } else {
          debugPrint('❌ Failed to launch video');
        }
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error launching video: $e');
      }
      return false;
    }
  }

  /// YouTube動画のURLを正規化（標準形式に変換）
  /// 
  /// すべてのYouTube URLを https://www.youtube.com/watch?v=VIDEO_ID
  /// の形式に統一します。
  /// 
  /// [url] 元のYouTube URL
  /// 
  /// Returns: 正規化されたURL、無効なURLの場合null
  static String? normalizeUrl(String url) {
    final videoId = extractVideoId(url);
    if (videoId == null || videoId.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ Cannot normalize invalid URL: $url');
      }
      return null;
    }

    return 'https://www.youtube.com/watch?v=$videoId';
  }

  /// YouTubeチャンネルURLからチャンネルIDまたはユーザー名を抽出
  /// 
  /// 注意: この機能は将来の拡張用です
  /// 
  /// [url] YouTubeチャンネルのURL
  /// 
  /// Returns: チャンネルIDまたはユーザー名、抽出できない場合null
  static String? extractChannelId(String url) {
    if (url.trim().isEmpty) {
      return null;
    }

    try {
      final uri = Uri.tryParse(url.trim());
      if (uri == null || !uri.host.contains('youtube.com')) {
        return null;
      }

      // /channel/CHANNEL_ID 形式
      if (uri.pathSegments.contains('channel') &&
          uri.pathSegments.length > 1) {
        final index = uri.pathSegments.indexOf('channel');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }

      // /@USERNAME 形式
      if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments[0].startsWith('@')) {
        return uri.pathSegments[0];
      }

      // /c/CUSTOM_NAME 形式
      if (uri.pathSegments.contains('c') && uri.pathSegments.length > 1) {
        final index = uri.pathSegments.indexOf('c');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }

      // /user/USERNAME 形式
      if (uri.pathSegments.contains('user') && uri.pathSegments.length > 1) {
        final index = uri.pathSegments.indexOf('user');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error extracting channel ID: $e');
      }
      return null;
    }
  }

  /// YouTube Shortsかどうかを判定
  /// 
  /// [url] チェックするURL
  /// 
  /// Returns: Shorts URLの場合true
  static bool isShortsUrl(String url) {
    if (url.trim().isEmpty) {
      return false;
    }

    try {
      final uri = Uri.tryParse(url.trim());
      if (uri == null || !uri.host.contains('youtube.com')) {
        return false;
      }

      return uri.pathSegments.contains('shorts');
    } catch (e) {
      return false;
    }
  }

  /// YouTube oEmbed APIを使って動画情報（タイトル・サムネイル・チャンネル名）を取得
  ///
  /// APIキー不要。ただし動画が非公開の場合や存在しない場合はnullを返します。
  ///
  /// [url] YouTube動画のURL
  ///
  /// Returns: YouTubeVideoInfo、取得失敗の場合null
  static Future<YouTubeVideoInfo?> fetchVideoInfo(String url) async {
    if (url.trim().isEmpty) {
      return null;
    }

    final videoId = extractVideoId(url);
    if (videoId == null) {
      return null;
    }

    try {
      final normalizedUrl = 'https://www.youtube.com/watch?v=$videoId';
      final apiUrl = Uri.parse(
        'https://www.youtube.com/oembed?format=json&url=${Uri.encodeComponent(normalizedUrl)}',
      );

      final response = await http.get(apiUrl).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('⚠️ oEmbed API returned ${response.statusCode} for $url');
        }
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      return YouTubeVideoInfo(
        title: (json['title'] as String? ?? '').trim(),
        thumbnailUrl: json['thumbnail_url'] as String?,
        authorName: json['author_name'] as String?,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error fetching YouTube video info: $e');
      }
      return null;
    }
  }

  /// YouTubeページのHTMLから動画の再生時間を取得
  ///
  /// YouTubeページ内の `lengthSeconds` フィールドを正規表現で抽出します。
  /// APIキー不要ですが、Flutter Web（Chrome）ではCORSにより取得できない場合があります。
  /// その場合はnullを返し、ユーザーが手動入力できます。
  ///
  /// [url] YouTube動画のURL
  ///
  /// Returns: "M:SS" または "H:MM:SS" 形式の文字列、取得失敗の場合null
  static Future<String?> fetchVideoDuration(String url) async {
    final videoId = extractVideoId(url);
    if (videoId == null) return null;

    try {
      final pageUrl = Uri.parse('https://www.youtube.com/watch?v=$videoId');
      final response = await http
          .get(pageUrl, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept-Language': 'ja,en;q=0.9',
          })
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = response.body;

      // "lengthSeconds":"N..." または "lengthSeconds":N のパターンを探す
      final patterns = [
        RegExp(r'"lengthSeconds"\s*:\s*"(\d+)"'),
        RegExp(r'"lengthSeconds"\s*:\s*(\d+)'),
        RegExp(r'approxDurationMs\\":\\"(\d+)\\"'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(body);
        if (match != null) {
          final rawValue = match.group(1);
          if (rawValue == null) continue;

          int seconds;
          if (pattern.pattern.contains('approxDurationMs')) {
            seconds = (int.parse(rawValue) / 1000).round();
          } else {
            seconds = int.parse(rawValue);
          }

          if (seconds > 0) {
            return _secondsToDurationString(seconds);
          }
        }
      }

      if (kDebugMode) {
        debugPrint('⚠️ Could not extract duration from YouTube page for $videoId');
      }
      return null;
    } catch (e) {
      // Flutter Webでは CORS エラーが発生するため静かにnullを返す
      if (kDebugMode) {
        debugPrint('⚠️ fetchVideoDuration failed (may be CORS on web): $e');
      }
      return null;
    }
  }

  /// 秒数を "M:SS" または "H:MM:SS" 形式に変換
  static String _secondsToDurationString(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    } else {
      return '$minutes:$ss';
    }
  }
}