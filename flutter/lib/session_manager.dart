import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const Duration sessionLifetime = Duration(days: 7);
  static const String _sessionCreatedAtKey = 'sessionCreatedAt';

  // Save user data when they log in
  static Future<void> saveUserSession(
    String role,
    String userId,
    String name,
    String company,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
    await prefs.setString('userId', userId);
    await prefs.setString('userName', name);
    await prefs.setString('companyName', company);
    await prefs.setInt(
      _sessionCreatedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setBool('isLoggedIn', true);
  }

  // Check if someone is currently logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('isLoggedIn') ?? false)) return false;

    final createdAtMillis = prefs.getInt(_sessionCreatedAtKey);
    if (createdAtMillis == null) {
      await clearSession();
      return false;
    }

    final sessionAge = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
    if (sessionAge >= sessionLifetime || sessionAge.isNegative) {
      await clearSession();
      return false;
    }

    return true;
  }

  // Fetch the saved user data
  static Future<Map<String, String?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'role': prefs.getString('role'),
      'userId': prefs.getString('userId'),
      'userName': prefs.getString('userName'),
      'companyName': prefs.getString('companyName'),
    };
  }

  // Clear session on logout
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('role');
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('companyName');
    await prefs.remove('isLoggedIn');
    await prefs.remove(_sessionCreatedAtKey);
  }
}
