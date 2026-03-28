import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';
import 'supabase_service.dart';

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
///   - FCM トークンの取得・Supabase への保存
///   - フォアグラウンド時の FCM メッセージ受信
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// 未読通知数。UI側は ValueListenableBuilder でリッスンする。
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  RealtimeChannel? _realtimeChannel;

  // ------------------------------------------------------------------
  // 初期化 / 破棄
  // ------------------------------------------------------------------

  /// ログイン後に呼び出す。
  /// 未読数取得・Realtime購読・FCM初期化を行う。
  Future<void> initialize() async {
    await refreshUnreadCount();
    _subscribeRealtime();
    await _initFcm();
  }

  /// ログアウト時に呼び出す。購読を解除し未読数をリセットする。
  Future<void> dispose() async {
    await _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    unreadCount.value = 0;
  }

  // ------------------------------------------------------------------
  // FCM 初期化
  // ------------------------------------------------------------------

  /// FCMの権限要求・トークン取得・フォアグラウンド受信設定を行う。
  Future<void> _initFcm() async {
    // Web は Android 対応完了後に別途実装予定のためスキップ
    if (kIsWeb) return;

    // バックグラウンドハンドラを登録（アプリ起動前に設定する必要がある）
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 通知権限を要求（Android 13+ / iOS）
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
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await registerFcmToken(token);
    }

    // トークンが更新された場合も保存
    FirebaseMessaging.instance.onTokenRefresh.listen(registerFcmToken);

    // フォアグラウンド時の通知表示を有効化
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

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
  }

  // ------------------------------------------------------------------
  // Realtime 購読
  // ------------------------------------------------------------------

  void _subscribeRealtime() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeChannel?.unsubscribe();

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

  /// FCM デバイストークンを profiles テーブルに保存する。
  Future<void> registerFcmToken(String token) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);

      debugPrint('✅ FCMトークンを登録しました');
    } catch (e) {
      debugPrint('❌ NotificationService.registerFcmToken: $e');
    }
  }

  /// ログアウト時にFCMトークンを削除する（他のデバイスへの誤送信を防ぐ）。
  Future<void> clearFcmToken() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client
          .from('profiles')
          .update({'fcm_token': null})
          .eq('id', userId);
    } catch (e) {
      debugPrint('❌ NotificationService.clearFcmToken: $e');
    }
  }
}
