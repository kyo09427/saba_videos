import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase接続を管理するサービスクラス
///
/// このクラスはシングルトンパターンを使用して、
/// アプリ全体で単一のSupabaseクライアントインスタンスを共有します。
class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseClient? _client;
  static String? _sharedPassword;
  static String? _supabaseUrl;

  static String? get supabaseUrl => _supabaseUrl;

  SupabaseService._();

  /// シングルトンインスタンスを取得
  static SupabaseService get instance {
    _instance ??= SupabaseService._();
    return _instance!;
  }

  /// Supabaseクライアントを取得
  SupabaseClient get client {
    if (_client == null) {
      throw StateError(
        'Supabase is not initialized. Call SupabaseService.initialize() first.',
      );
    }
    return _client!;
  }

  /// Supabaseの初期化
  ///
  /// アプリ起動時に一度だけ呼び出す必要があります。
  /// .envファイルから環境変数を読み込み、Supabaseクライアントを初期化します。
  ///
  /// Throws:
  ///   - [Exception] 環境変数が設定されていない場合
  ///   - [Exception] Supabaseの初期化に失敗した場合
  static Future<void> initialize() async {
    try {
      // .envファイルを読み込む
      await dotenv.load(fileName: '.env');

      // 環境変数の取得と検証
      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
      _sharedPassword = dotenv.env['SHARED_PASSWORD'];

      // URLの検証
      if (supabaseUrl == null || supabaseUrl.trim().isEmpty) {
        throw Exception(
          'SUPABASE_URL is not defined or empty in .env file. '
          'Please set it to your Supabase project URL.',
        );
      }

      // Anon Keyの検証
      if (supabaseAnonKey == null || supabaseAnonKey.trim().isEmpty) {
        throw Exception(
          'SUPABASE_ANON_KEY is not defined or empty in .env file. '
          'Please set it to your Supabase project anon key.',
        );
      }

      // 共有パスワードの検証
      if (_sharedPassword == null || _sharedPassword!.trim().isEmpty) {
        throw Exception(
          'SHARED_PASSWORD is not defined or empty in .env file. '
          'Please set it to your shared password.',
        );
      }

      // URLの形式検証
      final uri = Uri.tryParse(supabaseUrl);
      if (uri == null || !uri.hasScheme || !uri.host.contains('supabase')) {
        throw Exception(
          'SUPABASE_URL appears to be invalid. '
          'Expected format: https://your-project.supabase.co',
        );
      }

      // Supabaseの初期化
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        debug: kDebugMode,
      );

      _client = Supabase.instance.client;
      _supabaseUrl = supabaseUrl;

      if (kDebugMode) {
        debugPrint('✅ Supabase initialized successfully');
        debugPrint('   URL: $supabaseUrl');
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Supabase initialization failed: $e');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Unexpected error during Supabase initialization: $e');
      }
      throw Exception('Failed to initialize Supabase: $e');
    }
  }

  /// 共有パスワードを検証
  ///
  /// [password] 検証するパスワード
  ///
  /// Returns: パスワードが一致する場合true、それ以外false
  ///
  /// Throws:
  ///   - [StateError] 共有パスワードが初期化されていない場合
  bool validateSharedPassword(String password) {
    if (_sharedPassword == null) {
      throw StateError(
        'Shared password is not initialized. '
        'Make sure SHARED_PASSWORD is set in .env file.',
      );
    }

    if (password.trim().isEmpty) {
      return false;
    }

    return password.trim() == _sharedPassword!.trim();
  }

  /// 現在のユーザーを取得
  ///
  /// Returns: ログイン中のユーザー、未ログインの場合null
  User? get currentUser => client.auth.currentUser;

  /// 現在のセッションを取得
  ///
  /// Returns: 有効なセッション、存在しない場合null
  Session? get currentSession => client.auth.currentSession;

  /// 認証状態の変更を監視するストリーム
  ///
  /// このストリームを使用して、ログイン/ログアウトなどの
  /// 認証状態の変化をリアルタイムで監視できます。
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// メールアドレスとパスワードで新規登録
  ///
  /// [email] 登録するメールアドレス
  /// [password] パスワード（6文字以上推奨）
  ///
  /// Returns: 認証レスポンス（ユーザー情報を含む）
  ///
  /// Throws:
  ///   - [AuthException] メールアドレスが既に使用されている場合
  ///   - [AuthException] パスワードが弱い場合
  ///   - [Exception] ネットワークエラーなどの場合
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Attempting sign up for: $email');
      }

      // 入力値の検証
      final trimmedEmail = email.trim();
      if (trimmedEmail.isEmpty) {
        throw Exception('Email address cannot be empty');
      }

      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }

      final response = await client.auth.signUp(
        email: trimmedEmail,
        password: password,
      );

      if (kDebugMode) {
        debugPrint('✅ Sign up successful for: $trimmedEmail');
        if (response.user != null) {
          debugPrint('   User ID: ${response.user!.id}');
          debugPrint(
            '   Email confirmed: ${response.user!.emailConfirmedAt != null}',
          );
        }
      }

      // 注意: プロフィールは初回ログイン時に作成されます
      // （signUp直後はセッションが不完全なため、RLSポリシーが機能しない）

      return response;
    } on AuthException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign up failed (AuthException): ${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign up failed: $e');
      }
      rethrow;
    }
  }

  /// メールアドレスとパスワードでログイン
  ///
  /// [email] メールアドレス
  /// [password] パスワード
  ///
  /// Returns: 認証レスポンス（セッション情報を含む）
  ///
  /// Throws:
  ///   - [AuthException] 認証情報が正しくない場合
  ///   - [AuthException] メールが確認されていない場合
  ///   - [Exception] ネットワークエラーなどの場合
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Attempting sign in for: $email');
      }

      // 入力値の検証
      final trimmedEmail = email.trim();
      if (trimmedEmail.isEmpty) {
        throw Exception('Email address cannot be empty');
      }

      if (password.isEmpty) {
        throw Exception('Password cannot be empty');
      }

      final response = await client.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );

      if (kDebugMode) {
        debugPrint('✅ Sign in successful for: $trimmedEmail');
        if (response.session != null) {
          debugPrint('   Session expires: ${response.session!.expiresAt}');
        }
      }

      // ログイン成功後、プロフィールが存在しない場合は作成
      if (response.user != null) {
        await _ensureProfileExists(response.user!);
      }

      return response;
    } on AuthException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign in failed (AuthException): ${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign in failed: $e');
      }
      rethrow;
    }
  }

  /// ユーザーのプロフィールが存在することを確認し、存在しない場合は作成
  ///
  /// [user] ログイン中のユーザー
  Future<void> _ensureProfileExists(User user) async {
    try {
      // プロフィールが既に存在するかチェック
      final existingProfile = await client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      // 既に存在する場合は何もしない
      if (existingProfile != null) {
        if (kDebugMode) {
          debugPrint('ℹ️ Profile already exists for user: ${user.id}');
        }
        return;
      }

      // プロフィールが存在しない場合は作成
      if (kDebugMode) {
        debugPrint('📝 Creating initial profile for user: ${user.id}');
      }

      // メールアドレスのローカル部分をデフォルトユーザー名として使用
      // emailがnullの場合（Discord OAuthなど）はuser IDの先頭8文字をフォールバックとして使用
      String defaultUsername =
          user.email?.split('@')[0] ?? 'user_${user.id.substring(0, 8)}';

      // ユーザー名が既に存在するかチェック
      final existingUsername = await client
          .from('profiles')
          .select('username')
          .eq('username', defaultUsername)
          .maybeSingle();

      // 既に存在する場合は、UUIDの一部を追加してユニークにする
      if (existingUsername != null) {
        defaultUsername = '${defaultUsername}_${user.id.substring(0, 8)}';
      }

      // プロフィールを作成
      await client.from('profiles').insert({
        'id': user.id,
        'username': defaultUsername,
      });

      if (kDebugMode) {
        debugPrint('✅ Initial profile created for user: ${user.id}');
        debugPrint('   Username: $defaultUsername');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to ensure profile exists: $e');
      }
      // プロフィール作成に失敗してもログイン自体は成功しているため、
      // エラーをログに記録するのみで例外はスローしない
    }
  }

  /// ログアウト
  ///
  /// 現在のセッションを終了し、ローカルに保存されている
  /// 認証情報をクリアします。
  ///
  /// Throws:
  ///   - [Exception] ログアウトに失敗した場合
  Future<void> signOut() async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Attempting sign out');
      }

      await client.auth.signOut();

      if (kDebugMode) {
        debugPrint('✅ Sign out successful');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Sign out failed: $e');
      }
      rethrow;
    }
  }

  /// パスワードリセットメールを送信
  ///
  /// [email] パスワードをリセットするメールアドレス
  ///
  /// Throws:
  ///   - [AuthException] メールアドレスが存在しない場合
  ///   - [Exception] ネットワークエラーなどの場合
  Future<void> resetPasswordForEmail(String email) async {
    try {
      if (kDebugMode) {
        debugPrint('📧 Sending password reset email to: $email');
      }

      final trimmedEmail = email.trim();
      if (trimmedEmail.isEmpty) {
        throw Exception('Email address cannot be empty');
      }

      await client.auth.resetPasswordForEmail(trimmedEmail);

      if (kDebugMode) {
        debugPrint('✅ Password reset email sent');
      }
    } on AuthException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Password reset failed (AuthException): ${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Password reset failed: $e');
      }
      rethrow;
    }
  }

  /// 認証状態を確認
  ///
  /// Returns: ログイン中で有効なセッションがある場合true
  bool get isAuthenticated {
    final user = currentUser;
    final session = currentSession;
    return user != null && session != null;
  }

  /// Supabaseサービスをリセット（テスト用）
  ///
  /// 警告: 本番環境では使用しないでください
  @visibleForTesting
  static void reset() {
    _instance = null;
    _client = null;
    _sharedPassword = null;
  }

  // ============================================
  // チャンネル登録関連メソッド
  // ============================================

  /// チャンネルを登録
  ///
  /// [channelId] 登録するチャンネル（ユーザー）のID
  ///
  /// Throws:
  ///   - [Exception] 自分自身を登録しようとした場合
  ///   - [Exception] 既に登録済みの場合
  ///   - [Exception] 登録に失敗した場合
  Future<void> subscribeToChannel(String channelId) async {
    try {
      final currentUserId = currentUser?.id;
      if (currentUserId == null) {
        throw Exception('ログインが必要です');
      }

      if (currentUserId == channelId) {
        throw Exception('自分自身のチャンネルは登録できません');
      }

      if (kDebugMode) {
        debugPrint('📺 Subscribing to channel: $channelId');
      }

      await client.from('subscriptions').insert({
        'subscriber_id': currentUserId,
        'channel_id': channelId,
      });

      if (kDebugMode) {
        debugPrint('✅ Successfully subscribed to channel: $channelId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to subscribe to channel: $e');
      }
      rethrow;
    }
  }

  /// チャンネル登録を解除
  ///
  /// [channelId] 登録解除するチャンネル（ユーザー）のID
  ///
  /// Throws:
  ///   - [Exception] 登録解除に失敗した場合
  Future<void> unsubscribeFromChannel(String channelId) async {
    try {
      final currentUserId = currentUser?.id;
      if (currentUserId == null) {
        throw Exception('ログインが必要です');
      }

      if (kDebugMode) {
        debugPrint('📺 Unsubscribing from channel: $channelId');
      }

      await client
          .from('subscriptions')
          .delete()
          .eq('subscriber_id', currentUserId)
          .eq('channel_id', channelId);

      if (kDebugMode) {
        debugPrint('✅ Successfully unsubscribed from channel: $channelId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to unsubscribe from channel: $e');
      }
      rethrow;
    }
  }

  /// チャンネルを登録しているかチェック
  ///
  /// [channelId] チェックするチャンネル（ユーザー）のID
  ///
  /// Returns: 登録している場合true、それ以外false
  Future<bool> isSubscribed(String channelId) async {
    try {
      final currentUserId = currentUser?.id;
      if (currentUserId == null) {
        return false;
      }

      final result = await client
          .from('subscriptions')
          .select()
          .eq('subscriber_id', currentUserId)
          .eq('channel_id', channelId)
          .maybeSingle();

      return result != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to check subscription status: $e');
      }
      return false;
    }
  }

  /// チャンネルの登録者数を取得
  ///
  /// [channelId] チャンネル（ユーザー）のID
  ///
  /// Returns: 登録者数
  Future<int> getSubscriberCount(String channelId) async {
    try {
      final result = await client
          .from('subscriptions')
          .select()
          .eq('channel_id', channelId);

      return result is List ? result.length : 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to get subscriber count: $e');
      }
      return 0;
    }
  }

  /// 登録しているチャンネルのIDリストを取得
  ///
  /// Returns: 登録チャンネルのIDリスト
  Future<List<String>> getSubscribedChannelIds() async {
    try {
      final currentUserId = currentUser?.id;
      if (currentUserId == null) {
        return [];
      }

      final result = await client
          .from('subscriptions')
          .select('channel_id')
          .eq('subscriber_id', currentUserId);

      if (result is! List) return [];
      return result
          .whereType<Map<String, dynamic>>()
          .map((e) => e['channel_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to get subscribed channel IDs: $e');
      }
      return [];
    }
  }

  /// チャンネルの動画数を取得
  ///
  /// [channelId] チャンネル（ユーザー）のID
  ///
  /// Returns: 動画数
  Future<int> getChannelVideoCount(String channelId) async {
    try {
      final result = await client
          .from('videos')
          .select()
          .eq('user_id', channelId);

      return result is List ? result.length : 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to get channel video count: $e');
      }
      return 0;
    }
  }
}
