import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Discord OAuth認証とサーバーメンバーシップ検証を行うサービス
///
/// 特定のDiscordサーバーに参加しているユーザーのみ
/// ログイン・新規登録を許可します。
class DiscordAuthService {
  static DiscordAuthService? _instance;
  static String? _guildId;

  DiscordAuthService._();

  /// シングルトンインスタンスを取得
  static DiscordAuthService get instance {
    _instance ??= DiscordAuthService._();
    return _instance!;
  }

  /// 初期化（.envからGuild IDを読み込み）
  static void initialize() {
    _guildId = dotenv.env['DISCORD_GUILD_ID'];
    if (_guildId == null || _guildId!.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ DISCORD_GUILD_ID is not set in .env file');
      }
    } else {
      if (kDebugMode) {
        debugPrint('✅ Discord Auth Service initialized (Guild ID: $_guildId)');
      }
    }
  }

  /// Guild IDが設定されているか確認
  bool get isConfigured => _guildId != null && _guildId!.trim().isNotEmpty;

  /// Discord OAuthでサインインを開始
  ///
  /// Supabaseの組み込みOAuth機能を使用して、Discord認証フローを開始します。
  /// Web環境ではリダイレクト方式を使用します。
  ///
  /// Throws:
  ///   - [Exception] Guild IDが設定されていない場合
  ///   - [AuthException] OAuth開始に失敗した場合
  Future<void> signInWithDiscord() async {
    if (!isConfigured) {
      throw Exception('Discord認証が設定されていません。管理者に問い合わせてください。');
    }

    try {
      if (kDebugMode) {
        debugPrint('🔐 Starting Discord OAuth flow...');
      }

      // Supabaseの組み込みDiscord OAuth を使用
      // guilds スコープを追加して、サーバーメンバーシップを確認できるようにする
      await SupabaseService.instance.client.auth.signInWithOAuth(
        OAuthProvider.discord,
        scopes: 'identify email guilds',
        redirectTo: kIsWeb ? _getWebRedirectUrl() : null,
      );

      if (kDebugMode) {
        debugPrint('✅ Discord OAuth flow initiated');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Discord OAuth failed: $e');
      }
      rethrow;
    }
  }

  /// Discord OAuthコールバック後にサーバーメンバーシップを検証
  ///
  /// OAuthログイン成功後に呼び出し、ユーザーが指定のDiscordサーバーに
  /// 参加しているかどうかを確認します。
  ///
  /// [session] 現在のSupabaseセッション
  ///
  /// Returns: サーバーメンバーの場合true
  ///
  /// Throws:
  ///   - [Exception] メンバーシップ確認に失敗した場合
  Future<bool> verifyGuildMembership(Session session) async {
    if (!isConfigured) {
      if (kDebugMode) {
        debugPrint('⚠️ Guild ID not configured, skipping membership check');
      }
      return true; // Guild IDが未設定なら検証をスキップ
    }

    try {
      if (kDebugMode) {
        debugPrint('🔍 Verifying Discord guild membership...');
      }

      // Supabaseのセッションからプロバイダートークンを取得
      final providerToken = session.providerToken;
      if (providerToken == null) {
        if (kDebugMode) {
          debugPrint('⚠️ No provider token found in session');
        }
        return false;
      }

      // Discord APIでユーザーのギルド一覧を取得
      final response = await http.get(
        Uri.parse('https://discord.com/api/v10/users/@me/guilds'),
        headers: {
          'Authorization': 'Bearer $providerToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('❌ Discord API error: ${response.statusCode} ${response.body}');
        }
        throw Exception('Discordサーバー情報の取得に失敗しました');
      }

      final List<dynamic> guilds = json.decode(response.body);

      // 指定のGuild IDがユーザーのギルド一覧に含まれるか確認
      final isMember = guilds.any((guild) => guild['id'] == _guildId);

      if (kDebugMode) {
        debugPrint(isMember
            ? '✅ User is a member of the required Discord server'
            : '❌ User is NOT a member of the required Discord server');
        debugPrint('   User guilds: ${guilds.map((g) => '${g['name']} (${g['id']})').join(', ')}');
      }

      return isMember;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Guild membership verification failed: $e');
      }
      rethrow;
    }
  }

  /// Discordログイン後のサーバーメンバーシップ検証とプロフィール作成
  ///
  /// メンバーでない場合は自動的にサインアウトします。
  ///
  /// Returns: メンバーシップが確認され、ログインが成功した場合true
  Future<bool> handleDiscordCallback(Session session) async {
    try {
      // サーバーメンバーシップを検証
      final isMember = await verifyGuildMembership(session);

      if (!isMember) {
        // メンバーでない場合はサインアウト
        if (kDebugMode) {
          debugPrint('🚫 User is not a member of the required server. Signing out...');
        }
        await SupabaseService.instance.signOut();
        return false;
      }

      // メンバーの場合、プロフィールが存在するか確認して作成
      final user = session.user;
      await _ensureDiscordProfileExists(user);

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Discord callback handling failed: $e');
      }
      // エラーが発生した場合もサインアウト
      try {
        await SupabaseService.instance.signOut();
      } catch (_) {}
      rethrow;
    }
  }

  /// Discordユーザーのプロフィールを作成（存在しない場合）
  Future<void> _ensureDiscordProfileExists(User user) async {
    try {
      final client = SupabaseService.instance.client;

      // プロフィールが既に存在するかチェック
      final existingProfile = await client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile != null) {
        if (kDebugMode) {
          debugPrint('ℹ️ Profile already exists for Discord user: ${user.id}');
        }
        return;
      }

      // Discordのユーザー情報からデフォルトユーザー名を決定
      String defaultUsername = _getDiscordUsername(user);

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
        debugPrint('✅ Discord profile created for user: ${user.id}');
        debugPrint('   Username: $defaultUsername');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to create Discord profile: $e');
      }
      // プロフィール作成に失敗してもログイン自体は成功しているため、
      // エラーをログに記録するのみ
    }
  }

  /// Discordユーザーからユーザー名を取得
  String _getDiscordUsername(User user) {
    // user_metadataからDiscordの情報を取得
    final metadata = user.userMetadata;
    if (metadata != null) {
      // Discordのユーザー名 (full_name or name)
      final fullName = metadata['full_name'] as String?;
      if (fullName != null && fullName.isNotEmpty) {
        return fullName;
      }
      final name = metadata['name'] as String?;
      if (name != null && name.isNotEmpty) {
        return name;
      }
      // Discord custom_claims の preferred_username
      final preferredUsername = metadata['preferred_username'] as String?;
      if (preferredUsername != null && preferredUsername.isNotEmpty) {
        return preferredUsername;
      }
    }

    // フォールバック: メールのローカル部分またはユーザーIDの一部
    if (user.email != null && user.email!.isNotEmpty) {
      return user.email!.split('@')[0];
    }
    return 'user_${user.id.substring(0, 8)}';
  }

  /// Web環境でのリダイレクトURLを取得
  String _getWebRedirectUrl() {
    // Webの場合、現在のURLをリダイレクト先として使用
    // Cloudflare Pagesにデプロイされている場合のURLを返す
    return Uri.base.origin;
  }

  /// サービスをリセット（テスト用）
  @visibleForTesting
  static void reset() {
    _instance = null;
    _guildId = null;
  }
}
