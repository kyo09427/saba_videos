import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'theme_mode';

/// アプリのテーマ（ライト/ダーク/システム）を管理するシングルトンサービス。
///
/// SharedPreferences に永続化し、ValueNotifier で UI に通知する。
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  bool get isDark => themeMode.value == ThemeMode.dark;

  /// アプリ起動時に保存済みのテーマを読み込む。
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeModeKey);
    if (saved == 'light') {
      themeMode.value = ThemeMode.light;
    } else if (saved == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else {
      themeMode.value = ThemeMode.system;
    }
  }

  /// テーマを切り替えて SharedPreferences に保存する。
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    final String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
      case ThemeMode.dark:
        value = 'dark';
      case ThemeMode.system:
        value = 'system';
    }
    await prefs.setString(_kThemeModeKey, value);
  }
}
