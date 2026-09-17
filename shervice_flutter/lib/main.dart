import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'session_manager.dart';
import 'utils/tab_sync_stub.dart'
    if (dart.library.html) 'utils/tab_sync_web.dart';

import 'theme/theme_manager.dart';

// Import layouts and login
import 'layouts/admin/admin_layout.dart';
import 'layouts/driver/driver_layout.dart';
import 'layouts/oic/oic_layout.dart';
import 'layouts/staff/staff_layout.dart';
import 'login/login.dart';

// Global navigator key for cross-app navigation
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await ThemeManager.loadSavedTheme();

  bool loggedIn = await SessionManager.isLoggedIn();
  Map<String, String?> userData = {};

  if (loggedIn) {
    userData = await SessionManager.getUserData();
  }

  runApp(SherviceApp(isLoggedIn: loggedIn, userData: userData));
}

class SherviceApp extends StatefulWidget {
  final bool isLoggedIn;
  final Map<String, String?> userData;

  const SherviceApp({
    super.key,
    required this.isLoggedIn,
    required this.userData,
  });

  @override
  State<SherviceApp> createState() => _SherviceAppState();
}

class _SherviceAppState extends State<SherviceApp> {
  @override
  void initState() {
    super.initState();

    // Calls the web file if on a browser, or the dummy file if on mobile!
    setupTabSync(() {
      globalNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.base;
    final String? testRole = uri.queryParameters['role'];

    Widget getInitialScreen() {
      if (widget.isLoggedIn) {
        final rawRole = widget.userData['role'] ?? '';
        final role = rawRole.trim().toLowerCase();
        final userId = widget.userData['userId'] ?? '';
        final userName = widget.userData['userName'] ?? 'User';
        final company = widget.userData['companyName'] ?? 'GT LANTIN';

        if (role == 'admin') {
          return AdminLayout(adminId: userId, adminName: userName);
        } else if (role == 'oic') {
          return OicLayout(
            oicId: userId,
            oicName: userName,
            companyName: company,
          );
        } else if (role == 'staff') {
          return StaffLayout(
            staffId: userId,
            staffName: userName,
            companyName: company,
          );
        } else if (role == 'driver') {
          return DriverLayout(
            driverId: userId,
            driverName: userName,
            companyName: company,
          );
        }
      }

      // Fallback for URL testing (if needed)
      if (testRole == 'admin') {
        return const AdminLayout(
          adminId: '00000000-0000-0000-0000-000000000000',
        );
      } else if (testRole == 'driver') {
        return const DriverLayout(
          driverId: '00000000-0000-0000-0000-000000000000',
          driverName: 'System Driver',
          companyName: 'Test Company',
        );
      }

      return const LoginScreen();
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeManager.themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          navigatorKey: globalNavigatorKey,
          title: 'Shervice Portal',
          debugShowCheckedModeBanner: false,

          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            cardColor: Colors.white,
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
            cardTheme: const CardThemeData(color: Colors.white),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E293B),
              foregroundColor: Colors.white,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF60A5FA),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            cardColor: const Color(0xFF1E293B),
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Color(0xFF1E293B),
              border: OutlineInputBorder(),
              labelStyle: TextStyle(color: Color(0xFFCBD5E1)),
              hintStyle: TextStyle(color: Color(0xFF94A3B8)),
            ),
            cardTheme: const CardThemeData(color: Color(0xFF1E293B)),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Colors.white),
              bodyMedium: TextStyle(color: Colors.white),
              bodySmall: TextStyle(color: Color(0xFFCBD5E1)),
              titleLarge: TextStyle(color: Colors.white),
              titleMedium: TextStyle(color: Colors.white),
              titleSmall: TextStyle(color: Colors.white),
              headlineSmall: TextStyle(color: Colors.white),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E293B),
              foregroundColor: Colors.white,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF1E293B),
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1E293B),
            ),
            dropdownMenuTheme: const DropdownMenuThemeData(
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Color(0xFF1E293B),
              ),
            ),
            useMaterial3: true,
          ),
          themeMode: currentMode,
          home: getInitialScreen(),
        );
      },
    );
  }
}
