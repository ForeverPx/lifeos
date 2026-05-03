import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selected appearance; persisted locally.
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode? fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in AppThemeMode.values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  ThemeMode get themeMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

/// Loads and persists [AppThemeMode]; [notifier] drives root [MaterialApp] rebuilds.
abstract final class ThemePrefs {
  static const _key = 'app_theme_mode';

  static final ValueNotifier<AppThemeMode> notifier =
      ValueNotifier(AppThemeMode.system);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final stored = AppThemeMode.fromStorage(p.getString(_key));
    notifier.value = stored ?? AppThemeMode.system;
  }

  static Future<void> set(AppThemeMode mode) async {
    notifier.value = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, mode.name);
  }
}
