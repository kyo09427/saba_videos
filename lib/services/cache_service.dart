/// シンプルなメモリキャッシュサービス
///
/// TTL（生存時間）付きでデータをメモリキャッシュに保存し、
/// 各画面の初期表示を高速化します。
library;

class _CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  _CacheEntry({required this.data, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// キャッシュキー定数
class CacheKeys {
  CacheKeys._();

  static const String homeVideos = 'home_videos';
  static const String timelineVideos = 'timeline_videos';
  static const String subscribedChannelIds = 'subscribed_channel_ids';
  static const String subscriptionVideos = 'subscription_videos';
  static const String myVideos = 'my_videos';
  static const String myPageProfile = 'my_page_profile';
  static const String myPageVideoCount = 'my_page_video_count';

  /// チャンネルデータキー（channelId を含む）
  static String channelData(String channelId) => 'channel_data_$channelId';

  /// 特定チャンネルの動画キー
  static String channelVideos(String channelId) =>
      'subscription_videos_$channelId';

  /// 特定チャンネルのプレイリスト一覧キー
  static String channelPlaylists(String channelId) =>
      'channel_playlists_$channelId';
}

/// TTL付きメモリキャッシュのシングルトン
class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  final Map<String, _CacheEntry<dynamic>> _cache = {};

  /// デフォルトTTL（5分）
  static const Duration defaultTtl = Duration(minutes: 5);

  /// データを取得する（期限切れの場合はnullを返す）
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  /// データを保存する
  void set<T>(String key, T data, {Duration ttl = defaultTtl}) {
    _cache[key] = _CacheEntry<T>(
      data: data,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// 特定のキャッシュを無効化する
  void invalidate(String key) {
    _cache.remove(key);
  }

  /// 全キャッシュをクリアする
  void invalidateAll() {
    _cache.clear();
  }

  /// キャッシュが存在して有効かチェック
  bool isValid(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }
}
