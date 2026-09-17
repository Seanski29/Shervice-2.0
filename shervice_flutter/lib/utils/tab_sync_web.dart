// lib/utils/tab_sync_web.dart
import 'dart:html' as html;
import 'package:shared_preferences/shared_preferences.dart';

void setupTabSync(Function onLogout) {
  html.window.onStorage.listen((html.StorageEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    bool isStillLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (!isStillLoggedIn) {
      onLogout(); // Triggers the logout in main.dart
    }
  });
}