import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/video.dart';
import '../../services/cache_service.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/app_mobile_top_bar.dart';
import '../../widgets/app_navigation_scaffold.dart';
import '../../widgets/skeleton_widgets.dart';
import '../channel/channel_screen.dart';

/// タイムライン画面
///
/// 年月ごとにグルーピングして、過去に遡れる動画アーカイブを表示します。
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _supabase = SupabaseService.instance.client;
  final ScrollController _scrollController = ScrollController();

  /// 年月キー → 動画リスト のマップ（降順ソート済み）
  Map<String, List<Video>> _groupedVideos = {};
  /// 表示順の年月キーリスト（新しい月が上）
  List<String> _sortedMonthKeys = [];
  bool _isLoading = true;
  String? _errorMessage;

  // サイドバー用: 展開している年
  String? _expandedYear;
  // 現在スクロールで見えているセクションキー
  String? _activeSectionKey;
  // スクロールスロットル用（直前の更新時刻）
  DateTime? _lastScrollUpdate;

  // デザイン用カラー（テーマ対応ゲッター）
  static const Color _ytRed = Color(0xFFF20D0D);
  Color get _ytBackground => Theme.of(context).scaffoldBackgroundColor;
  Color get _ytSurface => Theme.of(context).colorScheme.surface;
  Color get _textWhite => Theme.of(context).colorScheme.onSurface;
  Color get _textGray => Theme.of(context).colorScheme.onSurfaceVariant;

  /// セクションキー → GlobalKey（スクロールジャンプ用）
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// スクロール位置に応じてアクティブセクションを更新
  /// 100ms スロットルでフレームごとの重い RenderBox 計算を抑制する。
  void _onScroll() {
    final now = DateTime.now();
    if (_lastScrollUpdate != null &&
        now.difference(_lastScrollUpdate!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastScrollUpdate = now;

    for (final key in _sortedMonthKeys) {
      final globalKey = _sectionKeys[key];
      final ctx = globalKey?.currentContext;
      if (ctx == null) continue;

      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null) continue;

      final position = renderBox.localToGlobal(Offset.zero);
      if (position.dy >= 0 &&
          position.dy < MediaQuery.of(ctx).size.height * 0.5) {
        if (_activeSectionKey != key) {
          setState(() => _activeSectionKey = key);
        }
        break;
      }
    }
  }

  /// 動画を読み込んで年月別にグループ化
  Future<void> _loadVideos({bool isRefresh = false}) async {
    if (!mounted) return;

    // ── キャッシュ読み込み（初回表示のみ、リフレッシュ時はスキップ）──
    if (!isRefresh) {
      final cached = CacheService.instance
          .get<Map<String, List<Video>>>(CacheKeys.timelineVideos);
      if (cached != null) {
        final sortedKeys = cached.keys.toList()..sort((a, b) => b.compareTo(a));
        final firstYear =
            sortedKeys.isNotEmpty ? sortedKeys.first.split('-').first : null;
        for (final key in sortedKeys) {
          _sectionKeys.putIfAbsent(key, () => GlobalKey());
        }
        if (mounted) {
          setState(() {
            _groupedVideos = cached;
            _sortedMonthKeys = sortedKeys;
            _expandedYear = firstYear;
            _activeSectionKey =
                sortedKeys.isNotEmpty ? sortedKeys.first : null;
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
      // 動画を古い順で取得（タイムラインなので古い→新しい順）
      final response = await _supabase
          .from('videos')
          .select('*')
          .order('created_at', ascending: false);

      final videosData = response is List<dynamic> ? response : <dynamic>[];

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

      // 動画オブジェクトを生成
      final videos = videosData
          .whereType<Map<String, dynamic>>()
          .map((videoJson) {
            final userId = videoJson['user_id'] as String?;
            if (userId != null && profilesMap.containsKey(userId)) {
              videoJson['profiles'] = profilesMap[userId];
            }
            videoJson['tags'] = [];
            return Video.fromJsonWithProfile(videoJson);
          })
          .where((v) => v.id.isNotEmpty)
          .toList();

      // 年月でグループ化
      final grouped = <String, List<Video>>{};
      for (final video in videos) {
        final jst = video.createdAt.toLocal();
        final key = '${jst.year}-${jst.month.toString().padLeft(2, '0')}';
        grouped.putIfAbsent(key, () => []).add(video);
      }

      // 年月キーを降順ソート（新しい月が上）
      final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

      // セクションキーを生成
      for (final key in sortedKeys) {
        _sectionKeys.putIfAbsent(key, () => GlobalKey());
      }

      // 最初のセクションをアクティブに
      final firstYear = sortedKeys.isNotEmpty
          ? sortedKeys.first.split('-').first
          : null;

      // キャッシュに保存
      CacheService.instance.set<Map<String, List<Video>>>(
          CacheKeys.timelineVideos, grouped);

      if (mounted) {
        setState(() {
          _groupedVideos = grouped;
          _sortedMonthKeys = sortedKeys;
          _expandedYear = firstYear;
          _activeSectionKey = sortedKeys.isNotEmpty ? sortedKeys.first : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading timeline videos: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '動画の読み込みに失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  /// 年月キーから日本語ラベルを生成
  String _monthLabel(String key) {
    final parts = key.split('-');
    final year = parts[0];
    final month = int.parse(parts[1]);
    const monthNames = ['', '1月', '2月', '3月', '4月', '5月', '6月',
        '7月', '8月', '9月', '10月', '11月', '12月'];
    return '${monthNames[month]}($year)';
  }

  String _shortMonthLabel(String key) {
    final parts = key.split('-');
    final month = int.parse(parts[1]);
    const monthNames = ['', '1月', '2月', '3月', '4月', '5月', '6月',
        '7月', '8月', '9月', '10月', '11月', '12月'];
    return monthNames[month];
  }

  String _yearFromKey(String key) => key.split('-').first;

  /// カテゴリに応じた色
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'ゲーム':    return const Color(0xFF9C27B0);
      case '音楽':     return const Color(0xFFE91E63);
      case 'ネタ':     return const Color(0xFFFF9800);
      case 'その他':   return const Color(0xFF607D8B);
      default:         return const Color(0xFF2196F3);
    }
  }

  /// 指定セクションまでスクロール
  void _scrollToSection(String key) {
    final globalKey = _sectionKeys[key];
    if (globalKey?.currentContext == null) return;
    Scrollable.ensureVisible(
      globalKey!.currentContext!,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
    setState(() => _activeSectionKey = key);
  }

  // ─── ウィジェット構築 ───────────────────────────────────────

  /// 左サイドバー（PC表示）
  Widget _buildSidebar() {
    // 年ごとにグループ化
    final yearGroups = <String, List<String>>{};
    for (final key in _sortedMonthKeys) {
      final year = _yearFromKey(key);
      yearGroups.putIfAbsent(year, () => []).add(key);
    }
    final years = yearGroups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Container(
      width: 160,
      color: _ytBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'タイムライン',
                  style: TextStyle(
                    color: _textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '動画の記録',
                  style: TextStyle(color: _textGray, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: years.length,
              itemBuilder: (context, i) {
                final year = years[i];
                final monthKeys = yearGroups[year]!;
                final isExpanded = _expandedYear == year;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 年ヘッダー
                    InkWell(
                      onTap: () {
                        setState(() {
                          _expandedYear = isExpanded ? null : year;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            // 縦ライン+ドット
                            Column(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isExpanded ? _ytRed : _textGray,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Text(
                              year,
                              style: TextStyle(
                                color: isExpanded ? _ytRed : _textGray,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: _textGray,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 月リスト
                    if (isExpanded)
                      ...monthKeys.map((key) {
                        final isActive = _activeSectionKey == key;
                        return InkWell(
                          onTap: () => _scrollToSection(key),
                          child: Container(
                            padding: const EdgeInsets.only(
                                left: 34, right: 16, top: 8, bottom: 8),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _ytSurface
                                  : Colors.transparent,
                              border: isActive
                                  ? Border(
                                      left: BorderSide(
                                          color: _ytRed, width: 2))
                                  : null,
                            ),
                            child: Text(
                              _shortMonthLabel(key),
                              style: TextStyle(
                                color:
                                    isActive ? _textWhite : _textGray,
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 4),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 月セクションのヘッダー
  Widget _buildMonthHeader(String key, int videoCount) {
    final parts = key.split('-');
    final year = parts[0];
    final month = int.parse(parts[1]);
    const monthNames = ['', '1月', '2月', '3月', '4月', '5月', '6月',
        '7月', '8月', '9月', '10月', '11月', '12月'];

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            monthNames[month],
            style: TextStyle(
              color: _textWhite,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              year,
              style: TextStyle(
                color: _textGray,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _ytSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$videoCount本',
              style: TextStyle(color: _textGray, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 動画カード（タイムライン用・横長レイアウト）
  Widget _buildTimelineVideoCard(Video video) {
    return InkWell(
      onTap: () async {
        if (video.url.isEmpty) return;
        await YouTubeService.launchVideo(video.url);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // サムネイル（横長）
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 140,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: video.thumbnailUrl != null &&
                          video.thumbnailUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: video.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, e) => Container(
                            color: _ytSurface,
                            child: Icon(Icons.play_circle_outline,
                                color: _textGray, size: 32),
                          ),
                        )
                      : Container(
                          color: _ytSurface,
                          child: Icon(Icons.video_library_outlined,
                              color: _textGray, size: 32),
                        ),
                ),
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
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // アバター + ユーザー名
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ChannelScreen(channelId: video.userId),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.purple,
                          backgroundImage:
                              video.userProfile?.avatarUrl != null
                                  ? NetworkImage(video.userProfile!.avatarUrl!)
                                  : null,
                          child: video.userProfile?.avatarUrl == null
                              ? Text(
                                  video.userProfile?.initials ?? '?',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 9),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            video.userProfile?.username ?? '不明',
                            style: TextStyle(
                                color: _textGray, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 日付 + カテゴリ
                  Row(
                    children: [
                      Text(
                        video.shortFormattedDate,
                        style: TextStyle(color: _textGray, fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(video.mainCategory),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          video.mainCategory,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// スマホ用月ドロップダウンヘッダー
  Widget _buildMobileMonthSelector() {
    return SliverToBoxAdapter(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: _sortedMonthKeys.map((key) {
            final isActive = _activeSectionKey == key;
            return GestureDetector(
              onTap: () => _scrollToSection(key),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? _ytRed : _ytSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _monthLabel(key),
                  style: TextStyle(
                    color: _textWhite,
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// スケルトンビュー（初回ロード中に表示）
  Widget _buildSkeletonView(double screenWidth) {
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
            title: screenWidth < 1100
                ? AppMobileTopBar.buildTitle(context)
                : const SizedBox.shrink(),
            actions: AppMobileTopBar.buildActions(context),
          ),
          // 月ヘッダースケルトン
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: SkeletonBox(width: 120, height: 28),
            ),
          ),
          // 動画カードスケルトン
          const SkeletonSliverList(
            itemBuilder: SkeletonVideoCardSmall.new,
            itemCount: 5,
          ),
        ],
      ),
    );
  }

  @override

  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 800;

    return AppNavigationScaffold(
      currentIndex: 1,
      backgroundColor: _ytBackground,
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // 左サイドバー（PCのみ）
            if (isWideScreen && _sortedMonthKeys.isNotEmpty)
              _buildSidebar(),

            // メインコンテンツ
            Expanded(
              child: _isLoading
                  ? _buildSkeletonView(screenWidth)
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline,
                                    color: _ytRed, size: 48),
                                const SizedBox(height: 16),
                                Text(_errorMessage!,
                                    style:
                                        TextStyle(color: _textWhite)),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadVideos,
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
                      : RefreshIndicator(
                          onRefresh: () => _loadVideos(isRefresh: true),
                          color: _ytRed,
                          backgroundColor: _ytSurface,
                          child: CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              // ─ アプリバー ─
                              SliverAppBar(
                                  floating: true,
                                  backgroundColor:
                                      _ytBackground.withValues(alpha: 0.95),
                                  elevation: 0,
                                  titleSpacing: 0,
                                  leadingWidth: 0,
                                  leading: const SizedBox.shrink(),
                                  automaticallyImplyLeading: false,
                                  // PC（サイドバーあり）はロゴ非表示
                                  title: screenWidth < 1100
                                      ? AppMobileTopBar.buildTitle(context)
                                      : const SizedBox.shrink(),
                                  actions: AppMobileTopBar.buildActions(context),
                              ),

                            // ─ 動画がない場合 ─
                            if (_sortedMonthKeys.isEmpty)
                              SliverFillRemaining(
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.history,
                                          size: 80, color: _ytSurface),
                                      const SizedBox(height: 16),
                                      Text('まだ動画がありません',
                                          style: TextStyle(
                                              color: _textGray)),
                                    ],
                                  ),
                                ),
                              )
                            else ...[
                              // スマホ用: 月選択チップ
                              if (!isWideScreen)
                                _buildMobileMonthSelector(),

                              // ─ 月別セクション ─
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) {
                                    final key = _sortedMonthKeys[i];
                                    final videos =
                                        _groupedVideos[key] ?? [];

                                    return Padding(
                                      key: _sectionKeys[key],
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // 月ヘッダー
                                          _buildMonthHeader(
                                              key, videos.length),
                                          const Divider(
                                            color: Color(0xFF3A3A3A),
                                            height: 1,
                                          ),
                                          const SizedBox(height: 8),
                                          // 動画一覧
                                          ...videos.map(
                                            (v) =>
                                                _buildTimelineVideoCard(v),
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                      ),
                                    );
                                  },
                                  childCount: _sortedMonthKeys.length,
                                ),
                              ),

                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 80)),
                            ],
                          ],
                        ),
                        ), // RefreshIndicator
            ),
          ],
        ),
      ),
    );
  }
}
