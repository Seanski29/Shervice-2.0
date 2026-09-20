import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const Duration sessionLifetime = Duration(days: 7);
  static const String _sessionCreatedAtKey = 'sessionCreatedAt';

  static Future<void> saveUserSession(
    String role,
    String userId,
    String name,
    String company,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('role', role),
      prefs.setString('userId', userId),
      prefs.setString('userName', name),
      prefs.setString('companyName', company),
      prefs.setInt(_sessionCreatedAtKey, DateTime.now().millisecondsSinceEpoch),
      prefs.setBool('isLoggedIn', true),
    ]);
  }

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

  static Future<Map<String, String?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'role': prefs.getString('role'),
      'userId': prefs.getString('userId'),
      'userName': prefs.getString('userName'),
      'companyName': prefs.getString('companyName'),
    };
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('role'),
      prefs.remove('userId'),
      prefs.remove('userName'),
      prefs.remove('companyName'),
      prefs.remove('isLoggedIn'),
      prefs.remove(_sessionCreatedAtKey),
    ]);
  }
}
