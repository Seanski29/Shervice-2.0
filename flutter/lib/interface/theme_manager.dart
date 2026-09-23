// lib/utils/theme_manager.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager {
  ThemeManager._();

  static const String _legacyPreferenceKey = 'darkMode';
  static const String _guestPreferenceKey = 'theme.darkMode.guest';
  static const String _accountPreferencePrefix = 'theme.darkMode.account.';
  static String? _activeUserId;

  static final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static ThemeMode get themeMode => themeNotifier.value;

  static bool get isDark => themeMode == ThemeMode.dark;

  static String _preferenceKey(String? userId) {
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      return _guestPreferenceKey;
    }
    return '$_accountPreferencePrefix$normalizedUserId';
  }

  static Future<void> loadSavedTheme({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedUserId = userId?.trim();
    _activeUserId = normalizedUserId == null || normalizedUserId.isEmpty
        ? null
        : normalizedUserId;

    final preferenceKey = _preferenceKey(_activeUserId);
    var savedMode = prefs.getBool(preferenceKey);

    // Preserve the existing installation-wide choice once during migration.
    if (savedMode == null && prefs.containsKey(_legacyPreferenceKey)) {
      savedMode = prefs.getBool(_legacyPreferenceKey);
      if (savedMode != null) {
        await prefs.setBool(preferenceKey, savedMode);
        await prefs.remove(_legacyPreferenceKey);
      }
    }

    // Light mode is the safe default for first-time users. An explicit saved
    // preference still takes precedence for returning users.
    savedMode ??= false;
    themeNotifier.value = savedMode ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> setDarkMode(bool enabled) async {
    themeNotifier.value = enabled ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey(_activeUserId), enabled);
  }

  static Future<void> toggleTheme() async {
    await setDarkMode(!isDark);
  }
}
