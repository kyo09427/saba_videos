import 'package:flutter/material.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/search/search_screen.dart';
import '../services/notification_service.dart';

/// スマホ・タブレット版共通上部バー
///
/// ホーム画面と同じロゴ・キャスト・通知・検索アイコンを他画面で再利用するための
/// ヘルパークラス。SliverAppBar の title / actions に渡して使う。
class AppMobileTopBar {
  static const Color _ytRed = Color(0xFFF20D0D);

  /// ロゴタイトル（SabaTube アイコン＋テキスト）
  static Widget buildTitle(BuildContext context) {
    final textWhite = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Image.asset('icon.png', height: 30),
          const SizedBox(width: 4),
          Text(
            'SabaTube',
            style: TextStyle(
              color: textWhite,
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  /// アクションボタン（キャスト・通知バッジ付き・検索）
  static List<Widget> buildActions(BuildContext context) {
    final textWhite = Theme.of(context).colorScheme.onSurface;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return [
      // キャスト
      IconButton(
        icon: const Icon(Icons.cast),
        color: textWhite,
        onPressed: () {},
      ),
      // 通知（未読バッジ付き）
      ValueListenableBuilder<int>(
        valueListenable: NotificationService.instance.unreadCount,
        builder: (context, count, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                color: textWhite,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              if (count > 0)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _ytRed,
                      border: Border.all(color: bg, width: 1.5),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      // 検索（SearchScreen に遷移）
      IconButton(
        icon: const Icon(Icons.search),
        color: textWhite,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SearchScreen(),
            ),
          );
        },
      ),
    ];
  }
}
