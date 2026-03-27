import 'package:flutter/material.dart';
import '../../models/playlist.dart';
import '../../models/user_profile.dart';
import '../../models/video.dart';
import '../../models/channel_stats.dart';
import '../../screens/playlist/playlist_detail_screen.dart';
import '../../services/cache_service.dart';
import '../../services/playlist_service.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/skeleton_widgets.dart';

/// チャンネル画面
///
/// 特定のユーザーのチャンネル情報と動画一覧、プレイリスト一覧を表示します。
class ChannelScreen extends StatefulWidget {
  final String channelId;

  const ChannelScreen({
    super.key,
    required this.channelId,
  });

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen>
    with TickerProviderStateMixin {
  final _supabase = SupabaseService.instance.client;
  UserProfile? _channelProfile;
  List<Video> _videos = [];
  List<PlaylistWithMeta> _playlists = [];
  ChannelStats? _stats;
  bool _isLoading = true;
  bool _isSubscribed = false;
  String? _errorMessage;

  late TabController _tabController;

  // デザイン用カラー定義
  final Color _ytBackground = const Color(0xFF0F0F0F);
  final Color _ytSurface = const Color(0xFF272727);
  final Color _ytRed = const Color(0xFFF20D0D);
  final Color _textWhite = Colors.white;
  final Color _textGray = const Color(0xFFAAAAAA);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadChannelData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// チャンネルデータを読み込む
  Future<void> _loadChannelData({bool isRefresh = false}) async {
    if (!mounted) return;

    // ── キャッシュ読み込み（初回表示のみ）──
    if (!isRefresh) {
      final cacheKey = CacheKeys.channelData(widget.channelId);
      final cached =
          CacheService.instance.get<Map<String, dynamic>>(cacheKey);
      if (cached != null) {
        final profile = cached['profile'] as UserProfile;
        final videos = cached['videos'] as List<Video>;
        final stats = cached['stats'] as ChannelStats;
        final isSubscribed = cached['isSubscribed'] as bool;
        final playlists =
            cached['playlists'] as List<PlaylistWithMeta>? ?? [];
        if (mounted) {
          setState(() {
            _channelProfile = profile;
            _videos = videos;
            _stats = stats;
            _isSubscribed = isSubscribed;
            _playlists = playlists;
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
      // プロフィール情報を取得
      final profileResponse = await _supabase
          .from('profiles')
          .select()
          .eq('id', widget.channelId)
          .single();

      final profile = UserProfile.fromJson(profileResponse);

      // 動画一覧を取得
      final videosResponse = await _supabase
          .from('videos')
          .select()
          .eq('user_id', widget.channelId)
          .order('created_at', ascending: false);

      final videos = (videosResponse as List)
          .map((v) => Video.fromJson(v as Map<String, dynamic>).copyWith(
                userProfile: profile,
              ))
          .where((v) => v.id.isNotEmpty)
          .toList();

      // プレイリスト一覧を取得
      List<PlaylistWithMeta> playlists = [];
      try {
        playlists = await PlaylistService.instance
            .getUserPlaylists(widget.channelId);
      } catch (e) {
        debugPrint('⚠️ Failed to load playlists: $e');
      }

      // 統計情報を取得
      final subscriberCount = await SupabaseService.instance
          .getSubscriberCount(widget.channelId);
      final videoCount = videos.length;

      final stats = ChannelStats(
        channelId: widget.channelId,
        subscriberCount: subscriberCount,
        videoCount: videoCount,
      );

      // 登録状態を確認
      final isSubscribed =
          await SupabaseService.instance.isSubscribed(widget.channelId);

      // キャッシュに保存
      CacheService.instance.set<Map<String, dynamic>>(
        CacheKeys.channelData(widget.channelId),
        {
          'profile': profile,
          'videos': videos,
          'stats': stats,
          'isSubscribed': isSubscribed,
          'playlists': playlists,
        },
      );

      // プレイリストは専用キーでもキャッシュ
      CacheService.instance.set<List<PlaylistWithMeta>>(
        CacheKeys.channelPlaylists(widget.channelId),
        playlists,
      );

      if (mounted) {
        setState(() {
          _channelProfile = profile;
          _videos = videos;
          _stats = stats;
          _isSubscribed = isSubscribed;
          _playlists = playlists;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading channel data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'チャンネル情報の読み込みに失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  /// 登録/登録解除を処理
  Future<void> _toggleSubscription() async {
    try {
      if (_isSubscribed) {
        await SupabaseService.instance
            .unsubscribeFromChannel(widget.channelId);
      } else {
        await SupabaseService.instance.subscribeToChannel(widget.channelId);
      }

      // キャッシュを無効化して再読み込み
      CacheService.instance
          .invalidate(CacheKeys.channelData(widget.channelId));
      CacheService.instance
          .invalidate(CacheKeys.channelPlaylists(widget.channelId));
      CacheService.instance.invalidate(CacheKeys.subscribedChannelIds);
      CacheService.instance.invalidate(CacheKeys.subscriptionVideos);
      await _loadChannelData(isRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isSubscribed ? 'チャンネル登録しました！' : 'チャンネル登録を解除しました'),
            backgroundColor: _isSubscribed ? Colors.grey : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 動画をタップしたときの処理
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

  /// 動画カードを構築
  Widget _buildVideoCard(Video video) {
    return InkWell(
      onTap: () => _handleVideoTap(video),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // サムネイル
            SizedBox(
              width: 160,
              height: 90,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: video.thumbnailUrl != null
                        ? Image.network(
                            video.thumbnailUrl!,
                            width: 160,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              width: 160,
                              height: 90,
                              color: _ytSurface,
                              child: Icon(Icons.play_circle_outline,
                                  color: _textGray, size: 36),
                            ),
                          )
                        : Container(
                            width: 160,
                            height: 90,
                            color: _ytSurface,
                            child: Icon(Icons.video_library_outlined,
                                color: _textGray, size: 36),
                          ),
                  ),
                  // 時間表示（durationが設定されている場合のみ表示）
                  if (video.duration != null && video.duration!.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video.duration!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 動画情報
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
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.relativeTime,
                    style: TextStyle(color: _textGray, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// プレイリストカードを構築（グリッドセル）
  Widget _buildPlaylistCard(PlaylistWithMeta playlist) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                PlaylistDetailScreen(playlist: playlist),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // サムネイル
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: playlist.thumbnailUrl != null
                      ? Image.network(
                          playlist.thumbnailUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: _ytSurface,
                            child: Icon(Icons.playlist_play,
                                color: _textGray, size: 40),
                          ),
                        )
                      : Container(
                          color: _ytSurface,
                          child: Icon(Icons.playlist_play,
                              color: _textGray, size: 40),
                        ),
                ),
                // 「N本の動画」バッジ（右下）
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.playlist_play,
                            color: Colors.white, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          playlist.videoCountLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          // プレイリスト名
          Text(
            playlist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textWhite,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonView() {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: _ytBackground,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: _textWhite),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SliverToBoxAdapter(child: SkeletonChannelHeader()),
        SliverToBoxAdapter(
          child: Container(height: 48, color: _ytBackground),
        ),
        const SkeletonSliverList(
          itemBuilder: SkeletonVideoCardSmall.new,
          itemCount: 4,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = SupabaseService.instance.currentUser?.id;
    final isOwnChannel = currentUserId == widget.channelId;

    return Scaffold(
      backgroundColor: _ytBackground,
      body: SafeArea(
        child: _isLoading
            ? _buildSkeletonView()
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: _ytRed, size: 48),
                        const SizedBox(height: 16),
                        Text(_errorMessage!,
                            style: TextStyle(color: _textWhite)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadChannelData,
                          child: const Text('再読み込み'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadChannelData(isRefresh: true),
                    color: _ytRed,
                    backgroundColor: _ytSurface,
                    child: NestedScrollView(
                      headerSliverBuilder:
                          (context, innerBoxIsScrolled) => [
                        // ── ナビゲーションバー ──
                        SliverAppBar(
                          floating: true,
                          backgroundColor: _ytBackground,
                          elevation: 0,
                          leading: IconButton(
                            icon: Icon(Icons.arrow_back, color: _textWhite),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          actions: [
                            IconButton(
                                icon: Icon(Icons.cast, color: _textWhite),
                                onPressed: () {}),
                            IconButton(
                                icon: Icon(Icons.search, color: _textWhite),
                                onPressed: () {}),
                            IconButton(
                                icon:
                                    Icon(Icons.more_vert, color: _textWhite),
                                onPressed: () {}),
                          ],
                        ),

                        // ── プロフィールセクション ──
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 40,
                                      backgroundColor: Colors.purple,
                                      backgroundImage:
                                          _channelProfile?.avatarUrl != null
                                              ? NetworkImage(
                                                  _channelProfile!.avatarUrl!)
                                              : null,
                                      child:
                                          _channelProfile?.avatarUrl == null
                                              ? Text(
                                                  _channelProfile?.initials ??
                                                      '?',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 28),
                                                )
                                              : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _channelProfile?.username ?? '不明',
                                            style: TextStyle(
                                              color: _textWhite,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '登録者 ${_stats?.subscriberCount ?? 0}人 • 動画 ${_stats?.videoCount ?? 0}本',
                                            style: TextStyle(
                                                color: _textGray,
                                                fontSize: 12),
                                          ),
                                          if (_channelProfile?.bio != null &&
                                              _channelProfile!
                                                  .bio!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _channelProfile!.bio!,
                                              style: TextStyle(
                                                  color: _textGray,
                                                  fontSize: 11),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (!isOwnChannel) ...[
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _toggleSubscription,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSubscribed
                                            ? _ytSurface
                                            : _textWhite,
                                        foregroundColor: _isSubscribed
                                            ? _textWhite
                                            : Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                      ),
                                      child: Text(
                                        _isSubscribed ? '登録済み' : '登録',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // ── タブバー ──
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _SliverTabBarDelegate(
                            tabBar: TabBar(
                              controller: _tabController,
                              indicatorColor: _textWhite,
                              labelColor: _textWhite,
                              unselectedLabelColor: _textGray,
                              labelStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                              unselectedLabelStyle:
                                  const TextStyle(fontSize: 14),
                              tabs: const [
                                Tab(text: '動画'),
                                Tab(text: 'プレイリスト'),
                              ],
                            ),
                            color: _ytBackground,
                          ),
                        ),
                      ],
                      body: TabBarView(
                        controller: _tabController,
                        children: [
                          // ── 動画タブ ──
                          _videos.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.video_library_outlined,
                                          size: 80, color: _ytSurface),
                                      const SizedBox(height: 16),
                                      Text('動画がありません',
                                          style:
                                              TextStyle(color: _textGray)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: _videos.length,
                                  itemBuilder: (context, index) =>
                                      _buildVideoCard(_videos[index]),
                                ),

                          // ── プレイリストタブ ──
                          _playlists.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.playlist_play_outlined,
                                          size: 80, color: _ytSurface),
                                      const SizedBox(height: 16),
                                      Text('プレイリストがありません',
                                          style:
                                              TextStyle(color: _textGray)),
                                    ],
                                  ),
                                )
                              // レスポンシブグリッド（画面幅に応じて列数・カードサイズを自動調整）
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final width = constraints.maxWidth;
                                    // 幅に応じた列数（モバイル2列、タブ3列、デスク4列）
                                    final cols = width < 400
                                        ? 2
                                        : width < 700
                                            ? 3
                                            : 4;
                                    // サムネイル(16:9) + テキスト2行分
                                    final cardW =
                                        (width - 10.0 * (cols + 1)) / cols;
                                    final cardH = cardW * 9 / 16 + 46;
                                    return GridView.builder(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: cols,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 10,
                                        childAspectRatio: cardW / cardH,
                                      ),
                                      itemCount: _playlists.length,
                                      itemBuilder: (context, index) =>
                                          _buildPlaylistCard(
                                              _playlists[index]),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

/// TabBar用 SliverPersistentHeaderDelegate
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color color;

  _SliverTabBarDelegate({required this.tabBar, required this.color});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: color, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar || color != oldDelegate.color;
  }
}
