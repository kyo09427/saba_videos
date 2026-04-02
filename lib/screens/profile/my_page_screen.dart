import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_profile.dart';
import '../../services/app_update_service.dart';
import '../../services/cache_service.dart';
import '../../services/notification_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/app_bottom_navigation_bar.dart';
import '../../widgets/update_dialog.dart';
import '../auth/login_screen.dart';
import 'edit_profile_screen.dart';
import 'my_videos_screen.dart';

/// マイページ画面
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final _supabase = SupabaseService.instance.client;
  final _profileService = ProfileService.instance;
  
  // ユーザー情報
  String? _userEmail;
  DateTime? _createdAt;
  UserProfile? _userProfile;
  
  // 統計情報（ダミーデータ）
  int _totalVideos = 0;
  int _totalViews = 0;
  int _totalLikes = 0;
  
  // 設定
  bool _notificationsEnabled = true;

  // バージョン情報
  String _currentVersion = '';
  String _currentBuildNumber = '';
  UpdateInfo? _latestUpdateInfo;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadVersionInfo();
    _loadNotificationSetting();
  }

  Future<void> _loadNotificationSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _toggleNotification(bool enabled) async {
    setState(() {
      _notificationsEnabled = enabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);

    if (enabled) {
      // 通知を有効化: FCMトークンを再取得してSupabaseに保存
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await NotificationService.instance.refreshFcmToken();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('通知をオンにしました'),
                ],
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // OS権限が拒否されている場合はトグルを戻す
        if (mounted) {
          setState(() {
            _notificationsEnabled = false;
          });
          await prefs.setBool('notifications_enabled', false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('通知権限が拒否されています。端末の設定から許可してください。'),
            ),
          );
        }
      }
    } else {
      // 通知を無効化: FCMトークンをSupabaseから削除
      await NotificationService.instance.clearFcmToken();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.notifications_off, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('通知をオフにしました'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _loadVersionInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _currentVersion = packageInfo.version;
      _currentBuildNumber = packageInfo.buildNumber;
    });
    // GitHub Releases から最新バージョンを取得
    final updateInfo = await AppUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _latestUpdateInfo = updateInfo;
    });
  }

  Future<void> _loadUserData({bool isRefresh = false}) async {
    if (!mounted) return;

    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    // ── キャッシュ読み込み（リフレッシュ時はスキップ）──
    if (!isRefresh) {
      final cachedProfile =
          CacheService.instance.get<UserProfile>(CacheKeys.myPageProfile);
      final cachedCount =
          CacheService.instance.get<int>(CacheKeys.myPageVideoCount);
      if (cachedProfile != null && cachedCount != null) {
        if (mounted) {
          setState(() {
            _userEmail = user.email;
            _createdAt = DateTime.parse(user.createdAt);
            _userProfile = cachedProfile;
            _totalVideos = cachedCount;
            _totalViews = cachedCount * 120;
            _totalLikes = cachedCount * 15;
            _isLoading = false;
          });
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // プロフィール情報を取得
      final profile = await _profileService.getProfile(user.id);
      
      // 投稿数を取得
      final videoCount = await _supabase
          .from('videos')
          .select()
          .eq('user_id', user.id)
          .count();

      // キャッシュに保存
      if (profile != null) {
        CacheService.instance.set<UserProfile>(
          CacheKeys.myPageProfile,
          profile,
        );
      }
      CacheService.instance.set<int>(
        CacheKeys.myPageVideoCount,
        videoCount.count,
      );

      setState(() {
        _userEmail = user.email;
        _createdAt = DateTime.parse(user.createdAt);
        _userProfile = profile;
        _totalVideos = videoCount.count;
        // ダミーデータ
        _totalViews = _totalVideos * 120;
        _totalLikes = _totalVideos * 15;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      try {
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

  void _showVersionDialog() {
    final hasUpdate = _latestUpdateInfo != null;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Image.asset('icon.png', height: 36),
            const SizedBox(width: 10),
            const Text('SabaTube'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _versionRow('現在のバージョン', 'v$_currentVersion+$_currentBuildNumber'),
            const SizedBox(height: 6),
            _versionRow(
              'GitHub 最新リリース',
              hasUpdate ? 'v${_latestUpdateInfo!.versionName}' : 'v$_currentVersion（最新）',
              valueColor: hasUpdate ? Colors.orange : Colors.green,
            ),
            if (hasUpdate && _latestUpdateInfo!.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('変更内容', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(_latestUpdateInfo!.releaseNotes, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 16),
            const Text('仲間内でYouTube動画を共有するアプリ', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            const Text('© 2026 サバの仲間たち', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('閉じる'),
          ),
          if (hasUpdate)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                UpdateDialog.show(context, _latestUpdateInfo!);
              },
              icon: const Icon(Icons.system_update, size: 18),
              label: const Text('アップデート'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _versionRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  String _getInitials(String? email) {
    // プロフィールがあればそれを使用
    if (_userProfile != null) {
      return _userProfile!.initials;
    }
    
    // なければメールアドレスから生成
    if (email == null || email.isEmpty) return '?';
    return email[0].toUpperCase();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '不明';
    return '${date.year}年${date.month}月${date.day}日';
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Colors.blue).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.blue,
          size: 24,
        ),
      ),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Colors.blue).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.blue,
          size: 24,
        ),
      ),
      title: Text(title),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  String _themeModeLabel(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'ライトモード';
      case ThemeMode.dark:
        return 'ダークモード';
      case ThemeMode.system:
        return 'システムのテーマに合わせる';
    }
  }

  IconData _themeModeIcon(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  Widget _buildThemeSelector(ThemeMode mode) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _themeModeIcon(mode),
          color: Colors.purple,
          size: 24,
        ),
      ),
      title: const Text('テーマ'),
      subtitle: Text(_themeModeLabel(mode)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        showDialog<ThemeMode>(
          context: context,
          builder: (ctx) {
            ThemeMode selected = mode;
            return StatefulBuilder(
              builder: (ctx, setLocalState) => AlertDialog(
                title: const Text('テーマを選択'),
                content: RadioGroup<ThemeMode>(
                  groupValue: selected,
                  onChanged: (v) => setLocalState(() => selected = v!),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<ThemeMode>(
                        title: const Text('ライトモード'),
                        secondary: const Icon(Icons.light_mode),
                        value: ThemeMode.light,
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('ダークモード'),
                        secondary: const Icon(Icons.dark_mode),
                        value: ThemeMode.dark,
                      ),
                      RadioListTile<ThemeMode>(
                        title: const Text('システムのテーマに合わせる'),
                        secondary: const Icon(Icons.brightness_auto),
                        value: ThemeMode.system,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    onPressed: () {
                      ThemeService.instance.setThemeMode(selected);
                      Navigator.pop(ctx);
                    },
                    child: const Text('適用'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マイページ'),
        automaticallyImplyLeading: false, // 戻るボタンを非表示
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadUserData(isRefresh: true),
              child: SingleChildScrollView(
              child: Column(
                children: [
                  // プロフィールヘッダー
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      children: [
                        // アバター
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.blue,
                          backgroundImage: _userProfile?.avatarUrl != null
                              ? NetworkImage(_userProfile!.avatarUrl!)
                              : null,
                          child: _userProfile?.avatarUrl == null
                              ? Text(
                                  _getInitials(_userEmail),
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        
                        // ユーザー名（プロフィールから取得）
                        Text(
                          _userProfile?.username ?? _userEmail ?? '未設定',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        
                        // メールアドレス
                        Text(
                          _userEmail ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        
                        // 登録日
                        Text(
                          '登録日: ${_formatDate(_createdAt)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // プロフィール編集ボタン
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (_userProfile == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('プロフィール情報の読み込み中です'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EditProfileScreen(
                                  profile: _userProfile!,
                                ),
                              ),
                            );
                            
                            // プロフィール編集から戻ってきたらキャッシュ無効化して再読み込み
                            if (result == true && mounted) {
                              CacheService.instance.invalidate(CacheKeys.myPageProfile);
                              CacheService.instance.invalidate(CacheKeys.myPageVideoCount);
                              _loadUserData(isRefresh: true);
                            }
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('プロフィール編集'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 統計情報
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '統計情報',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.video_library,
                                label: '投稿動画',
                                value: '$_totalVideos',
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.visibility,
                                label: '総再生数',
                                value: '$_totalViews',
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.favorite,
                                label: 'いいね',
                                value: '$_totalLikes',
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 設定セクション
                  Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '設定',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        _buildSwitchTile(
                          icon: Icons.notifications,
                          title: '通知を受け取る',
                          value: _notificationsEnabled,
                          onChanged: _toggleNotification,
                          iconColor: Colors.orange,
                        ),
                        const Divider(height: 1),
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: ThemeService.instance.themeMode,
                          builder: (_, mode, _) => _buildThemeSelector(mode),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // その他のメニュー
                  Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'その他',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        _buildMenuTile(
                          icon: Icons.video_collection,
                          title: '投稿した動画',
                          subtitle: '$_totalVideos件',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MyVideosScreen(),
                              ),
                            );
                          },
                          iconColor: Colors.blue,
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.favorite,
                          title: 'いいねした動画',
                          subtitle: '機能準備中',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('いいね機能は準備中です'),
                              ),
                            );
                          },
                          iconColor: Colors.red,
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.history,
                          title: '視聴履歴',
                          subtitle: '機能準備中',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('視聴履歴機能は準備中です'),
                              ),
                            );
                          },
                          iconColor: Colors.purple,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // サポート・情報
                  Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'サポート・情報',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        _buildMenuTile(
                          icon: Icons.help_outline,
                          title: 'ヘルプ・使い方',
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('使い方'),
                                content: const SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '📹 動画の投稿',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 4),
                                      Text('画面下部の「+」ボタンから投稿できます。'),
                                      SizedBox(height: 12),
                                      Text(
                                        '👀 動画の視聴',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 4),
                                      Text('動画カードをタップするとYouTubeアプリで開きます。'),
                                      SizedBox(height: 12),
                                      Text(
                                        '🔄 最新情報に更新',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 4),
                                      Text('画面を下にスワイプすると最新情報に更新されます。'),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('閉じる'),
                                  ),
                                ],
                              ),
                            );
                          },
                          iconColor: Colors.green,
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.info_outline,
                          title: 'アプリについて',
                          subtitle: _currentVersion.isEmpty
                              ? '読み込み中...'
                              : _latestUpdateInfo != null
                                  ? 'v$_currentVersion  ／  最新: v${_latestUpdateInfo!.versionName} ↑'
                                  : 'v$_currentVersion（最新）',
                          onTap: _currentVersion.isEmpty ? null : () {
                            _showVersionDialog();
                          },
                          trailing: _latestUpdateInfo != null
                              ? const Icon(Icons.system_update, color: Colors.orange)
                              : const Icon(Icons.chevron_right),
                          iconColor: Colors.blue,
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.privacy_tip_outlined,
                          title: 'プライバシーポリシー',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('プライバシーポリシーは準備中です'),
                              ),
                            );
                          },
                          iconColor: Colors.grey,
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.description_outlined,
                          title: '利用規約',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('利用規約は準備中です'),
                              ),
                            );
                          },
                          iconColor: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // ログアウトボタン
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _handleLogout,
                        icon: const Icon(Icons.logout),
                        label: const Text('ログアウト'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
      // ボトムナビゲーション
      bottomNavigationBar: const AppBottomNavigationBar(currentIndex: 4),
    );
  }
}