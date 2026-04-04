import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/video.dart';
import '../../services/app_update_service.dart';
import '../../services/cache_service.dart';
import '../../services/notification_service.dart';
import '../../services/search_history_service.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/update_dialog.dart';
import '../notifications/notifications_screen.dart';
import '../../utils/japanese_text_utils.dart';
import '../../widgets/app_navigation_scaffold.dart';
import '../../widgets/skeleton_widgets.dart';
import '../auth/login_screen.dart';
import '../channel/channel_screen.dart';
import '../post/post_video_screen.dart';
import '../profile/my_videos_screen.dart';
import '../search/search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = SupabaseService.instance.client;
  List<Video> _videos = [];
  List<Video> _filteredVideos = [];
  bool _isLoading = true;
  String? _errorMessage;
  RealtimeChannel? _realtimeChannel;
  String _selectedFilter = 'すべて';
  final List<String> _filterCategories = [
    'すべて',
    '新しい動画',
    '雑談',
    'ゲーム',
    '音楽',
    'ネタ',
    'その他',
  ];

  // デザイン用カラー（テーマ対応ゲッター）
  static const Color _ytRed = Color(0xFFF20D0D);
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _ytBackground => Theme.of(context).scaffoldBackgroundColor;
  Color get _ytSurface => Theme.of(context).colorScheme.surface;
  Color get _textWhite => Theme.of(context).colorScheme.onSurface;
  Color get _textGray => Theme.of(context).colorScheme.onSurfaceVariant;

  // 検索関連
  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();
  final SearchController _pcSearchController = SearchController();
  String _searchQuery = '';

  // ページネーション
  int _offset = 0;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounce;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _setupRealtimeSubscription();
    _scrollController.addListener(_onScroll);
    // アップデート確認（フレーム描画後に実行）
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  void _onScroll() {
    if (_scrollDebounce?.isActive ?? false) return;
    _scrollDebounce = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.85) {
        _loadMoreVideos();
      }
    });
  }

  Future<void> _checkForUpdate() async {
    final updateInfo = await AppUpdateService.instance.checkForUpdate();
    if (updateInfo != null && mounted) {
      await UpdateDialog.show(context, updateInfo);
    }
  }

  @override
  void dispose() {
    _cleanupRealtimeSubscription();
    _searchController.dispose();
    _pcSearchController.dispose();
    _scrollDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// リアルタイム購読のクリーンアップ
  void _cleanupRealtimeSubscription() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }

  Future<void> _loadVideos({bool isRefresh = false}) async {
    if (!mounted) return;

    // リフレッシュ時はキャッシュとページネーション状態をリセット
    if (isRefresh) {
      CacheService.instance.invalidate(CacheKeys.homeVideos);
      _offset = 0;
      _hasMore = true;
    }

    // ── キャッシュ読み込み（初回表示のみ、リフレッシュ時はスキップ）──
    if (!isRefresh) {
      final cached = CacheService.instance.get<List<Video>>(CacheKeys.homeVideos);
      if (cached != null) {
        if (mounted) {
          setState(() {
            _videos = cached;
            _offset = cached.length;
            _applyFilter();
            _isLoading = false;
          });
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 動画データを取得（最初の _pageSize 件のみ）
      final response = await _supabase
          .from('videos')
          .select('*')
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      final videosData = response is List<dynamic> ? response : <dynamic>[];

      // 各動画のユーザーIDを収集（重複を除く）
      final userIds = videosData
          .whereType<Map<String, dynamic>>()
          .map((v) => v['user_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      // プロフィール情報を一括取得
      Map<String, dynamic> profilesMap = {};
      if (userIds.isNotEmpty) {
        final profilesResponse = await _supabase
            .from('profiles')
            .select('*')
            .inFilter('id', userIds);

        for (final profile in (profilesResponse is List ? profilesResponse : <dynamic>[])) {
          if (profile is Map<String, dynamic>) {
            final id = profile['id'] as String?;
            if (id != null) profilesMap[id] = profile;
          }
        }
      }

      // 各動画のタグ情報を取得
      Map<String, List<String>> videoTagsMap = {};
      if (videosData.isNotEmpty) {
        final videoIds = videosData
            .whereType<Map<String, dynamic>>()
            .map((v) => v['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        // video_tagsテーブルとtagsテーブルをJOINして取得
        final tagsResponse = await _supabase
            .from('video_tags')
            .select('video_id, tags!inner(name)')
            .inFilter('video_id', videoIds);

        for (final item in (tagsResponse is List ? tagsResponse : <dynamic>[])) {
          if (item is! Map<String, dynamic>) continue;
          final videoId = item['video_id'] as String? ?? '';
          final tagName = item['tags'] is Map
              ? (item['tags'] as Map)['name'] as String? ?? ''
              : '';
          if (videoId.isEmpty || tagName.isEmpty) continue;

          if (!videoTagsMap.containsKey(videoId)) {
            videoTagsMap[videoId] = [];
          }
          videoTagsMap[videoId]!.add(tagName);
        }
      }

      // 動画データとプロフィール情報、タグ情報を結合
      final videos = videosData
          .whereType<Map<String, dynamic>>()
          .map((videoJson) {
            final userId = videoJson['user_id'] as String?;
            if (userId != null && profilesMap.containsKey(userId)) {
              videoJson['profiles'] = profilesMap[userId];
            }

            // タグ情報を追加
            final videoId = videoJson['id'] as String? ?? '';
            videoJson['tags'] = videoTagsMap[videoId] ?? [];

            return Video.fromJsonWithProfile(videoJson);
          })
          .where((video) => video.id.isNotEmpty)
          .toList();

      // ページネーション状態を更新
      _offset = videos.length;
      _hasMore = videosData.length == _pageSize;

      // キャッシュに保存
      CacheService.instance.set<List<Video>>(CacheKeys.homeVideos, videos);

      if (mounted) {
        setState(() {
          _videos = videos;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading videos: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '動画の読み込みに失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  /// スクロール末端に達したら追加の動画を取得する
  Future<void> _loadMoreVideos() async {
    if (!mounted || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final response = await _supabase
          .from('videos')
          .select('*')
          .order('created_at', ascending: false)
          .range(_offset, _offset + _pageSize - 1);

      final videosData = response is List<dynamic> ? response : <dynamic>[];
      if (videosData.isEmpty) {
        if (mounted) setState(() { _hasMore = false; _isLoadingMore = false; });
        return;
      }

      // プロフィール情報を一括取得
      final userIds = videosData
          .whereType<Map<String, dynamic>>()
          .map((v) => v['user_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, dynamic> profilesMap = {};
      if (userIds.isNotEmpty) {
        final profilesResponse = await _supabase
            .from('profiles')
            .select('*')
            .inFilter('id', userIds);
        for (final profile in (profilesResponse is List ? profilesResponse : <dynamic>[])) {
          if (profile is Map<String, dynamic>) {
            final id = profile['id'] as String?;
            if (id != null) profilesMap[id] = profile;
          }
        }
      }

      // タグ情報を一括取得
      final videoIds = videosData
          .whereType<Map<String, dynamic>>()
          .map((v) => v['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      Map<String, List<String>> videoTagsMap = {};
      if (videoIds.isNotEmpty) {
        final tagsResponse = await _supabase
            .from('video_tags')
            .select('video_id, tags!inner(name)')
            .inFilter('video_id', videoIds);
        for (final item in (tagsResponse is List ? tagsResponse : <dynamic>[])) {
          if (item is! Map<String, dynamic>) continue;
          final videoId = item['video_id'] as String? ?? '';
          final tagName = item['tags'] is Map
              ? (item['tags'] as Map)['name'] as String? ?? ''
              : '';
          if (videoId.isEmpty || tagName.isEmpty) continue;
          videoTagsMap.putIfAbsent(videoId, () => []).add(tagName);
        }
      }

      final newVideos = videosData
          .whereType<Map<String, dynamic>>()
          .map((videoJson) {
            final userId = videoJson['user_id'] as String?;
            if (userId != null && profilesMap.containsKey(userId)) {
              videoJson['profiles'] = profilesMap[userId];
            }
            final videoId = videoJson['id'] as String? ?? '';
            videoJson['tags'] = videoTagsMap[videoId] ?? [];
            return Video.fromJsonWithProfile(videoJson);
          })
          .where((video) => video.id.isNotEmpty)
          .toList();

      _offset += videosData.length;
      _hasMore = videosData.length == _pageSize;

      final allVideos = [..._videos, ...newVideos];
      CacheService.instance.set<List<Video>>(CacheKeys.homeVideos, allVideos);

      if (mounted) {
        setState(() {
          _videos = allVideos;
          _applyFilter();
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading more videos: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel = _supabase
        .channel('videos_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'videos',
          callback: (payload) {
            if (mounted) {
              _loadVideos(isRefresh: true);
            }
          },
        )
        .subscribe();
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _ytSurface,
        title: Text('ログアウト', style: TextStyle(color: _textWhite)),
        content: Text('ログアウトしますか?', style: TextStyle(color: _textWhite)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ログアウト', style: TextStyle(color: _ytRed)),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      try {
        // リアルタイム購読をクリーンアップ
        _cleanupRealtimeSubscription();
        
        await SupabaseService.instance.signOut();
        
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ログアウトに失敗しました: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _navigateToPostScreen() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PostVideoScreen()),
    );
    
    // 投稿画面から戻ってきた場合、明示的にリフレッシュ
    if (result == true && mounted) {
      await _loadVideos(isRefresh: true);
    }
  }

  Future<void> _handleVideoTap(Video video) async {
    if (video.url.isEmpty) {
      _showErrorSnackBar('無効な動画URLです');
      return;
    }

    final success = await YouTubeService.launchVideo(video.url);
    
    if (!success && mounted) {
      _showErrorSnackBar('動画を開けませんでした');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// カテゴリフィルター部分
  Widget _buildCategoryPills() {
    return SliverToBoxAdapter(
      child: Container(
        height: 48,
        color: _ytBackground.withValues(alpha: 0.95),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _filterCategories.length + 1, // +1 for explore icon
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            // 探索アイコン
            if (index == 0) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _ytSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.explore_outlined, color: _textWhite, size: 20),
              );
            }
            
            final category = _filterCategories[index - 1];
            final isSelected = _selectedFilter == category;
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFilter = category;
                  _applyFilter();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black87)
                      : (isDark ? const Color(0xFF272727) : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isSelected
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? Colors.white : Colors.black87),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }



  /// フィルターを適用
  void _applyFilter() {
    // ステップ1: カテゴリフィルター
    List<Video> afterCategory;
    if (_selectedFilter == 'すべて') {
      afterCategory = _videos;
    } else if (_selectedFilter == '新しい動画') {
      final lastWeek = DateTime.now().subtract(const Duration(days: 7));
      afterCategory = _videos.where((v) => v.createdAt.isAfter(lastWeek)).toList();
    } else {
      afterCategory = _videos.where((v) => v.mainCategory == _selectedFilter).toList();
    }

    // ステップ2: 検索クエリフィルター（ヒラガナ/カタカナ区別なし）
    if (_searchQuery.isEmpty) {
      _filteredVideos = afterCategory;
    } else {
      _filteredVideos = afterCategory.where((v) {
        // タイトルで検索
        if (containsIgnoreKana(v.title, _searchQuery)) return true;
        // メインカテゴリで検索
        if (containsIgnoreKana(v.mainCategory, _searchQuery)) return true;
        // タグで検索
        if (v.tags.any((tag) => containsIgnoreKana(tag, _searchQuery))) return true;
        return false;
      }).toList();
    }
  }

  /// カテゴリに応じた色を返す
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'ゲーム':
        return const Color(0xFF9C27B0); // 紫
      case '音楽':
        return const Color(0xFFE91E63); // ピンク
      case 'ネタ':
        return const Color(0xFFFF9800); // オレンジ
      case 'その他':
        return const Color(0xFF607D8B); // グレー
      case '雑談':
      default:
        return const Color(0xFF2196F3); // 青
    }
  }

  Widget _buildVideoCard(Video video) {
    return InkWell(
      onTap: () => _handleVideoTap(video),
      onLongPress: () => _showVideoOptions(video),
      child: Column(
        children: [
          // サムネイル
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: video.thumbnailUrl != null && video.thumbnailUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: video.thumbnailUrl!,
                        memCacheWidth: 640,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: _ytSurface,
                          child: Center(
                            child: CircularProgressIndicator(color: _accent),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: _ytSurface,
                          child: Center(
                            child: Icon(Icons.play_circle_outline,
                                color: _textGray, size: 48),
                          ),
                        ),
                      )
                    : Container(
                        color: _ytSurface,
                        child: Center(
                          child: Icon(Icons.video_library_outlined,
                              color: _textGray, size: 48),
                        ),
                      ),
              ),
              // 時間表示バッジ（保存済みの再生時間があれば表示）
              if (video.duration != null && video.duration!.isNotEmpty)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      video.duration!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
            ],
          ),
          // 動画詳細情報
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ユーザーアバター（実際のプロフィール情報を使用）
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(ChannelScreen.route(video.userId));
                  },
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.purple,
                    backgroundImage: video.userProfile?.avatarUrl != null
                        ? NetworkImage(video.userProfile!.avatarUrl!)
                        : null,
                    child: video.userProfile?.avatarUrl == null
                        ? Text(
                            video.userProfile?.initials ?? '?',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textWhite,
                          fontSize: 15,
                          fontWeight: FontWeight.normal,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${video.userProfile?.username ?? "不明"} • ${video.relativeTime}',
                        style: TextStyle(color: _textGray, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // メインカテゴリバッジのみ表示（サブカテゴリタグは内部で検索等に使用）
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(video.mainCategory),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video.mainCategory,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showVideoOptions(video),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.more_vert, color: _textWhite, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 三点リーダーのオプションシートを表示
  void _showVideoOptions(Video video) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isOwner = currentUserId != null && video.userId == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: _ytSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ハンドル
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _textGray.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.account_circle_outlined, color: _textWhite),
              title: Text('チャンネルへ移動', style: TextStyle(color: _textWhite)),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(ChannelScreen.route(video.userId));
              },
            ),
            if (isOwner) ...[
              ListTile(
                leading: Icon(Icons.edit_outlined, color: _textWhite),
                title: Text('編集', style: TextStyle(color: _textWhite)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _handleEdit(video);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('削除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _handleDelete(video);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 編集ボトムシートを表示
  Future<void> _handleEdit(Video video) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditVideoSheet(video: video),
    );

    if (result == true && mounted) {
      CacheService.instance.invalidate(CacheKeys.homeVideos);
      await _loadVideos(isRefresh: true);
    }
  }

  /// 削除確認ダイアログを表示
  Future<void> _handleDelete(Video video) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _ytSurface,
        title: Text('動画を削除', style: TextStyle(color: _textWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${video.title}」を削除しますか？',
                style: TextStyle(color: _textWhite)),
            const SizedBox(height: 8),
            Text('削除すると元に戻せません。',
                style: TextStyle(color: _textGray, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('キャンセル', style: TextStyle(color: _textGray)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: _ytRed),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await _supabase.from('video_tags').delete().eq('video_id', video.id);
      await _supabase.from('videos').delete().eq('id', video.id);
      CacheService.instance.invalidate(CacheKeys.homeVideos);
      CacheService.instance.invalidate(CacheKeys.myVideos);
      CacheService.instance.invalidate(CacheKeys.myPageTotalViews);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('動画を削除しました'), backgroundColor: Colors.green,
              duration: Duration(seconds: 2)),
        );
        await _loadVideos(isRefresh: true);
      }
    } catch (e) {
      debugPrint('❌ Error deleting video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除に失敗しました'), backgroundColor: Colors.red,
              duration: Duration(seconds: 2)),
        );
      }
    }
  }

  /// スケルトンビュー（初回ロード中に表示）
  Widget _buildSkeletonView() {
    return Container(
      color: _ytBackground,
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          // ヘッダースケルトン
          SliverAppBar(
            floating: true,
            backgroundColor: _ytBackground.withValues(alpha: 0.95),
            elevation: 0,
            titleSpacing: 0,
            leadingWidth: 0,
            leading: const SizedBox.shrink(),
            automaticallyImplyLeading: false,
            title: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.play_circle_filled, color: _ytRed, size: 30),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'SabaTube',
                    style: TextStyle(
                      color: _textWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // カテゴリフィルタースケルトン
          SliverToBoxAdapter(
            child: Container(
              height: 48,
              color: _ytBackground.withValues(alpha: 0.95),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: List.generate(
                  5,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SkeletonBox(width: 60 + i * 5.0, height: 32),
                  ),
                ),
              ),
            ),
          ),
          // 動画カードスケルトン
          const SkeletonSliverList(
            itemBuilder: SkeletonVideoCardLarge.new,
            itemCount: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: _ytRed, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'エラーが発生しました',
              style: TextStyle(color: _textWhite),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadVideos(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _ytSurface,
                foregroundColor: _textWhite,
              ),
              child: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }

  /// セル幅から childAspectRatio を動的計算する。
  /// サムネイル(16:9) + 情報エリア固定高さ でセル高さを求め、比率を返す。
  double _calcAspectRatio(double screenWidth, int columns) {
    const hPad = 24.0;    // SliverPadding horizontal: 12×2
    const spacing = 12.0; // crossAxisSpacing
    const infoH = 114.0;  // 情報エリア固定高さ（padding+avatar+テキスト+バッジ）
    final cellW = (screenWidth - hPad - (columns - 1) * spacing) / columns;
    final thumbH = cellW * 9 / 16;
    return cellW / (thumbH + infoH);
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationScaffold(
      currentIndex: 0,
      backgroundColor: _ytBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // サイドバー分を除いた実際の利用可能幅で列数・比率を計算
          final screenWidth = constraints.maxWidth;
          int crossAxisCount;
          double childAspectRatio;

          if (screenWidth < 600) {
            crossAxisCount = 1;
            childAspectRatio = 1.0; // 1列はSliverListを使うので参照されない
          } else if (screenWidth < 900) {
            crossAxisCount = 2;
            childAspectRatio = _calcAspectRatio(screenWidth, 2);
          } else if (screenWidth < 1200) {
            crossAxisCount = 3;
            childAspectRatio = _calcAspectRatio(screenWidth, 3);
          } else {
            crossAxisCount = 4;
            childAspectRatio = _calcAspectRatio(screenWidth, 4);
          }

          return SafeArea(
            bottom: false,
        child: _isLoading
            ? _buildSkeletonView()
            : _errorMessage != null
                ? _buildErrorView()
                : RefreshIndicator(
                    onRefresh: () => _loadVideos(isRefresh: true),
                    color: _accent,
                    backgroundColor: _ytSurface,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: kIsWeb
                          ? const ClampingScrollPhysics()
                          : const BouncingScrollPhysics(),
                      slivers: [
                        // ヘッダー
                        SliverAppBar(
                          floating: true,
                          backgroundColor: _ytBackground.withValues(alpha: 0.95),
                          elevation: 0,
                          titleSpacing: 0,
                          leadingWidth: 0,
                          leading: const SizedBox.shrink(),
                          automaticallyImplyLeading: false,
                          title: screenWidth >= 600
                              ? _buildPCAppBarTitle(context)
                              : _buildMobileAppBarTitle(context),
                          actions: screenWidth >= 600
                              ? _buildPCAppBarActions()
                              : _buildMobileAppBarActions(),
                        ),

                        // カテゴリフィルター
                        _buildCategoryPills(),

                        // コンテンツ
                        if (_filteredVideos.isEmpty)
                          SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.video_library_outlined,
                                      size: 80, color: _ytSurface),
                                  const SizedBox(height: 16),
                                  Text('動画がありません',
                                      style: TextStyle(color: _textGray)),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: _navigateToPostScreen,
                                    icon: const Icon(Icons.add),
                                    label: const Text('最初の動画を投稿'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _ytRed,
                                      foregroundColor: _textWhite,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          // 動画リスト/グリッド
                          // 1列はSliverList（自然な高さ）、複数列はSliverGrid
                          if (crossAxisCount == 1)
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => RepaintBoundary(
                                  child: _buildVideoCard(_filteredVideos[index]),
                                ),
                                childCount: _filteredVideos.length,
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              sliver: SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: childAspectRatio,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => RepaintBoundary(
                                    child: _buildVideoCard(_filteredVideos[index]),
                                  ),
                                  childCount: _filteredVideos.length,
                                ),
                              ),
                            ),

                          if (_isLoadingMore)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(color: _accent),
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 80)),
                        ],
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  // --- [AppBar Helper Methods] ---

  Widget _buildPCAppBarTitle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? const Color(0xFFAAAAAA) : Colors.black45;
    final textColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final borderColor = isDark ? const Color(0xFF333333) : Colors.grey.shade300;

    final hasSidebar = MediaQuery.of(context).size.width >= 1100;

    return Row(
      children: [
        // ロゴ（サイドバーがない場合のみ表示）
        if (!hasSidebar)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Image.asset('icon.png', height: 30),
                const SizedBox(width: 4),
                Text(
                  'SabaTube',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
          ),
        // 検索バー (ドロップダウン)
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SearchAnchor(
                searchController: _pcSearchController,
                isFullScreen: false,
                // ドロップダウン内でEnterキーを押した時の動作
                viewOnSubmitted: (value) async {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty) {
                    await SearchHistoryService.instance.addSearchQuery(trimmed);
                  }
                  if (_pcSearchController.isOpen) {
                    _pcSearchController.closeView(trimmed);
                  } else {
                    _pcSearchController.text = trimmed;
                  }
                  setState(() {
                    _searchQuery = trimmed;
                    _applyFilter();
                  });
                },
                builder: (context, controller) {
                  return SearchBar(
                    controller: controller,
                    onTap: () {
                      if (!controller.isOpen) {
                        controller.openView();
                      }
                    },
                    onChanged: (_) {
                      if (!controller.isOpen) {
                        controller.openView();
                      }
                    },
                    constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
                    hintText: 'タイトル・カテゴリ・タグを検索',
                    hintStyle: WidgetStateProperty.all(TextStyle(color: hintColor, fontSize: 15)),
                    textStyle: WidgetStateProperty.all(TextStyle(color: textColor, fontSize: 15)),
                    backgroundColor: WidgetStateProperty.all(bgColor),
                    elevation: WidgetStateProperty.all(0),
                    side: WidgetStateProperty.all(BorderSide(color: borderColor)),
                    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16)),
                    leading: Icon(Icons.search, color: hintColor),
                    // ×ボタンの表示はコントローラーの文字数を直接監視してUIだけ更新(ListenableBuilder)
                    trailing: [
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, child) {
                          if (value.text.isNotEmpty) {
                            return IconButton(
                              icon: Icon(Icons.close, color: hintColor, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                controller.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _applyFilter();
                                });
                              },
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                    // Anchor(窓の部分)でEnterを押した時の動作
                    onSubmitted: (value) async {
                      final trimmed = value.trim();
                      if (trimmed.isNotEmpty) {
                        await SearchHistoryService.instance.addSearchQuery(trimmed);
                      }
                      if (!mounted) return;
                      if (controller.isOpen) {
                        controller.closeView(trimmed);
                      } else {
                        controller.text = trimmed;
                        FocusScope.of(context).unfocus();
                      }
                      setState(() {
                        _searchQuery = trimmed;
                        _applyFilter();
                      });
                    },
                  );
                },
                suggestionsBuilder: (context, controller) async {
                  final history = await SearchHistoryService.instance.getSearchHistory();
                  return history.map((query) => ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(query),
                        trailing: IconButton(
                          icon: const Icon(Icons.north_west, size: 20),
                          onPressed: () {
                            controller.text = query;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: query.length),
                            );
                          },
                        ),
                        // 履歴から選んだ時の動作
                        onTap: () async {
                          controller.closeView(query);
                          await SearchHistoryService.instance.addSearchQuery(query);
                          setState(() {
                            _searchQuery = query;
                            _applyFilter();
                          });
                        },
                      )).toList();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileAppBarTitle(BuildContext context) {
    if (!_isSearchActive) {
      return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Image.asset('icon.png', height: 30),
            const SizedBox(width: 4),
            Text(
              'SabaTube',
              style: TextStyle(
                color: _textWhite,
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      );
    }
    
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final hintColor = isDark ? const Color(0xFFAAAAAA) : Colors.black45;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: TextField(
          controller: _searchController,
          readOnly: true, // タップで画面遷移のみ
          onTap: () async {
            final result = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SearchScreen(initialQuery: _searchQuery),
              ),
            );
            if (result != null && result is String) {
              setState(() {
                _searchQuery = result;
                _searchController.text = result;
                _isSearchActive = result.isNotEmpty;
                _applyFilter();
              });
            }
          },
          style: TextStyle(color: textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'タイトル・カテゴリ・タグで検索',
            hintStyle: TextStyle(color: hintColor, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 9),
            prefixIcon: Icon(Icons.search, size: 18, color: hintColor),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSharedActions() {
    return [
      ValueListenableBuilder<int>(
        valueListenable: NotificationService.instance.unreadCount,
        builder: (context, count, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                },
                color: _textWhite,
              ),
              if (count > 0)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _ytRed,
                      border: Border.all(color: _ytBackground, width: 1.5),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _buildPCAppBarActions() {
    return [
      ..._buildSharedActions(),
    ];
  }

  List<Widget> _buildMobileAppBarActions() {
    return [
      if (!_isSearchActive) ..._buildSharedActions(),
      IconButton(
        icon: Icon(_isSearchActive ? Icons.close : Icons.search),
        color: _textWhite,
        onPressed: () async {
          if (!_isSearchActive) {
            final result = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SearchScreen(initialQuery: _searchQuery),
              ),
            );
            if (result != null && result is String) {
              setState(() {
                _searchQuery = result;
                _isSearchActive = result.isNotEmpty;
                _searchController.text = result;
                _applyFilter();
              });
            }
          } else {
            setState(() {
              _isSearchActive = false;
              _searchController.clear();
              _searchQuery = '';
              _applyFilter();
            });
          }
        },
      ),
    ];
  }
}