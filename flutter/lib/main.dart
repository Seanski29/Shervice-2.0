import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/session_manager.dart';
import 'utils/tab_sync_stub.dart'
    if (dart.library.html) 'utils/tab_sync_web.dart';

import 'theme/theme_manager.dart';
import 'theme/enterprise_theme.dart';

// Import layouts and login
import 'layouts/admin/admin_layout.dart';
import 'layouts/staff/staff_layout.dart';
import 'login/login.dart';

// Global navigator key for cross-app navigation
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  // Browser plugins can publish lifecycle events before WidgetsBinding attaches
  // its listener. Keep those early events instead of dropping them.
  ServicesBinding.instance.channelBuffers.resize(
    SystemChannels.lifecycle.name,
    10,
  );
  usePathUrlStrategy();

  bool loggedIn = await SessionManager.isLoggedIn();
  Map<String, String?> userData = {};

  if (loggedIn) {
    userData = await SessionManager.getUserData();
  }

  await ThemeManager.loadSavedTheme(userId: userData['userId']);

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
        } else if (role == 'staff') {
          return StaffLayout(
            staffId: userId,
            staffName: userName,
            companyName: company,
          );
        }
      }

      // Fallback for URL testing (if needed)
      if (testRole == 'admin') {
        return const AdminLayout(
          adminId: '00000000-0000-0000-0000-000000000000',
        );
      } else if (testRole == 'staff') {
        return const StaffLayout(
          staffId: '00000000-0000-0000-0000-000000000000',
          staffName: 'System Staff',
          companyName: 'GT LANTIN',
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

          theme: EnterpriseTheme.light(),
          darkTheme: EnterpriseTheme.dark(),
          themeMode: currentMode,
          home: getInitialScreen(),
        );
      },
    );
  }
}
