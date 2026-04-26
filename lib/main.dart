import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'services/supabase_service.dart';
import 'services/discord_auth_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日本語ロケールの初期化
  await initializeDateFormatting('ja_JP', null);

  // Firebaseの初期化（プッシュ通知に必要）
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Supabaseの初期化
  try {
    await SupabaseService.initialize();
    // Discord認証サービスの初期化
    DiscordAuthService.initialize();
  } catch (e) {
    // 初期化エラーをログ出力
    debugPrint('Supabase initialization error: $e');
  }

  // テーマの初期化（保存済み設定を読み込む）
  await ThemeService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    ThemeService.instance.themeMode.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeService.instance.themeMode.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    ).copyWith(
      // カード・コンテナ・ダイアログの背景
      surface: isDark ? const Color(0xFF272727) : Colors.white,
      onSurface: isDark ? Colors.white : Colors.black87,
      onSurfaceVariant: isDark ? const Color(0xFFAAAAAA) : Colors.grey.shade600,
      surfaceContainer: isDark ? const Color(0xFF272727) : Colors.grey.shade100,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      // Scaffold（画面）の背景色
      scaffoldBackgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.grey.shade100,
      // AppBar のデフォルト色
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
      ),
      // Divider の色
      dividerColor: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade300,
      // カードの背景色
      cardColor: isDark ? const Color(0xFF272727) : Colors.white,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SabaTube',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeService.instance.themeMode.value,
      home: const AuthWrapper(),
    );
  }
}

/// 認証状態に応じて画面を切り替えるラッパー
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void dispose() {
    NotificationService.instance.forcedLogout.removeListener(_onForcedLogout);
    super.dispose();
  }

  /// 他プラットフォームからのログインを検知した際に強制ログアウトする。
  Future<void> _onForcedLogout() async {
    if (!NotificationService.instance.forcedLogout.value) return;
    if (!mounted) return;

    final platform = kIsWeb ? 'Android アプリ' : 'ブラウザ';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('別のデバイスでログイン'),
        content: Text('$platform から同じアカウントでログインされました。このセッションを終了します。'),
        actions: [
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await NotificationService.instance.dispose();
              await NotificationService.instance.clearFcmToken();
              await SupabaseService.instance.signOut();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Discordギルド検証の状態管理
  /// null: 検証不要 or 未開始, true: 検証中, false: 検証完了
  bool? _isVerifyingGuild;
  bool _guildVerified = false;
  String? _guildErrorMessage;

  @override
  void initState() {
    super.initState();
    _checkInitialization();
    NotificationService.instance.forcedLogout.addListener(_onForcedLogout);
  }

  Future<void> _checkInitialization() async {
    try {
      // Supabaseが初期化されているか確認
      final _ = SupabaseService.instance.client;
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'アプリの初期化に失敗しました。\n設定を確認してください。';
        _isInitialized = true;
      });
    }
  }

  /// Discordログインユーザーのサーバーメンバーシップ検証
  ///
  /// 初回ログイン時: providerTokenを使ってDiscord APIで検証 → DB保存
  /// セッション復帰時: DBに保存された検証結果を参照
  Future<void> _verifyDiscordMembership(Session session) async {
    // Discord OAuthでのログインかどうかを確認
    final provider = session.user.appMetadata['provider'];
    if (provider != 'discord') {
      // Discord以外のログインは検証不要
      setState(() {
        _guildVerified = true;
        _isVerifyingGuild = false;
      });
      return;
    }

    setState(() {
      _isVerifyingGuild = true;
      _guildErrorMessage = null;
    });

    try {
      if (session.providerToken != null) {
        // === 初回ログイン: providerTokenがある場合はAPI検証 ===
        final success = await DiscordAuthService.instance.handleDiscordCallback(session);
        if (mounted) {
          if (success) {
            setState(() {
              _guildVerified = true;
              _isVerifyingGuild = false;
            });
          } else {
            setState(() {
              _guildVerified = false;
              _isVerifyingGuild = false;
              _guildErrorMessage = '指定のDiscordサーバーに参加していないため、\nログインできません。';
            });
          }
        }
      } else {
        // === セッション復帰: providerTokenがない場合はDB参照 ===
        final isVerifiedInDb = await DiscordAuthService.instance
            .checkStoredGuildVerification(session.user.id);

        if (mounted) {
          if (isVerifiedInDb) {
            setState(() {
              _guildVerified = true;
              _isVerifyingGuild = false;
            });
          } else {
            // DB上でも検証されていない場合はサインアウト
            await SupabaseService.instance.signOut();
            setState(() {
              _guildVerified = false;
              _isVerifyingGuild = false;
              _guildErrorMessage = 'Discordサーバーのメンバーシップが確認できません。\n再度ログインしてください。';
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        // エラー発生時もサインアウト
        try {
          await SupabaseService.instance.signOut();
        } catch (signOutError) {
          debugPrint('⚠️ Sign out failed during error recovery: $signOutError');
        }
        setState(() {
          _isVerifyingGuild = false;
          _guildVerified = false;
          _guildErrorMessage = 'Discordサーバーの確認に失敗しました。\n再度お試しください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- 初期化中 ---
    if (!_isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('icon.png', width: 100, height: 100),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('初期化中...'),
            ],
          ),
        ),
      );
    }

    // --- 初期化エラー ---
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isInitialized = false;
                      _errorMessage = null;
                    });
                    _checkInitialization();
                  },
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // --- ギルド検証中 ---
    if (_isVerifyingGuild == true) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('icon.png', width: 100, height: 100),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Discordサーバーを確認中...'),
            ],
          ),
        ),
      );
    }

    // --- ギルド検証エラー ---
    if (_guildErrorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.block,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                Text(
                  _guildErrorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _guildErrorMessage = null;
                      _guildVerified = false;
                      _isVerifyingGuild = null;
                    });
                  },
                  child: const Text('ログイン画面に戻る'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // --- 認証状態の監視 ---
    return StreamBuilder(
      stream: SupabaseService.instance.authStateChanges,
      builder: (context, snapshot) {
        // 認証状態を確認中
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // エラーハンドリング
        if (snapshot.hasError) {
          final errorStr = snapshot.error.toString();
          final isDiscordExchangeError = errorStr.contains('Unable to exchange external code') ||
              (errorStr.contains('server_error') && errorStr.contains('unexpected_failure'));
          final supabaseCallbackUrl = isDiscordExchangeError
              ? '${SupabaseService.instance.client.supabaseUrl}/auth/v1/callback'
              : null;

          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isDiscordExchangeError
                          ? 'Discord認証の設定を確認してください。\n\n以下のURLがDiscord Developer PortalのOAuth2リダイレクトURIに登録されているか確認してください：\n\n$supabaseCallbackUrl\n\nまたはSupabaseのDiscordプロバイダー設定（Client ID/Secret）を確認してください。'
                          : '認証エラーが発生しました。\n$errorStr',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _guildVerified = false;
                          _isVerifyingGuild = null;
                          _guildErrorMessage = null;
                        });
                      },
                      child: const Text('再読み込み'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 認証済みかチェック
        final session = snapshot.hasData ? snapshot.data!.session : null;

        if (session != null) {
          final isDiscordUser = session.user.appMetadata['provider'] == 'discord';

          if (isDiscordUser) {
            // Discordユーザー: ギルド検証が必要
            if (!_guildVerified) {
              // まだ検証されていない場合、検証を開始
              if (_isVerifyingGuild != true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _verifyDiscordMembership(session);
                });
              }
              // 検証完了まではローディングを表示（HomeScreenは見せない）
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Discordサーバーを確認中...'),
                    ],
                  ),
                ),
              );
            }
            // 検証済み → 通知サービス初期化 → ホーム画面
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationService.instance.initialize();
            });
            return const HomeScreen();
          } else {
            // メール+パスワードユーザー: 検証不要でホーム画面
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationService.instance.initialize();
            });
            return const HomeScreen();
          }
        } else {
          // 未ログイン → 通知サービスをリセット → ログイン画面（状態リセット）
          if (_guildVerified || _isVerifyingGuild != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                NotificationService.instance.dispose();
                NotificationService.instance.clearFcmToken();
                setState(() {
                  _guildVerified = false;
                  _isVerifyingGuild = null;
                  _guildErrorMessage = null;
                });
              }
            });
          }
          return const LoginScreen();
        }
      },
    );
  }
}