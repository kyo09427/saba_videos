/// プレイリスト関連のSupabase操作サービス
library;

import '../models/playlist.dart';
import '../models/video.dart';
import 'supabase_service.dart';

/// プレイリストサービス（シングルトン）
class PlaylistService {
  PlaylistService._();
  static final PlaylistService instance = PlaylistService._();

  final _client = SupabaseService.instance.client;

  // ── チャンネル画面用 ─────────────────────────────────────────────────

  /// 指定ユーザーのプレイリスト一覧をメタ情報付きで取得
  ///
  /// サムネイルは各プレイリスト内の最新動画（added_at降順）から取得します。
  Future<List<PlaylistWithMeta>> getUserPlaylists(String userId) async {
    // 1) そのユーザーのプレイリストを取得
    final playlistsResponse = await _client
        .from('playlists')
        .select('id, user_id, name, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final playlists = (playlistsResponse as List)
        .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
        .toList();

    if (playlists.isEmpty) return [];

    // 2) 各プレイリストの動画本数と最新動画のサムネイルを一括取得
    final playlistIds = playlists.map((p) => p.id).toList();
    final pvResponse = await _client
        .from('playlist_videos')
        .select('playlist_id, video_id, videos!inner(url)')
        .inFilter('playlist_id', playlistIds)
        .order('added_at', ascending: false);

    // playlist_id ごとに動画を集める
    final Map<String, List<Map<String, dynamic>>> pvMap = {};
    for (final row in (pvResponse as List)) {
      final pid = row['playlist_id'] as String;
      pvMap.putIfAbsent(pid, () => []).add(row as Map<String, dynamic>);
    }

    // 3) PlaylistWithMeta を組み立てる
    return playlists.map((pl) {
      final rows = pvMap[pl.id] ?? [];
      final videoCount = rows.length;

      // 最新動画のURLからサムネイルを生成
      String? thumbnailUrl;
      if (rows.isNotEmpty) {
        final latestVideoUrl =
            rows.first['videos']?['url'] as String?;
        if (latestVideoUrl != null) {
          final videoId = _extractVideoId(latestVideoUrl);
          if (videoId != null) {
            thumbnailUrl =
                'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
          }
        }
      }

      return PlaylistWithMeta(
        playlist: pl,
        videoCount: videoCount,
        thumbnailUrl: thumbnailUrl,
      );
    }).toList();
  }

  // ── 投稿・編集画面用 ─────────────────────────────────────────────────

  /// 自分のプレイリスト一覧を取得（名前のみ）
  Future<List<Playlist>> getMyPlaylists() async {
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null) return [];

    final response = await _client
        .from('playlists')
        .select('id, user_id, name, created_at')
        .eq('user_id', currentUser.id)
        .order('created_at', ascending: false);

    return (response as List)
        .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// プレイリストを新規作成する
  ///
  /// [name] プレイリスト名（1〜50文字）
  Future<Playlist> createPlaylist(String name) async {
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null) throw Exception('ログインしていません');

    final response = await _client
        .from('playlists')
        .insert({'user_id': currentUser.id, 'name': name.trim()})
        .select()
        .single();

    return Playlist.fromJson(response as Map<String, dynamic>);
  }

  /// 指定動画が属するプレイリストのID一覧を取得（編集時の初期値用）
  Future<List<String>> getVideoPlaylistIds(String videoId) async {
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null) return [];

    // 自分のプレイリストのIDを収集
    final myPlaylists = await getMyPlaylists();
    if (myPlaylists.isEmpty) return [];
    final myPlaylistIds = myPlaylists.map((p) => p.id).toList();

    final response = await _client
        .from('playlist_videos')
        .select('playlist_id')
        .eq('video_id', videoId)
        .inFilter('playlist_id', myPlaylistIds);

    return (response as List)
        .map((r) => r['playlist_id'] as String)
        .toList();
  }

  /// 動画のプレイリスト関連付けを一括更新する
  ///
  /// 既存の関連（自分のプレイリスト分）を全削除して再挿入します。
  Future<void> setVideoPlaylists(
      String videoId, List<String> playlistIds) async {
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser == null) return;

    // 自分のプレイリストに属するvideo関連だけ削除（他人のプレイリストに影響させない）
    final myPlaylists = await getMyPlaylists();
    if (myPlaylists.isNotEmpty) {
      final myPlaylistIds = myPlaylists.map((p) => p.id).toList();
      await _client
          .from('playlist_videos')
          .delete()
          .eq('video_id', videoId)
          .inFilter('playlist_id', myPlaylistIds);
    }

    // 選択されたプレイリストに再挿入
    if (playlistIds.isNotEmpty) {
      final inserts = playlistIds
          .map((pid) => {'playlist_id': pid, 'video_id': videoId})
          .toList();
      await _client.from('playlist_videos').insert(inserts);
    }
  }

  // ── プレイリスト詳細画面用 ───────────────────────────────────────────

  /// プレイリスト内の動画一覧を追加順（新しい順）で取得
  Future<List<Video>> getPlaylistVideos(String playlistId) async {
    final response = await _client
        .from('playlist_videos')
        .select('video_id, videos!inner(*)')
        .eq('playlist_id', playlistId)
        .order('added_at', ascending: false);

    final List<Video> videos = [];
    for (final row in (response as List)) {
      final videoJson = row['videos'] as Map<String, dynamic>?;
      if (videoJson == null) continue;

      // プロフィールを取得
      final userId = videoJson['user_id'] as String?;
      if (userId != null) {
        try {
          final profileResponse = await _client
              .from('profiles')
              .select()
              .eq('id', userId)
              .maybeSingle();
          if (profileResponse != null) {
            videoJson['profiles'] = profileResponse;
          }
        } catch (_) {}
      }

      // タグを取得
      final videoId = videoJson['id'] as String?;
      if (videoId != null) {
        try {
          final tagsResponse = await _client
              .from('video_tags')
              .select('tags!inner(name)')
              .eq('video_id', videoId);
          videoJson['tags'] = (tagsResponse as List)
              .map((t) => t['tags']?['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty)
              .toList();
        } catch (_) {
          videoJson['tags'] = <String>[];
        }
      }

      final video = Video.fromJsonWithProfile(videoJson);
      if (video.id.isNotEmpty) videos.add(video);
    }
    return videos;
  }

  // ── ユーティリティ ────────────────────────────────────────────────────

  /// YouTube URLからビデオIDを抽出（サムネイル生成用）
  static String? _extractVideoId(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      if (uri.host == 'youtu.be' || uri.host == 'www.youtu.be') {
        if (uri.pathSegments.isEmpty) return null;
        final id = uri.pathSegments[0].split('?')[0];
        return id.length == 11 ? id : null;
      }

      if (uri.host.contains('youtube.com')) {
        final id = uri.queryParameters['v'];
        if (id != null && id.length == 11) return id;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
