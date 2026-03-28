import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/post/post_video_screen.dart';
import '../screens/profile/my_page_screen.dart';
import '../screens/subscriptions/subscriptions_screen.dart';
import '../screens/timeline/timeline_screen.dart';

/// 共通のボトムナビゲーションバー
class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
  });

  // デザイン用カラー定義
  static const Color _ytBackground = Color(0xFF0F0F0F);
  static const Color _ytSurface = Color(0xFF272727);
  static const Color _textWhite = Colors.white;

  void _onItemTapped(BuildContext context, int index) {
    // 現在のページと同じ場合は何もしない
    if (index == currentIndex) return;

    switch (index) {
      case 0: // ホーム
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;
      case 1: // タイムライン
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TimelineScreen()),
        );
        break;
      case 2: // 投稿
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PostVideoScreen()),
        );
        break;
      case 3: // 登録チャンネル
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SubscriptionsScreen()),
        );
        break;
      case 4: // マイページ
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MyPageScreen()),
        );
        break;
    }
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
    VoidCallback? onTap,
  }) {
    final isActive = index == currentIndex;
    
    return InkWell(
      onTap: onTap ?? () => _onItemTapped(context, index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: _textWhite,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: _textWhite,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _ytBackground,
        border: Border(top: BorderSide(color: _ytSurface, width: 0.5)),
      ),
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context: context,
            icon: Icons.home_filled,
            label: 'ホーム',
            index: 0,
          ),
          _buildNavItem(
            context: context,
            icon: Icons.timeline,
            label: 'タイムライン',
            index: 1,
          ),
          // 投稿ボタン（中央）
          InkWell(
            onTap: () => _onItemTapped(context, 2),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1),
                color: _ytSurface.withValues(alpha: 0.5),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
          _buildNavItem(
            context: context,
            icon: Icons.subscriptions_outlined,
            label: '登録チャンネル',
            index: 3,
          ),
          _buildNavItem(
            context: context,
            icon: Icons.account_circle_outlined,
            label: 'マイページ',
            index: 4,
          ),
        ],
      ),
    );
  }
}