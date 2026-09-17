// lib/utils/theme_manager.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager {
  ThemeManager._();

  static final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static ThemeMode get themeMode => themeNotifier.value;

  static bool get isDark => themeMode == ThemeMode.dark;

  static Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getBool('darkMode') ?? true;
    themeNotifier.value = savedMode ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> setDarkMode(bool enabled) async {
    themeNotifier.value = enabled ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', enabled);
  }

  static Future<void> toggleTheme() async {
    await setDarkMode(!isDark);
  }
}
