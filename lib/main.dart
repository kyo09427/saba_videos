import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'services/discord_auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日本語ロケールの初期化
  await initializeDateFormatting('ja_JP', null);

  // Supabaseの初期化
  try {
    await SupabaseService.initialize();
    // Discord認証サービスの初期化
    DiscordAuthService.initialize();
  } catch (e) {
    // 初期化エラーをログ出力
    debugPrint('Supabase initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'サバの動画',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
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
      ),
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
  bool _isVerifyingGuild = false;
  String? _errorMessage;
  String? _guildErrorMessage;

  @override
  void initState() {
    super.initState();
    _checkInitialization();
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

  /// Discordログイン後のサーバーメンバーシップ検証
  Future<void> _verifyDiscordMembership(session) async {
    // Discord OAuthでのログインかどうかを確認
    final provider = session.user?.appMetadata['provider'];
    if (provider != 'discord') {
      return; // Discord以外のログインはスキップ
    }

    // プロバイダートークンがない場合はスキップ（既存セッションの復帰時）
    if (session.providerToken == null) {
      return;
    }

    setState(() {
      _isVerifyingGuild = true;
      _guildErrorMessage = null;
    });

    try {
      final success = await DiscordAuthService.instance.handleDiscordCallback(session);
      if (!success) {
        setState(() {
          _guildErrorMessage = '指定のDiscordサーバーに参加していないため、\nログインできません。';
        });
      }
    } catch (e) {
      setState(() {
        _guildErrorMessage = 'Discordサーバーの確認に失敗しました。\n再度お試しください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingGuild = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('初期化中...'),
            ],
          ),
        ),
      );
    }

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

    // サーバーメンバーシップ検証中
    if (_isVerifyingGuild) {
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

    // サーバーメンバーシップエラー
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
                      '認証エラーが発生しました。\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {});
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
          // Discord OAuthでの新規ログイン時にサーバーメンバーシップを検証
          final authEvent = snapshot.data!.event;
          if (authEvent == AuthChangeEvent.signedIn &&
              session.user.appMetadata['provider'] == 'discord' &&
              session.providerToken != null) {
            // 非同期でギルドメンバーシップを検証
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _verifyDiscordMembership(session);
            });
          }

          // ログイン済み → ホーム画面
          return const HomeScreen();
        } else {
          // 未ログイン → ログイン画面
          return const LoginScreen();
        }
      },
    );
  }
}