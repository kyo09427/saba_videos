import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/playlist.dart';
import '../../models/video.dart';
import '../../services/playlist_service.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_service.dart';

/// 動画投稿画面
class PostVideoScreen extends StatefulWidget {
  const PostVideoScreen({super.key});

  @override
  State<PostVideoScreen> createState() => _PostVideoScreenState();
}

class _PostVideoScreenState extends State<PostVideoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _tagInputController = TextEditingController();
  final _durationController = TextEditingController();
  bool _isLoading = false;
  bool _isFetchingInfo = false;
  String? _errorMessage;
  String? _previewThumbnail;

  String? _fetchedYoutubeTitle; // oEmbedで取得した元タイトル
  bool _durationAutoFetched = false; // 再生時間が自動取得済みか

  // カテゴリとタグの状態
  String _selectedCategory = '雑談';
  final List<String> _categories = ['雑談', 'ゲーム', '音楽', 'ネタ', 'その他'];
  final List<String> _tags = [];

  // プレイリスト関連の状態
  List<Playlist> _myPlaylists = [];
  final Set<String> _selectedPlaylistIds = {};
  bool _isLoadingPlaylists = false;

  @override
  void initState() {
    super.initState();
    _loadMyPlaylists();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _tagInputController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  /// 自分のプレイリスト一覧をロード
  Future<void> _loadMyPlaylists() async {
    setState(() => _isLoadingPlaylists = true);
    try {
      final playlists = await PlaylistService.instance.getMyPlaylists();
      if (mounted) {
        setState(() {
          _myPlaylists = playlists;
          _isLoadingPlaylists = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPlaylists = false);
    }
  }

  /// タグを追加
  void _addTag(String tag) {
    final trimmedTag = tag.trim();
    if (trimmedTag.isEmpty) return;
    if (_tags.contains(trimmedTag)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('このタグは既に追加されています'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() {
      _tags.add(trimmedTag);
      _tagInputController.clear();
    });
  }

  /// タグを削除
  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  /// URLからサムネイルをプレビューし、oEmbed APIでタイトル＋ページHTMLで再生時間を自動取得
  Future<void> _updatePreview(String url) async {
    final videoId = YouTubeService.extractVideoId(url);
    setState(() {
      _previewThumbnail = videoId != null
          ? YouTubeService.getThumbnailUrl(videoId)
          : null;
    });

    // 有効なYouTube URLの場合はタイトルと再生時間を並行取得
    if (videoId != null && YouTubeService.isValidYouTubeUrl(url)) {
      setState(() => _isFetchingInfo = true);
      try {
        // タイトル（oEmbed）と再生時間（HTMLスクレイプ）を並行取得
        final results = await Future.wait([
          YouTubeService.fetchVideoInfo(url),
          YouTubeService.fetchVideoDuration(url),
        ]);

        final info = results[0] as YouTubeVideoInfo?;
        final duration = results[1] as String?;

        if (mounted) {
          setState(() {
            if (info != null) {
              _fetchedYoutubeTitle = info.title;
              // タイトルが未入力の場合のみ自動補完（手動入力を上書きしない）
              if (_titleController.text.trim().isEmpty && info.title.isNotEmpty) {
                _titleController.text = info.title;
              }
            }
            // 再生時間が取得できた場合のみ自動補完（手動入力を上書きしない）
            if (duration != null && _durationController.text.trim().isEmpty) {
              _durationController.text = duration;
              _durationAutoFetched = true;
            }
          });
        }
      } finally {
        if (mounted) setState(() => _isFetchingInfo = false);
      }
    } else {
      setState(() {
        _fetchedYoutubeTitle = null;
        _durationAutoFetched = false;
      });
    }
  }

  /// 新しいプレイリストを作成するダイアログ
  Future<void> _showCreatePlaylistDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新しいプレイリスト'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'プレイリスト名',
            border: OutlineInputBorder(),
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
      ),
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

  Future<void> _handlePost() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) {
        throw Exception('ログインしていません');
      }

      // URLを正規化
      final normalizedUrl = YouTubeService.normalizeUrl(_urlController.text.trim());
      if (normalizedUrl == null) {
        throw Exception('無効なYouTube URLです');
      }

      final video = Video(
        id: '',
        createdAt: DateTime.now(),
        title: _titleController.text.trim(),
        url: normalizedUrl,
        userId: currentUser.id,
        mainCategory: _selectedCategory,
        tags: _tags,
        duration: _durationController.text.trim().isEmpty
            ? null
            : _durationController.text.trim(),
        youtubeTitle: _fetchedYoutubeTitle,
      );

      // 動画を挿入して、挿入されたデータを取得
      final insertedData = await SupabaseService.instance.client
          .from('videos')
          .insert(video.toJson())
          .select()
          .single();

      final videoId = insertedData['id'] as String;

      // タグの処理
      if (_tags.isNotEmpty) {
        for (final tagName in _tags) {
          // タグが存在するか確認
          final existingTag = await SupabaseService.instance.client
              .from('tags')
              .select('id')
              .eq('name', tagName)
              .maybeSingle();

          String tagId;
          if (existingTag != null) {
            tagId = existingTag['id'] as String;
          } else {
            // 新しいタグを作成
            final newTag = await SupabaseService.instance.client
                .from('tags')
                .insert({'name': tagName})
                .select('id')
                .single();
            tagId = newTag['id'] as String;
          }

          // video_tagsテーブルに関連付けを追加
          await SupabaseService.instance.client
              .from('video_tags')
              .insert({
            'video_id': videoId,
            'tag_id': tagId,
          });
        }
      }

      // プレイリストの関連付け
      if (_selectedPlaylistIds.isNotEmpty) {
        await PlaylistService.instance.setVideoPlaylists(
          videoId,
          _selectedPlaylistIds.toList(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('動画を投稿しました！'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        // trueを返して、ホーム画面でリフレッシュを促す
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } catch (e) {
      setState(() {
        _errorMessage = '投稿に失敗しました。もう一度お試しください。\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// プレイリスト選択セクションを構築
  Widget _buildPlaylistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'プレイリスト',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          '動画を追加するプレイリストを選択（任意・複数可）',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (_isLoadingPlaylists)
          const SizedBox(
            height: 36,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          // 既存プレイリストのチップ
          if (_myPlaylists.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _myPlaylists.map((pl) {
                final selected = _selectedPlaylistIds.contains(pl.id);
                return FilterChip(
                  label: Text(pl.name),
                  selected: selected,
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
          const SizedBox(height: 8),
          // 新しいプレイリスト作成ボタン
          OutlinedButton.icon(
            onPressed: _showCreatePlaylistDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新しいプレイリスト'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue,
              side: const BorderSide(color: Colors.blue),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('動画を投稿'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 説明
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'YouTube動画を投稿',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'YouTubeの動画URLを入力してください。\n一覧にサムネイルとタイトルが表示されます。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // YouTube URL入力
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'YouTube URL',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                  helperText: '例: https://www.youtube.com/watch?v=...',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                onChanged: _updatePreview,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'URLを入力してください';
                  }
                  if (!YouTubeService.isValidYouTubeUrl(value)) {
                    return '有効なYouTube URLを入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // サムネイルプレビュー
              if (_previewThumbnail != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'プレビュー',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (_isFetchingInfo) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '情報取得中...',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ] else if (_fetchedYoutubeTitle != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _durationAutoFetched
                                ? 'タイトル・再生時間 自動取得済み'
                                : 'タイトル自動取得済み',
                            style: const TextStyle(fontSize: 12, color: Colors.green),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          _previewThumbnail!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[300],
                              child: const Icon(
                                Icons.error,
                                color: Colors.red,
                                size: 48,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              // タイトル入力
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '動画タイトル',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                  helperText: '動画の説明やメモを入力（URL入力時に自動補完）',
                ),
                maxLength: 100,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (_formKey.currentState!.validate()) {
                    _handlePost();
                  }
                },
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
              const SizedBox(height: 16),

              // 再生時間入力（任意）
              TextFormField(
                controller: _durationController,
                decoration: InputDecoration(
                  labelText: '再生時間（任意）',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.timer_outlined),
                  helperText: _durationAutoFetched
                      ? 'URLから自動取得しました（修正可能）'
                      : kIsWeb
                          ? 'Web版では自動取得できません。手動で入力してください。例: "12:45"'
                          : 'URL入力で自動取得。例: "12:45" または "1:23:45"',
                  helperStyle: _durationAutoFetched
                      ? const TextStyle(color: Colors.green)
                      : null,
                  suffixIcon: _durationAutoFetched
                      ? const Icon(Icons.auto_awesome, color: Colors.green, size: 18)
                      : null,
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null; // 任意
                  // MM:SS または H:MM:SS 形式のバリデーション
                  final trimmed = value.trim();
                  final valid = RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(trimmed);
                  if (!valid) {
                    return '形式が正しくありません。例: "12:45" または "1:23:45"';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // メインカテゴリ選択
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'メインカテゴリ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                  helperText: 'カテゴリを選択（必須）',
                ),
                items: _categories.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 24),

              // サブカテゴリタグ入力
              TextFormField(
                controller: _tagInputController,
                decoration: InputDecoration(
                  labelText: 'タグ',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.tag),
                  helperText: '複数入力可能（Enterで追加）',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      _addTag(_tagInputController.text);
                    },
                  ),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: _addTag,
              ),
              const SizedBox(height: 8),

              // タグのチップ表示
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((tag) {
                    return Chip(
                      label: Text(tag),
                      onDeleted: () => _removeTag(tag),
                      deleteIcon: const Icon(Icons.close, size: 18),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 24),

              // プレイリスト選択セクション
              _buildPlaylistSection(),
              const SizedBox(height: 24),

              // エラーメッセージ
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[900]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[900]),
                        ),
                      ),
                    ],
                  ),
                ),

              // 投稿ボタン
              ElevatedButton(
                onPressed: _isLoading ? null : _handlePost,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send),
                          SizedBox(width: 8),
                          Text('投稿する', style: TextStyle(fontSize: 16)),
                        ],
                      ),
              ),
              const SizedBox(height: 16),

              // キャンセルボタン
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('キャンセル'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}