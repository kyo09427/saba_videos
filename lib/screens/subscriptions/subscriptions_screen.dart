import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../models/video.dart';
import '../../services/cache_service.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/app_navigation_scaffold.dart';
import '../../widgets/skeleton_widgets.dart';
import '../../widgets/app_mobile_top_bar.dart';
import '../channel/channel_screen.dart';
import 'subscriptions_channel_list_screen.dart';

/// 登録チャンネル画面
/// 
/// 登録しているチャンネルの動画のみを表示します。
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _supabase = SupabaseService.instance.client;
  List<Video> _videos = [];
  List<Video> _filteredVideos = []; // フィルター後の動画リスト
  List<UserProfile> _subscribedChannels = [];
  String? _selectedChannelId; // nullの場合は「すべて」
  String _selectedCategoryFilter = 'すべて'; // カテゴリフィルター
  bool _isLoading = true;
  String? _errorMessage;

  // カテゴリフィルター用
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
  Color get _ytBackground => Theme.of(context).scaffoldBackgroundColor;
  Color get _ytSurface => Theme.of(context).colorScheme.surface;
  Color get _textWhite => Theme.of(context).colorScheme.onSurface;
  Color get _textGray => Theme.of(context).colorScheme.onSurfaceVariant;

  // ページネーション
  int _offset = 0;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSubscribedChannels();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMoreVideos();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 登録チャンネル一覧を読み込む
  Future<void> _loadSubscribedChannels({bool isRefresh = false}) async {
    if (!mounted) return;

    // リフレッシュ時はキャッシュとページネーション状態をリセット
    if (isRefresh) {
      CacheService.instance.invalidate(CacheKeys.subscriptionVideos);
      CacheService.instance.invalidate(CacheKeys.subscribedChannelIds);
      _offset = 0;
      _hasMore = true;
    }

    // ── キャッシュ読み込み（初回表示のみ）──
    if (!isRefresh) {
      final cachedChannels =
          CacheService.instance.get<List<UserProfile>>(CacheKeys.subscribedChannelIds);
      final cachedVideos =
          CacheService.instance.get<List<Video>>(CacheKeys.subscriptionVideos);
      if (cachedChannels != null && cachedVideos != null) {
        if (mounted) {
          setState(() {
            _subscribedChannels = cachedChannels;
            _videos = cachedVideos;
            _offset = cachedVideos.length;
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
      // 登録しているチャンネルのIDリストを取得
      final channelIds = await SupabaseService.instance.getSubscribedChannelIds();

      if (channelIds.isEmpty) {
        if (mounted) {
          setState(() {
            _subscribedChannels = [];
            _videos = [];
            _isLoading = false;
          });
        }
        return;
      }

      // プロフィール情報を取得
      final profilesResponse = await _supabase
          .from('profiles')
          .select('*')
          .inFilter('id', channelIds);

      final channels = (profilesResponse is List ? profilesResponse : <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((p) => UserProfile.fromJson(p))
          .toList();

      // キャッシュに保存（チャンネル一覧）
      CacheService.instance.set<List<UserProfile>>(
          CacheKeys.subscribedChannelIds, channels);

      if (mounted) {
        setState(() {
          _subscribedChannels = channels;
        });
      }

      // 動画を読み込む
      await _loadVideos();
    } catch (e) {
      debugPrint('❌ Error loading subscribed channels: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'チャンネル情報の読み込みに失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  /// 動画を読み込む
  Future<void> _loadVideos() async {
    try {
      final channelIds = _subscribedChannels.map((c) => c.id).toList();

      if (channelIds.isEmpty) {
        if (mounted) {
          setState(() {
            _videos = [];
            _isLoading = false;
          });
        }
        return;
      }

      // フィルター条件を設定
      List<String> targetChannelIds;
      if (_selectedChannelId != null) {
        targetChannelIds = [_selectedChannelId!];
      } else {
        targetChannelIds = channelIds;
      }

      // 登録チャンネルの動画を取得（最初の _pageSize 件のみ）
      final videosResponse = await _supabase
          .from('videos')
          .select('*')
          .inFilter('user_id', targetChannelIds)
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      final videosData = videosResponse is List<dynamic>
          ? videosResponse
          : <dynamic>[];
      
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

      // 動画データとプロフィール情報を結合
      final videos = videosData
          .whereType<Map<String, dynamic>>()
          .map((videoJson) {
            final userId = videoJson['user_id'] as String?;
            if (userId != null && profilesMap.containsKey(userId)) {
              videoJson['profiles'] = profilesMap[userId];
            }
            return Video.fromJsonWithProfile(videoJson);
          })
          .where((video) => video.id.isNotEmpty)
          .toList();

      // ページネーション状態を更新
      _offset = videos.length;
      _hasMore = videosData.length == _pageSize;

      // キャッシュに保存（動画一覧）
      CacheService.instance.set<List<Video>>(CacheKeys.subscriptionVideos, videos);

      if (mounted) {
        setState(() {
          _videos = videos;
          _applyFilter(); // フィルターを適用
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading subscribed videos: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '動画の読み込みに失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  /// チャンネルを選択
  void _selectChannel(String? channelId) {
    if (_selectedChannelId == channelId) return;

    _offset = 0;
    _hasMore = true;
    CacheService.instance.invalidate(CacheKeys.subscriptionVideos);

    setState(() {
      _selectedChannelId = channelId;
      _videos = [];
      _isLoading = true;
    });

    _loadVideos();
  }

  /// スクロール末端に達したら追加の動画を取得する
  Future<void> _loadMoreVideos() async {
    if (!mounted || _isLoadingMore || !_hasMore) return;

    final channelIds = _subscribedChannels.map((c) => c.id).toList();
    if (channelIds.isEmpty) return;

    final targetChannelIds = _selectedChannelId != null
        ? [_selectedChannelId!]
        : channelIds;

    setState(() => _isLoadingMore = true);

    try {
      final response = await _supabase
          .from('videos')
          .select('*')
          .inFilter('user_id', targetChannelIds)
          .order('created_at', ascending: false)
          .range(_offset, _offset + _pageSize - 1);

      final videosData = response is List<dynamic> ? response : <dynamic>[];
      if (videosData.isEmpty) {
        if (mounted) setState(() { _hasMore = false; _isLoadingMore = false; });
        return;
      }

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

      final newVideos = videosData
          .whereType<Map<String, dynamic>>()
          .map((videoJson) {
            final userId = videoJson['user_id'] as String?;
            if (userId != null && profilesMap.containsKey(userId)) {
              videoJson['profiles'] = profilesMap[userId];
            }
            return Video.fromJsonWithProfile(videoJson);
          })
          .where((video) => video.id.isNotEmpty)
          .toList();

      _offset += videosData.length;
      _hasMore = videosData.length == _pageSize;

      final allVideos = [..._videos, ...newVideos];
      CacheService.instance.set<List<Video>>(CacheKeys.subscriptionVideos, allVideos);

      if (mounted) {
        setState(() {
          _videos = allVideos;
          _applyFilter();
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading more subscription videos: $e');
      if (mounted) setState(() => _isLoadingMore = false);
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

  /// フィルターを適用
  void _applyFilter() {
    if (_selectedCategoryFilter == 'すべて') {
      _filteredVideos = List.from(_videos);
    } else if (_selectedCategoryFilter == '新しい動画') {
      // 最新の動画（1週間以内）
      final now = DateTime.now();
      _filteredVideos = _videos.where((video) {
        final diff = now.difference(video.createdAt);
        return diff.inDays <= 7;
      }).toList();
    } else {
      // カテゴリでフィルタリング
      _filteredVideos = _videos.where((video) {
        return video.mainCategory == _selectedCategoryFilter;
      }).toList();
    }
  }

  /// チャンネル選択サイドバー（タブレット版）
  Widget _buildChannelSidebar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = _textGray.withValues(alpha: 0.2);

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: _ytBackground,
        border: Border(
          right: BorderSide(color: dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── すべてのチャンネルボタン ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: InkWell(
              onTap: () => _selectChannel(null),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedChannelId == null
                      ? (isDark
                          ? const Color(0xFF272727)
                          : Colors.grey.shade200)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.video_library_outlined,
                      size: 20,
                      color: _selectedChannelId == null
                          ? _ytRed
                          : _textWhite,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'すべてのチャンネル',
                        style: TextStyle(
                          fontSize: 14,
                          color: _selectedChannelId == null
                              ? _ytRed
                              : _textWhite,
                          fontWeight: _selectedChannelId == null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Divider(height: 1, color: dividerColor,
              indent: 12, endIndent: 12),

          // ── チャンネルリスト ──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _subscribedChannels.length,
              itemBuilder: (context, index) {
                final channel = _subscribedChannels[index];
                final isSelected = _selectedChannelId == channel.id;

                return InkWell(
                  onTap: () => _selectChannel(channel.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: isSelected
                        ? (isDark
                            ? const Color(0xFF272727)
                            : Colors.grey.shade200)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        // チャンネルアイコン
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.purple,
                          backgroundImage: channel.avatarUrl != null
                              ? NetworkImage(channel.avatarUrl!)
                              : null,
                          child: channel.avatarUrl == null
                              ? Text(
                                  channel.initials,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 9),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        // チャンネル名
                        Expanded(
                          child: Text(
                            channel.username,
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  isSelected ? _ytRed : _textWhite,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// チャンネルアイコンリスト（スマホ版・横スクロール）
  Widget _buildChannelIconRow() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 92,
        child: Stack(
          children: [
            // ── 横スクロールリスト（右端60pxは「すべて」ボタンの裏になるので余白） ──
            Container(
              color: _ytBackground,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 60, 6),
                itemCount: _subscribedChannels.length,
                itemBuilder: (context, index) {
                  final channel = _subscribedChannels[index];
                  final isSelected = _selectedChannelId == channel.id;

                  return Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: GestureDetector(
                      onTap: () => _selectChannel(channel.id),
                      child: SizedBox(
                        width: 60,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: _ytRed, width: 2.5)
                                    : null,
                              ),
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.purple,
                                backgroundImage: channel.avatarUrl != null
                                    ? NetworkImage(channel.avatarUrl!)
                                    : null,
                                child: channel.avatarUrl == null
                                    ? Text(
                                        channel.initials,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 14),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              channel.username,
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected ? _ytRed : _textWhite,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── 右端固定の「すべて」ボタン ──
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SubscriptionsChannelListScreen(
                        channels: _subscribedChannels,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 15, 0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _ytBackground.withValues(alpha: 0),
                        _ytBackground.withValues(alpha: 0.85),
                        _ytBackground,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'すべて',
                      style: TextStyle(
                        color: _selectedChannelId == null
                            ? _ytRed
                            : const Color(0xFF065FD4),
                        fontSize: 13,
                        fontWeight: _selectedChannelId == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// カテゴリフィルターチップを構築
  Widget _buildCategoryPills() {
    return SliverToBoxAdapter(
      child: Container(
        height: 48,
        color: _ytBackground.withValues(alpha: 0.95),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _filterCategories.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final category = _filterCategories[index];
            final isSelected = _selectedCategoryFilter == category;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategoryFilter = category;
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

  /// グリッドの列数を決定
  int _getGridColumnCount(double screenWidth, bool isWideScreen) {
    if (!isWideScreen) {
      return 1;
    }
    if (screenWidth > 1600) {
      return 4;
    } else if (screenWidth > 1200) {
      return 3;
    } else {
      return 2;
    }
  }

  /// セル幅からセルの高さ（px）を計算する。
  /// サムネイル(16:9) + 情報エリア固定高さ の合計を返す。
  double _calcCellHeight(double screenWidth, int columns) {
    const hPad = 16.0;    // SliverPadding horizontal: 8×2
    const spacing = 8.0;  // crossAxisSpacing
    const infoH = 96.0;  // 情報エリア固定高さ（padding+タイトル2行+チャンネル行）
    final cellW = (screenWidth - hPad - (columns - 1) * spacing) / columns;
    return cellW * 9 / 16 + infoH;
  }

  /// 動画カードをホーム画面と同じスタイルで構築
  Widget _buildVideoCard(Video video) {
    return InkWell(
      onTap: () => _handleVideoTap(video),
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
                            child: CircularProgressIndicator(color: _ytRed),
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
              // 時間表示バッジ（durationが設定されている場合のみ表示）
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
          // 動画詳細情報（グリッド用に簡略化）
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タイトル
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                // チャンネル情報
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChannelScreen(channelId: video.userId),
                          ),
                        );
                      },
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.purple,
                        backgroundImage: video.userProfile?.avatarUrl != null
                            ? NetworkImage(video.userProfile!.avatarUrl!)
                            : null,
                        child: video.userProfile?.avatarUrl == null
                            ? Text(
                                video.userProfile?.initials ?? '?',
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.userProfile?.username ?? "不明",
                            style: TextStyle(color: _textGray, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            video.relativeTime,
                            style: TextStyle(color: _textGray, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationScaffold(
      currentIndex: 3,
      backgroundColor: _ytBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // サイドバー分を除いた実際の利用可能幅で列数・比率を計算
          final screenWidth = constraints.maxWidth;
          final isWideScreen = screenWidth > 600;
          // PC ナビゲーションサイドバーの表示判定（AppNavigationScaffold と同じ閾値）
          final actualScreenWidth = MediaQuery.of(context).size.width;
          final isPcSidebar = actualScreenWidth >= 1100;

          // 動画スライバーリスト（モバイル・タブレット共通）
          List<Widget> videoSlivers(double contentWidth) => [
            if (_subscribedChannels.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.subscriptions_outlined,
                          size: 80, color: _ytSurface),
                      const SizedBox(height: 16),
                      Text('登録チャンネルがありません',
                          style: TextStyle(color: _textGray)),
                      const SizedBox(height: 8),
                      Text(
                        'チャンネルを登録すると、ここに動画が表示されます',
                        style: TextStyle(color: _textGray, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else if (_filteredVideos.isEmpty)
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
                    ],
                  ),
                ),
              )
            else if (_getGridColumnCount(contentWidth, isWideScreen) == 1)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildVideoCard(_filteredVideos[index]),
                  childCount: _filteredVideos.length,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        _getGridColumnCount(contentWidth, isWideScreen),
                    mainAxisExtent: _calcCellHeight(contentWidth,
                        _getGridColumnCount(contentWidth, isWideScreen)),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildVideoCard(_filteredVideos[index]),
                    childCount: _filteredVideos.length,
                  ),
                ),
              ),
            if (_isLoadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(color: _ytRed),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ];

          return SafeArea(
            bottom: false,
            child: _isLoading
                ? _buildSkeletonView()
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, color: _ytRed, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                style: TextStyle(color: _textWhite),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _loadSubscribedChannels(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _ytSurface,
                                  foregroundColor: _textWhite,
                                ),
                                child: const Text('再読み込み'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : isPcSidebar
                        // ── PC：ロゴのみ表示（アイコンなし）＋カテゴリ＋動画 ──
                        ? RefreshIndicator(
                            onRefresh: () => _loadSubscribedChannels(
                                isRefresh: true),
                            color: _ytRed,
                            backgroundColor: _ytSurface,
                            child: CustomScrollView(
                              controller: _scrollController,
                              slivers: [
                                SliverAppBar(
                                  floating: true,
                                  backgroundColor:
                                      _ytBackground.withValues(alpha: 0.95),
                                  elevation: 0,
                                  titleSpacing: 0,
                                  leadingWidth: 0,
                                  leading: const SizedBox.shrink(),
                                  automaticallyImplyLeading: false,
                                  // PC はロゴ非表示・アイコン表示
                                  title: const SizedBox.shrink(),
                                  actions: AppMobileTopBar.buildActions(context),
                                ),
                                if (_subscribedChannels.isNotEmpty)
                                  _buildCategoryPills(),
                                ...videoSlivers(screenWidth),
                              ],
                            ),
                          )
                        : isWideScreen
                        // ── タブレット：チャンネルサイドバー + コンテンツ ──
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_subscribedChannels.isNotEmpty)
                                _buildChannelSidebar(),
                              Expanded(
                                child: RefreshIndicator(
                                  onRefresh: () => _loadSubscribedChannels(
                                      isRefresh: true),
                                  color: _ytRed,
                                  backgroundColor: _ytSurface,
                                  child: CustomScrollView(
                                    controller: _scrollController,
                                    slivers: [
                                      // 共通上部バー
                                      SliverAppBar(
                                        floating: true,
                                        backgroundColor: _ytBackground
                                            .withValues(alpha: 0.95),
                                        elevation: 0,
                                        titleSpacing: 0,
                                        leadingWidth: 0,
                                        leading: const SizedBox.shrink(),
                                        automaticallyImplyLeading: false,
                                        title: AppMobileTopBar.buildTitle(
                                            context),
                                        actions: AppMobileTopBar.buildActions(
                                            context),
                                      ),
                                      if (_subscribedChannels.isNotEmpty)
                                        _buildCategoryPills(),
                                      ...videoSlivers(
                                          screenWidth -
                                              (_subscribedChannels.isNotEmpty
                                                  ? 240
                                                  : 0)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        // ── モバイル：上部アイコン横スクロール ──
                        : RefreshIndicator(
                            onRefresh: () => _loadSubscribedChannels(
                                isRefresh: true),
                            color: _ytRed,
                            backgroundColor: _ytSurface,
                            child: CustomScrollView(
                              controller: _scrollController,
                              slivers: [
                                // 共通上部バー（モバイル）
                                SliverAppBar(
                                  floating: true,
                                  backgroundColor:
                                      _ytBackground.withValues(alpha: 0.95),
                                  elevation: 0,
                                  titleSpacing: 0,
                                  leadingWidth: 0,
                                  leading: const SizedBox.shrink(),
                                  automaticallyImplyLeading: false,
                                  title: AppMobileTopBar.buildTitle(context),
                                  actions: AppMobileTopBar.buildActions(context),
                                ),
                                // チャンネルアイコンリスト（モバイルのみ）
                                if (_subscribedChannels.isNotEmpty)
                                  _buildChannelIconRow(),
                                // カテゴリフィルターチップ
                                if (_subscribedChannels.isNotEmpty)
                                  _buildCategoryPills(),
                                ...videoSlivers(screenWidth),
                              ],
                            ),
                          ),
          );
        },
      ),
    );
  }

  /// スケルトンビュー（初回ロード中に表示）
  Widget _buildSkeletonView() {
    final isPC = MediaQuery.of(context).size.width >= 1100;
    return Container(
      color: _ytBackground,
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: _ytBackground.withValues(alpha: 0.95),
            elevation: 0,
            titleSpacing: 0,
            leadingWidth: 0,
            leading: const SizedBox.shrink(),
            automaticallyImplyLeading: false,
            // PC はロゴ非表示・アイコン表示
            title: isPC
                ? const SizedBox.shrink()
                : AppMobileTopBar.buildTitle(context),
            actions: AppMobileTopBar.buildActions(context),
          ),
          const SkeletonSliverList(
            itemBuilder: SkeletonVideoCardSmall.new,
            itemCount: 4,
          ),
        ],
      ),
    );
  }

}
