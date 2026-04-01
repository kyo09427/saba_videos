import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// デザイントークン（各スクリーンと統一）
// ─────────────────────────────────────────────────────────────
const Color _kBackground = Color(0xFF0F0F0F);
const Color _kSurface = Color(0xFF272727);
const Color _kSurfaceLight = Color(0xFF3A3A3A);

// ─────────────────────────────────────────────────────────────
// 共有シマーアニメーション（InheritedWidget）
// リスト内の全 SkeletonBox が1つの AnimationController を共有し
// CPU・GPU 負荷を大幅に削減する。
// ─────────────────────────────────────────────────────────────

class _ShimmerScope extends InheritedWidget {
  final Animation<double> animation;

  const _ShimmerScope({required this.animation, required super.child});

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  bool updateShouldNotify(_ShimmerScope old) => false;
}

class _ShimmerProvider extends StatefulWidget {
  final Widget child;

  const _ShimmerProvider({required this.child});

  @override
  State<_ShimmerProvider> createState() => _ShimmerProviderState();
}

class _ShimmerProviderState extends State<_ShimmerProvider>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ShimmerScope(animation: _animation, child: widget.child);
}

// ─────────────────────────────────────────────────────────────
// SkeletonBase：シマーアニメーションの基底ウィジェット
// ─────────────────────────────────────────────────────────────

/// シマーアニメーション付きのベースウィジェット
///
/// 指定した [width] × [height] の矩形または角丸矩形を
/// グラデーションアニメーションで描画します。
/// 祖先に [_ShimmerProvider] がある場合はそのアニメーションを共有します。
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final animation = _ShimmerScope.of(context);
    if (animation == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: _kSurface,
        ),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment(animation.value - 1, 0),
            end: Alignment(animation.value + 1, 0),
            colors: const [_kSurface, _kSurfaceLight, _kSurface],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SkeletonVideoCardLarge：ホーム画面用（大きいサムネイル + 情報）
// ─────────────────────────────────────────────────────────────

/// ホーム画面の動画カード用スケルトン
class SkeletonVideoCardLarge extends StatelessWidget {
  const SkeletonVideoCardLarge({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // サムネイル（16:9）
        AspectRatio(
          aspectRatio: 16 / 9,
          child: SkeletonBox(width: double.infinity, borderRadius: 0),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // アバター
              const SkeletonBox(width: 36, height: 36, borderRadius: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // タイトル行1
                    SkeletonBox(width: double.infinity, height: 14),
                    const SizedBox(height: 6),
                    // タイトル行2
                    SkeletonBox(
                      width: MediaQuery.of(context).size.width * 0.6,
                      height: 14,
                    ),
                    const SizedBox(height: 8),
                    // チャンネル名 + 日時
                    SkeletonBox(
                      width: MediaQuery.of(context).size.width * 0.45,
                      height: 11,
                    ),
                    const SizedBox(height: 6),
                    // カテゴリバッジ
                    const SkeletonBox(width: 48, height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SkeletonVideoCardSmall：タイムライン・チャンネル・マイ動画用
// ─────────────────────────────────────────────────────────────

/// 横並びレイアウト（サムネイル左 + 情報右）のスケルトン
class SkeletonVideoCardSmall extends StatelessWidget {
  const SkeletonVideoCardSmall({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // サムネイル
          const SkeletonBox(width: 160, height: 90, borderRadius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タイトル行1
                SkeletonBox(width: double.infinity, height: 14),
                const SizedBox(height: 6),
                // タイトル行2
                SkeletonBox(
                  width: MediaQuery.of(context).size.width * 0.4,
                  height: 14,
                ),
                const SizedBox(height: 10),
                // チャンネル名
                const SkeletonBox(width: 100, height: 11),
                const SizedBox(height: 6),
                // 日時
                const SkeletonBox(width: 80, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SkeletonChannelHeader：チャンネル詳細画面のヘッダー用
// ─────────────────────────────────────────────────────────────

/// チャンネル詳細画面のプロフィールヘッダー用スケルトン
class SkeletonChannelHeader extends StatelessWidget {
  const SkeletonChannelHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // アバター（大）
              const SkeletonBox(width: 80, height: 80, borderRadius: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // チャンネル名
                    SkeletonBox(
                      width: MediaQuery.of(context).size.width * 0.4,
                      height: 22,
                    ),
                    const SizedBox(height: 8),
                    // 登録者数
                    const SkeletonBox(width: 140, height: 12),
                    const SizedBox(height: 6),
                    // プロフィール文
                    SkeletonBox(
                      width: MediaQuery.of(context).size.width * 0.5,
                      height: 11,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 登録ボタン
          SkeletonBox(width: double.infinity, height: 44, borderRadius: 22),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SkeletonListView：スケルトンカードのリスト表示
// ─────────────────────────────────────────────────────────────

/// 複数のスケルトンカードをまとめて表示するウィジェット
/// 単一の [_ShimmerProvider] で全アイテムのアニメーションを共有します。
class SkeletonListView extends StatelessWidget {
  final Widget Function() itemBuilder;
  final int itemCount;
  final Color? backgroundColor;

  const SkeletonListView({
    super.key,
    required this.itemBuilder,
    this.itemCount = 4,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return _ShimmerProvider(
      child: Container(
        color: backgroundColor ?? _kBackground,
        child: Column(
          children: List.generate(itemCount, (_) => itemBuilder()),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SkeletonSliverList：Sliver配下でスケルトンカードのリスト表示
// ─────────────────────────────────────────────────────────────

/// CustomScrollView内で使えるスケルトンSliverList
/// [_ShimmerProvider] で全アイテムのアニメーションを共有します。
class SkeletonSliverList extends StatelessWidget {
  final Widget Function() itemBuilder;
  final int itemCount;

  const SkeletonSliverList({
    super.key,
    required this.itemBuilder,
    this.itemCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: _ShimmerProvider(
        child: Column(
          children: List.generate(itemCount, (_) => itemBuilder()),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SkeletonPlaylistCard：プレイリストタブのグリッドカード用
// ─────────────────────────────────────────────────────────────

/// プレイリストグリッドカード用スケルトン
class SkeletonPlaylistCard extends StatelessWidget {
  const SkeletonPlaylistCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // サムネイル（16:9）
        AspectRatio(
          aspectRatio: 16 / 9,
          child: SkeletonBox(width: double.infinity, borderRadius: 8),
        ),
        const SizedBox(height: 8),
        // プレイリスト名
        const SkeletonBox(width: double.infinity, height: 13),
        const SizedBox(height: 5),
        // 動画本数バッジ
        const SkeletonBox(width: 70, height: 11),
      ],
    );
  }
}

/// プレイリスト用スケルトン（2列グリッド）を Sliver で表示
/// [_ShimmerProvider] で全アイテムのアニメーションを共有します。
class SkeletonPlaylistSliverGrid extends StatelessWidget {
  final int itemCount;

  const SkeletonPlaylistSliverGrid({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _ShimmerProvider(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: itemCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (_, _) => const SkeletonPlaylistCard(),
          ),
        ),
      ),
    );
  }
}
