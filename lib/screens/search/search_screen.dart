import 'package:flutter/material.dart';
import '../../services/search_history_service.dart';

/// 検索入力および履歴表示を行う専用画面
class SearchScreen extends StatefulWidget {
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late TextEditingController _searchController;
  List<String> _history = [];
  bool _isLoading = true;
  bool _hasText = false;

  // テーマカラー（ホーム画面と統一）
  final Color _ytBackground = const Color(0xFF0F0F0F);
  final Color _ytSurface = const Color(0xFF272727);
  final Color _textWhite = Colors.white;
  final Color _textGray = const Color(0xFFAAAAAA);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _hasText = widget.initialQuery.isNotEmpty;
    
    // 入力欄の変更を監視して×ボタンの表示/非表示を切り替え
    _searchController.addListener(() {
      final hasText = _searchController.text.isNotEmpty;
      if (_hasText != hasText) {
        setState(() => _hasText = hasText);
      }
    });

    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 履歴を読み込む
  Future<void> _loadHistory() async {
    final history = await SearchHistoryService.instance.getSearchHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  /// 検索を実行して前の画面に戻る
  void _executeSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      await SearchHistoryService.instance.addSearchQuery(trimmed);
    }
    // 検索結果（キーワード）を持って元の画面に戻る
    if (mounted) {
      Navigator.of(context).pop(trimmed);
    }
  }

  /// 履歴を削除する
  Future<void> _removeHistory(String query) async {
    await SearchHistoryService.instance.removeSearchQuery(query);
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    // ダークモードかどうかを判定して色を調整
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final bgColor = isDark ? _ytBackground : Colors.white;
    final surfaceColor = isDark ? _ytSurface : Colors.grey.shade200;
    final textColor = isDark ? _textWhite : Colors.black87;
    final subtleIconColor = isDark ? _textWhite : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        // 丸みを帯びた検索入力バー
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: textColor, fontSize: 16),
            cursorColor: isDark ? _textWhite : Colors.black87,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'タイトル・カテゴリ・タグを検索',
              hintStyle: TextStyle(color: isDark ? _textGray : Colors.grey, fontSize: 15),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              isDense: true,
              // 入力された文字があるときだけ×ボタンを表示
              suffixIcon: _hasText
                  ? IconButton(
                      icon: Icon(Icons.close, color: textColor, size: 20),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
            ),
            onSubmitted: _executeSearch,
          ),
        ),
        actions: [
          // マイクアイコン（UI上のダミー）
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: surfaceColor,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.mic, color: textColor, size: 22),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final query = _history[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  // 左の時計アイコン
                  leading: Icon(Icons.history, color: subtleIconColor, size: 26),
                  // 履歴テキスト
                  title: Text(
                    query,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  // 右の上向き矢印（テキストフィールドに入力するだけ。検索はしない）
                  trailing: IconButton(
                    icon: Icon(Icons.north_west, color: subtleIconColor, size: 24),
                    onPressed: () {
                      _searchController.text = query;
                      _searchController.selection = TextSelection.fromPosition(
                        TextPosition(offset: query.length),
                      );
                    },
                  ),
                  // タップで即時検索
                  onTap: () => _executeSearch(query),
                  // 長押しで個別履歴削除
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: isDark ? _ytSurface : Colors.white,
                        title: Text('履歴から削除しますか？', style: TextStyle(color: textColor)),
                        content: Text('「$query」を検索履歴から削除します。',
                            style: TextStyle(color: isDark ? _textGray : Colors.black87)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _removeHistory(query);
                            },
                            child: const Text('削除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
