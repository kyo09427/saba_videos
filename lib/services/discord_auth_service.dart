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
/// ギルド検証結果はDBに永続化し、セッション復帰時にも検証可能です。
class DiscordAuthService {
  static DiscordAuthService? _instance;
  static String? _guildId;

  /// モバイルアプリ用のカスタムURLスキーム
  static const String _mobileCallbackScheme = 'win.okasis.sabatube';
  static const String _mobileCallbackUrl = '$_mobileCallbackScheme://login-callback';

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
        debugPrint('✅ Discord Auth Service initialized');
      }
    }
  }

  /// Guild IDが設定されているか確認
  bool get isConfigured => _guildId != null && _guildId!.trim().isNotEmpty;

  /// Discord OAuthでサインインを開始
  ///
  /// Supabaseの組み込みOAuth機能を使用して、Discord認証フローを開始します。
  /// プラットフォームに応じて適切なリダイレクトURLを設定します。
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

      // プラットフォームに応じたリダイレクトURLを設定
      final redirectUrl = _getRedirectUrl();

      if (kDebugMode) {
        debugPrint('🔗 Redirect URL: $redirectUrl');
      }

      // Supabaseの組み込みDiscord OAuth を使用
      // guilds スコープを追加して、サーバーメンバーシップを確認できるようにする
      await SupabaseService.instance.client.auth.signInWithOAuth(
        OAuthProvider.discord,
        scopes: 'identify email guilds',
        redirectTo: redirectUrl,
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
      // フェイルクローズ: Guild ID未設定ならログイン拒否
      if (kDebugMode) {
        debugPrint('❌ Guild ID not configured, rejecting login (fail-closed)');
      }
      return false;
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
          debugPrint('❌ Discord API error: ${response.statusCode}');
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
      }

      return isMember;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Guild membership verification failed: $e');
      }
      rethrow;
    }
  }

  /// DBに保存されたギルド検証済みフラグを確認
  ///
  /// セッション復帰時（providerTokenなし）にDBから検証状態を取得します。
  ///
  /// [userId] 確認するユーザーID
  ///
  /// Returns: DB上でギルド検証済みの場合true
  Future<bool> checkStoredGuildVerification(String userId) async {
    try {
      final result = await SupabaseService.instance.client
          .from('profiles')
          .select('discord_guild_verified')
          .eq('id', userId)
          .maybeSingle();

      if (result == null) {
        return false;
      }

      final verified = result['discord_guild_verified'] as bool? ?? false;

      if (kDebugMode) {
        debugPrint(verified
            ? '✅ Guild verification found in DB for user: $userId'
            : '❌ No guild verification in DB for user: $userId');
      }

      return verified;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to check stored guild verification: $e');
      }
      return false;
    }
  }

  /// ギルド検証結果をDBに保存
  ///
  /// [userId] 保存対象のユーザーID
  /// [verified] 検証結果
  Future<void> _saveGuildVerification(String userId, bool verified) async {
    try {
      await SupabaseService.instance.client
          .from('profiles')
          .update({
        'discord_guild_verified': verified,
        'discord_guild_verified_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      if (kDebugMode) {
        debugPrint('✅ Guild verification saved to DB: verified=$verified');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to save guild verification: $e');
      }
      // 保存失敗してもログインフロー自体は継続
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
        // 検証失敗をDBに記録
        await _saveGuildVerification(session.user.id, false);
        await SupabaseService.instance.signOut();
        return false;
      }

      // メンバーの場合、プロフィールが存在するか確認して作成
      final user = session.user;
      await _ensureDiscordProfileExists(user);

      // 検証成功をDBに保存
      await _saveGuildVerification(user.id, true);

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
          debugPrint('ℹ️ Profile already exists for Discord user');
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
        'discord_guild_verified': false,
      });

      if (kDebugMode) {
        debugPrint('✅ Discord profile created');
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

  /// プラットフォームに応じたリダイレクトURLを取得
  String? _getRedirectUrl() {
    if (kIsWeb) {
      // Web: 現在のoriginをリダイレクト先として使用
      return Uri.base.origin;
    } else {
      // モバイル: カスタムURLスキームを使用
      return _mobileCallbackUrl;
    }
  }

  /// サービスをリセット（テスト用）
  @visibleForTesting
  static void reset() {
    _instance = null;
    _guildId = null;
  }
}
