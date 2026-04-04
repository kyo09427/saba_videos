import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/playlist.dart';
import '../../models/video.dart';
import '../../services/cache_service.dart';
import '../../services/playlist_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/skeleton_widgets.dart';

/// プレイリスト詳細画面
///
/// プレイリスト内の動画一覧をリスト表示します。
class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistWithMeta playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<Video> _videos = [];
  bool _isLoading = true;
  String? _errorMessage;

  String get _cacheKey => 'playlist_videos_${widget.playlist.id}';

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos({bool isRefresh = false}) async {
    if (!mounted) return;

    // キャッシュ読み込み（初回表示時のみ）
    if (!isRefresh) {
      final cached = CacheService.instance.get<List<Video>>(_cacheKey);
      if (cached != null) {
        if (mounted) {
          setState(() {
            _videos = cached;
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
      final videos =
          await PlaylistService.instance.getPlaylistVideos(widget.playlist.id);

      // キャッシュに保存（3分）
      CacheService.instance.set<List<Video>>(
        _cacheKey,
        videos,
        ttl: const Duration(minutes: 3),
      );

      if (mounted) {
        setState(() {
          _videos = videos;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading playlist videos: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '動画の読み込みに失敗しました';
          _isLoading = false;
        });
      }
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

  Widget _buildVideoCard(Video video) {
    final colorScheme = Theme.of(context).colorScheme;
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: video.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: video.thumbnailUrl!,
                        width: 160,
                        height: 90,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 160,
                          height: 90,
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 160,
                          height: 90,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.play_circle_outline,
                              color: colorScheme.onSurfaceVariant, size: 36),
                        ),
                      )
                    : Container(
                        width: 160,
                        height: 90,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.video_library_outlined,
                            color: colorScheme.onSurfaceVariant, size: 36),
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
                      color: colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (video.userProfile != null)
                    Text(
                      video.userProfile!.username,
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    video.relativeTime,
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonView() {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SkeletonSliverList(
          itemBuilder: SkeletonVideoCardSmall.new,
          itemCount: 5,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? _buildSkeletonView()
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            color: colorScheme.error, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _loadVideos(isRefresh: true),
                          child: const Text('再読み込み'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadVideos(isRefresh: true),
                    color: colorScheme.primary,
                    child: CustomScrollView(
                      slivers: [
                        // ヘッダー
                        SliverAppBar(
                          floating: true,
                          backgroundColor:
                              Theme.of(context).scaffoldBackgroundColor,
                          elevation: 0,
                          leading: IconButton(
                            icon: Icon(Icons.arrow_back,
                                color: colorScheme.onSurface),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.playlist.name,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.playlist.videoCountLabel,
                                style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),

                        // 動画一覧
                        if (_videos.isEmpty)
                          SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.playlist_play_outlined,
                                      size: 80,
                                      color: colorScheme.surfaceContainerHighest),
                                  const SizedBox(height: 16),
                                  Text('動画がありません',
                                      style: TextStyle(
                                          color: colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  _buildVideoCard(_videos[index]),
                              childCount: _videos.length,
                            ),
                          ),

                        const SliverToBoxAdapter(
                            child: SizedBox(height: 80)),
                      ],
                    ),
                  ),
      ),
    );
  }
}
