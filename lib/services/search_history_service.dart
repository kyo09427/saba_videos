import 'package:shared_preferences/shared_preferences.dart';

/// 検索履歴をローカル（SharedPreferences）で管理するサービス
class SearchHistoryService {
  static const String _key = 'search_history';
  static const int _maxHistory = 20; // 履歴の最大保持件数

  SearchHistoryService._();
  static final SearchHistoryService instance = SearchHistoryService._();

  /// 検索履歴を取得
  Future<List<String>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// 検索履歴を追加
  Future<void> addSearchQuery(String query) async {
    final sanitizedQuery = query.trim();
    if (sanitizedQuery.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_key)?.toList() ?? [];

    // 重複がある場合は一度削除（最新として先頭に持ってくるため）
    history.remove(sanitizedQuery);
    // 先頭に追加
    history.insert(0, sanitizedQuery);

    // 最大件数を超えた部分を切り捨て
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }

    await prefs.setStringList(_key, history);
  }

  /// 特定の検索履歴を削除
  Future<void> removeSearchQuery(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_key)?.toList() ?? [];
    
    if (history.remove(query)) {
      await prefs.setStringList(_key, history);
    }
  }

  /// 検索履歴をすべて削除
  Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
