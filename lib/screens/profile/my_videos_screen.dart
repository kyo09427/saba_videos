import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/playlist.dart';
import '../../models/video.dart';
import '../../services/cache_service.dart';
import '../../services/playlist_service.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_service.dart';
import '../../widgets/skeleton_widgets.dart';

/// 自分の投稿動画一覧画面
///
/// 自分が投稿した動画の一覧を表示し、再生・編集・削除ができます。
class MyVideosScreen extends StatefulWidget {
  const MyVideosScreen({super.key});

  @override
  State<MyVideosScreen> createState() => _MyVideosScreenState();
}

class _MyVideosScreenState extends State<MyVideosScreen> {
  final _supabase = SupabaseService.instance.client;
  List<Video> _videos = [];
  bool _isLoading = true;
  String? _errorMessage;

  // デザイン用カラー（テーマ対応ゲッター）
  static const Color _ytRed = Color(0xFFF20D0D);
  Color get _ytBackground => Theme.of(context).scaffoldBackgroundColor;
  Color get _ytSurface => Theme.of(context).colorScheme.surface;
  Color get _textWhite => Theme.of(context).colorScheme.onSurface;
  Color get _textGray => Theme.of(context).colorScheme.onSurfaceVariant;

  @override
  void initState() {
    super.initState();
    _loadMyVideos();
  }

  /// 自分の投稿動画を取得
  Future<void> _loadMyVideos({bool isRefresh = false}) async {
    if (!mounted) return;

    // ── キャッシュ読み込み（初回表示のみ）──
    if (!isRefresh) {
      final cached = CacheService.instance.get<List<Video>>(CacheKeys.myVideos);
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
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'ログインしていません';
          _isLoading = false;
        });
        return;
      }

      final response = await _supabase
          .from('videos')
          .select('*')
          .eq('user_id', currentUser.id)
          .order('created_at', ascending: false);

      // タグ情報を取得（video_tagsテーブル経由）
      final videosData = response as List<dynamic>;
      final List<Video> videos = [];

      for (final videoJson in videosData) {
        final videoId = videoJson['id'] as String?;
        if (videoId == null || videoId.isEmpty) continue;

        // タグを取得
        try {
          final tagsResponse = await _supabase
              .from('video_tags')
              .select('tags(name)')
              .eq('video_id', videoId);

          final tagsList = (tagsResponse as List)
              .map((t) => t['tags']?['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty)
              .toList();

          final videoMap = Map<String, dynamic>.from(videoJson as Map);
          videoMap['tags'] = tagsList;
          videos.add(Video.fromJson(videoMap));
        } catch (_) {
          videos.add(Video.fromJson(videoJson as Map<String, dynamic>));
        }
      }

      // キャッシュに保存
      CacheService.instance.set<List<Video>>(CacheKeys.myVideos, videos);

      if (mounted) {
        setState(() {
          _videos = videos;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading my videos: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '動画の読み込みに失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  /// 動画をタップして再生
  Future<void> _handleVideoTap(Video video) async {
    if (video.url.isEmpty) {
      _showSnackBar('無効な動画URLです', isError: true);
      return;
    }
    final success = await YouTubeService.launchVideo(video.url);
    if (!success && mounted) {
      _showSnackBar('動画を開けませんでした', isError: true);
    }
  }

  /// 編集ダイアログを表示
  Future<void> _handleEdit(Video video) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditVideoSheet(video: video),
    );

    if (result == true) {
      // キャッシュを無効化して再読み込み
      CacheService.instance.invalidate(CacheKeys.myVideos);
      CacheService.instance.invalidate(CacheKeys.homeVideos);
      _showSnackBar('動画を更新しました');
      await _loadMyVideos(isRefresh: true);
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
            Text(
              '「${video.title}」を削除しますか？',
              style: TextStyle(color: _textWhite),
            ),
            const SizedBox(height: 8),
            Text(
              '削除すると元に戻せません。',
              style: TextStyle(color: _textGray, fontSize: 12),
            ),
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
      // video_tags を先に削除
      await _supabase.from('video_tags').delete().eq('video_id', video.id);

      // 動画を削除
      await _supabase.from('videos').delete().eq('id', video.id);

      // キャッシュを無効化
      CacheService.instance.invalidate(CacheKeys.myVideos);
      CacheService.instance.invalidate(CacheKeys.homeVideos);
      CacheService.instance.invalidate(CacheKeys.myPageTotalViews);

      _showSnackBar('動画を削除しました');
      await _loadMyVideos(isRefresh: true);
    } catch (e) {
      debugPrint('❌ Error deleting video: $e');
      _showSnackBar('削除に失敗しました', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 動画カードを構築（チャンネル画面と同じ横並びスタイル）
  Widget _buildVideoCard(Video video) {
    return Dismissible(
      key: Key(video.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red[800],
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text('削除', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await _handleDelete(video);
        return false;
      },
      child: InkWell(
        onTap: () => _handleVideoTap(video),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // サムネイル（小さく左寄せ）
              SizedBox(
                width: 160,
                height: 90,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          video.thumbnailUrl != null &&
                              video.thumbnailUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: video.thumbnailUrl!,
                              width: 160,
                              height: 90,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: 160,
                                height: 90,
                                color: _ytSurface,
                              ),
                              errorWidget: (context, url, error) =>
                                  Container(
                                    width: 160,
                                    height: 90,
                                    color: _ytSurface,
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: _textGray,
                                      size: 36,
                                    ),
                                  ),
                            )
                          : Container(
                              width: 160,
                              height: 90,
                              color: _ytSurface,
                              child: Icon(
                                Icons.video_library_outlined,
                                color: _textGray,
                                size: 36,
                              ),
                            ),
                    ),
                    // 再生ボタン（中央）
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // テキスト情報（右側）
              Expanded(
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
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // カテゴリ + 投稿日時
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _ytSurface,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            video.mainCategory,
                            style: TextStyle(color: _textGray, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            video.relativeTime,
                            style: TextStyle(color: _textGray, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // タグ（最大3個）
                    if (video.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: video.tags
                            .take(3)
                            .map(
                              (tag) => Text(
                                '#$tag',
                                style: TextStyle(
                                  color: Colors.blue[300],
                                  fontSize: 10,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // 編集・削除メニュー
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: _textGray, size: 18),
                color: _ytSurface,
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'edit') {
                    _handleEdit(video);
                  } else if (value == 'delete') {
                    _handleDelete(video);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: _textWhite, size: 18),
                        const SizedBox(width: 8),
                        Text('編集', style: TextStyle(color: _textWhite)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: _ytRed, size: 18),
                        const SizedBox(width: 8),
                        Text('削除', style: TextStyle(color: _ytRed)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// スケルトンビュー（初回ロード中に表示）
  Widget _buildSkeletonView() {
    return Container(
      color: _ytBackground,
      child: const SkeletonListView(
        itemBuilder: SkeletonVideoCardSmall.new,
        itemCount: 5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ytBackground,
      appBar: AppBar(
        backgroundColor: _ytBackground,
        foregroundColor: _textWhite,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '投稿した動画',
              style: TextStyle(color: _textWhite, fontWeight: FontWeight.bold),
            ),
            if (!_isLoading)
              Text(
                '${_videos.length}件',
                style: TextStyle(color: _textGray, fontSize: 12),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? _buildSkeletonView()
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
                      onPressed: _loadMyVideos,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _ytSurface,
                      ),
                      child: Text('再読み込み', style: TextStyle(color: _textWhite)),
                    ),
                  ],
                ),
              ),
            )
          : _videos.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    size: 80,
                    color: _ytSurface,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '投稿した動画はありません',
                    style: TextStyle(color: _textGray, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '動画を投稿すると、ここに表示されます',
                    style: TextStyle(color: _textGray, fontSize: 12),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadMyVideos,
              color: _ytRed,
              backgroundColor: _ytSurface,
              child: ListView.builder(
                itemCount: _videos.length,
                itemBuilder: (context, index) =>
                    _buildVideoCard(_videos[index]),
              ),
            ),
    );
  }
}

/// 動画編集用のボトムシート
class EditVideoSheet extends StatefulWidget {
  final Video video;

  const EditVideoSheet({
    required this.video,
  });

  @override
  State<EditVideoSheet> createState() => _EditVideoSheetState();
}

class _EditVideoSheetState extends State<EditVideoSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _durationController;
  late final TextEditingController _tagInputController;
  final _supabase = SupabaseService.instance.client;

  late String _selectedCategory;
  late List<String> _tags;
  bool _isLoading = false;

  // プレイリスト関連
  List<Playlist> _myPlaylists = [];
  final Set<String> _selectedPlaylistIds = {};
  bool _isLoadingPlaylists = false;

  final List<String> _categories = ['雑談', 'ゲーム', '音楽', 'ネタ', 'その他'];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video.title);
    _durationController = TextEditingController(text: widget.video.duration ?? '');
    _tagInputController = TextEditingController();
    _selectedCategory = widget.video.mainCategory;
    _tags = List.from(widget.video.tags);
    _loadPlaylists();
  }

  /// プレイリスト一覧と現在の関連付けを読み込む
  Future<void> _loadPlaylists() async {
    setState(() => _isLoadingPlaylists = true);
    try {
      final results = await Future.wait([
        PlaylistService.instance.getMyPlaylists(),
        PlaylistService.instance.getVideoPlaylistIds(widget.video.id),
      ]);
      if (mounted) {
        setState(() {
          _myPlaylists = results[0] as List<Playlist>;
          _selectedPlaylistIds.addAll((results[1] as List<String>));
          _isLoadingPlaylists = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPlaylists = false);
    }
  }

  /// 新しいプレイリストを作成するダイアログ
  Future<void> _showCreatePlaylistDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('新しいプレイリスト'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            maxLength: 50,
            decoration: InputDecoration(
              labelText: 'プレイリスト名',
              border: const OutlineInputBorder(),
              counterStyle:
                  TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) Navigator.of(ctx).pop(name);
              },
              child: const Text('作成'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    if (result == null || !mounted) return;

    try {
      final newPlaylist = await PlaylistService.instance.createPlaylist(result);
      if (mounted) {
        setState(() {
          _myPlaylists.insert(0, newPlaylist);
          _selectedPlaylistIds.add(newPlaylist.id);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('プレイリスト作成に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _durationController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    final trimmedTag = tag.trim();
    if (trimmedTag.isEmpty) return;
    if (_tags.contains(trimmedTag)) return;
    setState(() {
      _tags.add(trimmedTag);
      _tagInputController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // videosテーブルを更新
      final durationText = _durationController.text.trim();
      await _supabase
          .from('videos')
          .update({
            'title': _titleController.text.trim(),
            'main_category': _selectedCategory,
            'duration': durationText.isEmpty ? null : durationText,
          })
          .eq('id', widget.video.id);

      // タグを全削除してから再挿入
      await _supabase
          .from('video_tags')
          .delete()
          .eq('video_id', widget.video.id);

      if (_tags.isNotEmpty) {
        for (final tagName in _tags) {
          // タグが存在するか確認
          final existingTag = await _supabase
              .from('tags')
              .select('id')
              .eq('name', tagName)
              .maybeSingle();

          String tagId;
          if (existingTag != null) {
            tagId = existingTag['id'] as String;
          } else {
            final newTag = await _supabase
                .from('tags')
                .insert({'name': tagName})
                .select('id')
                .single();
            tagId = newTag['id'] as String;
          }

          await _supabase.from('video_tags').insert({
            'video_id': widget.video.id,
            'tag_id': tagId,
          });
        }
      }

      // プレイリストの関連付けを更新
      await PlaylistService.instance.setVideoPlaylists(
        widget.video.id,
        _selectedPlaylistIds.toList(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('❌ Error updating video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新に失敗しました: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// プレイリスト選択セクション
  Widget _buildPlaylistSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ラベル
        Row(
          children: [
            Icon(Icons.playlist_add, color: colorScheme.onSurfaceVariant, size: 17),
            const SizedBox(width: 6),
            Text(
              'プレイリスト',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ローディング中
        if (_isLoadingPlaylists)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
          )
        // プレイリストなし
        else if (_myPlaylists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'まだプレイリストがありません',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          )
        // チップ一覧
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _myPlaylists.map((pl) {
              final selected = _selectedPlaylistIds.contains(pl.id);
              return FilterChip(
                label: Text(pl.name, style: const TextStyle(fontSize: 12)),
                selected: selected,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedPlaylistIds.add(pl.id);
                    } else {
                      _selectedPlaylistIds.remove(pl.id);
                    }
                  });
                },
              );
            }).toList(),
          ),

        const SizedBox(height: 10),

        // 新規作成ボタン
        OutlinedButton.icon(
          onPressed: _showCreatePlaylistDialog,
          icon: Icon(Icons.add_circle_outline, size: 15, color: colorScheme.primary),
          label: Text(
            '新しいプレイリスト',
            style: TextStyle(color: colorScheme.primary, fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // フォームフィールド共通デコレーション
    InputDecoration fieldDeco({
      required String label,
      required IconData icon,
      String? helper,
      Widget? suffix,
    }) {
      return InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        helperText: helper,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── ハンドルバー ──
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── ヘッダー（サムネイル + タイトルラベル） ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // サムネイル（小さく）
                  if (widget.video.thumbnailUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: widget.video.thumbnailUrl!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => Container(
                          width: 120,
                          height: 68,
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (ctx, url, err) => Container(
                          width: 120,
                          height: 68,
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.video_library,
                            color: colorScheme.onSurfaceVariant,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  // 「動画を編集」ラベル
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit, color: colorScheme.onSurface, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              '動画を編集',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // ── フォーム部分（スクロール可能） ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // タイトル入力
                      TextFormField(
                        controller: _titleController,
                        decoration: fieldDeco(label: 'タイトル', icon: Icons.title),
                        maxLength: 100,
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                            Text(
                              '$currentLength / ${maxLength ?? 100}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'タイトルを入力してください';
                          }
                          if (value.trim().length < 3) {
                            return 'タイトルは3文字以上で入力してください';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // カテゴリ選択
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,
                        decoration: fieldDeco(
                          label: 'カテゴリ',
                          icon: Icons.category_outlined,
                        ),
                        items: _categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedCategory = value);
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      // 再生時間入力（任意）
                      TextFormField(
                        controller: _durationController,
                        decoration: fieldDeco(
                          label: '再生時間（任意）',
                          icon: Icons.timer_outlined,
                          helper: '例: "12:45" または "1:23:45"',
                        ),
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // タグ入力
                      TextFormField(
                        controller: _tagInputController,
                        decoration: fieldDeco(
                          label: 'タグを追加',
                          icon: Icons.tag,
                          helper: 'Enterまたは＋で追加',
                          suffix: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => _addTag(_tagInputController.text),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: _addTag,
                      ),

                      // タグチップ
                      if (_tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _tags
                              .map(
                                (tag) => Chip(
                                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onDeleted: () => _removeTag(tag),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                              )
                              .toList(),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // プレイリスト選択
                      _buildPlaylistSection(),

                      const SizedBox(height: 24),

                      // 保存ボタン
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSave,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Text(
                                  '保存する',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // キャンセルボタン
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: TextButton(
                          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('キャンセル'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
