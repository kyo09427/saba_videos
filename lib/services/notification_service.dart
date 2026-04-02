import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';
import 'supabase_service.dart';

/// Web FCM 用の VAPID 公開鍵。
/// Firebase Console > Project Settings > Cloud Messaging > Web configuration > 鍵ペア
const _kWebVapidKey =
    'BEexX4VY1EtJqthnxOe56_RAHTkiwzsQkvDnbnrpxKV0tReZcZYOEqf-STo2O6nXUtuSPEwqqBSC3UTDBCkbXU0';

/// バックグラウンド/終了状態でのFCMメッセージハンドラ。
/// トップレベル関数である必要がある。
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // バックグラウンドでは FCM SDK が自動的に通知を表示するため、
  // ここでは未読数の更新はできない（Isolateが分離しているため）。
  // アプリ復帰時に refreshUnreadCount() が呼ばれて同期される。
  debugPrint('📲 バックグラウンド通知受信: ${message.notification?.title}');
}

/// アプリ内通知 + プッシュ通知を管理するシングルトンサービス。
///
/// 責務:
///   - 通知一覧の取得
///   - 未読数の管理（[unreadCount] ValueNotifier）
///   - Supabase Realtime による新着通知のリアルタイム受信
///   - 既読処理
///   - FCM トークンの取得・Supabase への保存（Android: fcm_token / Web: web_fcm_token）
///   - フォアグラウンド時の FCM メッセージ受信
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// 未読通知数。UI側は ValueListenableBuilder でリッスンする。
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  RealtimeChannel? _realtimeChannel;

  /// initialize() の多重呼び出しを防ぐフラグ
  bool _isInitialized = false;

  /// FCMリスナーの多重登録を防ぐフラグ
  bool _isFcmInitialized = false;

  // ------------------------------------------------------------------
  // 初期化 / 破棄
  // ------------------------------------------------------------------

  /// ログイン後に呼び出す。
  /// 未読数取得・Realtime購読・FCM初期化を行う。
  /// 既に初期化済みの場合は何もしない（多重呼び出し対策）。
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await refreshUnreadCount();
    await _subscribeRealtime();
    await _initFcm();
  }

  /// ログアウト時に呼び出す。購読を解除し未読数をリセットする。
  Future<void> dispose() async {
    await _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    unreadCount.value = 0;
    _isInitialized = false;
    _isFcmInitialized = false;
  }

  // ------------------------------------------------------------------
  // FCM 初期化
  // ------------------------------------------------------------------

  /// FCMの権限要求・トークン取得・フォアグラウンド受信設定を行う。
  /// Android: fcm_token カラム / Web: web_fcm_token カラムにトークンを保存する。
  Future<void> _initFcm() async {
    if (_isFcmInitialized) return;
    _isFcmInitialized = true;

    // バックグラウンドハンドラはネイティブのみ（WebはService Workerが処理）
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    // 通知権限を要求（Android 13+ はOS権限ダイアログ / Webはブラウザ権限ダイアログ）
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('🔕 通知権限が拒否されました');
      return;
    }

    // FCMトークンを取得してSupabaseに保存
    // Web は VAPID 鍵が必須
    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? _kWebVapidKey : null,
      );
      if (token != null) {
        await registerFcmToken(token);
      } else {
        debugPrint('⚠️ FCMトークンがnullです（Service Workerの登録状態を確認してください）');
      }
    } catch (e) {
      debugPrint('❌ FCMトークン取得失敗: $e');
      return;
    }

    // トークンが更新された場合も保存
    FirebaseMessaging.instance.onTokenRefresh.listen(registerFcmToken);

    // フォアグラウンド時の通知表示を有効化（iOS/Androidのみ）
    if (!kIsWeb) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // フォアグラウンド時のメッセージ受信 → アプリ内の未読数をインクリメント
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📲 フォアグラウンド通知受信: ${message.notification?.title}');
      unreadCount.value += 1;
    });

    // 通知タップでアプリが起動した場合
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📲 通知タップでアプリ起動: ${message.notification?.title}');
      // 必要に応じて特定画面への遷移ロジックをここに追加
    });

    debugPrint('✅ FCM初期化完了 (${kIsWeb ? "Web" : "Android"})');
  }

  // ------------------------------------------------------------------
  // Realtime 購読
  // ------------------------------------------------------------------

  Future<void> _subscribeRealtime() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _realtimeChannel?.unsubscribe();

    _realtimeChannel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            // 新着通知が届いたら未読数をインクリメント
            unreadCount.value += 1;
          },
        )
        .subscribe();
  }

  // ------------------------------------------------------------------
  // 未読数
  // ------------------------------------------------------------------

  /// DBから未読数を取得して [unreadCount] を更新する。
  Future<void> refreshUnreadCount() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      unreadCount.value = (response as List).length;
    } catch (e) {
      debugPrint('❌ NotificationService.refreshUnreadCount: $e');
    }
  }

  // ------------------------------------------------------------------
  // 通知一覧取得
  // ------------------------------------------------------------------

  /// 最新50件の通知を取得する。
  Future<List<AppNotification>> fetchNotifications() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List)
          .map((json) => AppNotification.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ NotificationService.fetchNotifications: $e');
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 既読処理
  // ------------------------------------------------------------------

  /// 指定した通知を既読にする。
  Future<void> markAsRead(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);

      if (unreadCount.value > 0) {
        unreadCount.value -= 1;
      }
    } catch (e) {
      debugPrint('❌ NotificationService.markAsRead: $e');
    }
  }

  /// ログインユーザーの全通知を既読にする。
  Future<void> markAllAsRead() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      unreadCount.value = 0;
    } catch (e) {
      debugPrint('❌ NotificationService.markAllAsRead: $e');
    }
  }

  // ------------------------------------------------------------------
  // FCM トークン管理
  // ------------------------------------------------------------------

  /// FCMトークンを再取得してSupabaseに保存する。
  /// マイページのトグルON時に呼び出す。
  Future<void> refreshFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? _kWebVapidKey : null,
      );
      if (token != null) {
        await registerFcmToken(token);
      } else {
        debugPrint('⚠️ FCMトークン再取得: nullが返されました');
      }
    } catch (e) {
      debugPrint('❌ FCMトークン再取得失敗: $e');
    }
  }

  /// FCM デバイストークンを profiles テーブルに保存する。
  /// Android → fcm_token カラム / Web → web_fcm_token カラム
  Future<void> registerFcmToken(String token) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      // 自プラットフォームのトークンを保存し、他プラットフォームのトークンはクリア
      // （同一アカウントで複数プラットフォーム使用時に重複通知を防ぐ）
      await _client
          .from('profiles')
          .update(kIsWeb
              ? {'web_fcm_token': token, 'fcm_token': null}
              : {'fcm_token': token, 'web_fcm_token': null})
          .eq('id', userId);

      debugPrint('✅ FCMトークンを登録しました (${kIsWeb ? "Web" : "Android"})');
    } catch (e) {
      debugPrint('❌ NotificationService.registerFcmToken: $e');
    }
  }

  /// ログアウト時にFCMトークンを削除する（他のデバイスへの誤送信を防ぐ）。
  /// Android → fcm_token カラム / Web → web_fcm_token カラム
  Future<void> clearFcmToken() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      final column = kIsWeb ? 'web_fcm_token' : 'fcm_token';
      await _client
          .from('profiles')
          .update({column: null})
          .eq('id', userId);
    } catch (e) {
      debugPrint('❌ NotificationService.clearFcmToken: $e');
    }
  }
}
