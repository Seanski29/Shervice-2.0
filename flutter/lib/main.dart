import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/session_manager.dart';
import 'utilities/tab_sync_stub.dart'
    if (dart.library.html) 'utilities/tab_sync_web.dart';

import 'interface/theme_manager.dart';
import 'layouts/enterprise/enterprise_theme.dart';

import 'login/login.dart';
import 'layouts/admin/admin_layout.dart' deferred as admin_layout;
import 'layouts/staff/staff_layout.dart' deferred as staff_layout;

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
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();

    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!await SessionManager.isLoggedIn() && mounted) {
        globalNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });

    // Calls the web file if on a browser, or the dummy file if on mobile!
    setupTabSync(() {
      globalNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
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
          return _DeferredWorkspaceScreen(
            role: role,
            userId: userId,
            userName: userName,
            companyName: company,
          );
        } else if (role == 'staff') {
          return _DeferredWorkspaceScreen(
            role: role,
            userId: userId,
            userName: userName,
            companyName: company,
          );
        }
      }

      // Fallback for URL testing (if needed)
      if (testRole == 'admin') {
        return const _DeferredWorkspaceScreen(
          role: 'admin',
          userId: '00000000-0000-0000-0000-000000000000',
          userName: 'Admin',
        );
      } else if (testRole == 'staff') {
        return const _DeferredWorkspaceScreen(
          role: 'staff',
          userId: '00000000-0000-0000-0000-000000000000',
          userName: 'System Staff',
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
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final clampedScale = mediaQuery.textScaler
                .scale(1)
                .clamp(0.85, 1.05)
                .toDouble();
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(clampedScale),
              ),
              child: ScrollConfiguration(
                behavior: const _SherviceScrollBehavior(),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: getInitialScreen(),
        );
      },
    );
  }
}

class _SherviceScrollBehavior extends MaterialScrollBehavior {
  const _SherviceScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _DeferredWorkspaceScreen extends StatefulWidget {
  const _DeferredWorkspaceScreen({
    required this.role,
    required this.userId,
    required this.userName,
    this.companyName = 'GT LANTIN',
  });

  final String role;
  final String userId;
  final String userName;
  final String companyName;

  @override
  State<_DeferredWorkspaceScreen> createState() =>
      _DeferredWorkspaceScreenState();
}

class _DeferredWorkspaceScreenState extends State<_DeferredWorkspaceScreen> {
  late final Future<Widget> _screen = _loadScreen();

  Future<Widget> _loadScreen() async {
    if (widget.role == 'admin') {
      await admin_layout.loadLibrary();
      return admin_layout.AdminLayout(
        adminId: widget.userId,
        adminName: widget.userName,
      );
    }

    await staff_layout.loadLibrary();
    return staff_layout.StaffLayout(
      staffId: widget.userId,
      staffName: widget.userName,
      companyName: widget.companyName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _screen,
      builder: (context, snapshot) {
        if (snapshot.hasData) return snapshot.data!;
        return const Scaffold(
          body: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        );
      },
    );
  }
}
