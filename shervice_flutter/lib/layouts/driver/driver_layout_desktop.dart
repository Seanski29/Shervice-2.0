import 'package:flutter/material.dart';
import '../../constant.dart';
import '../../login/login.dart';
import '../../screens/driver/driver_dashboard.dart';
import '../../screens/driver/driver_profile.dart';
import '../../screens/driver/driver_schedules.dart';
import '../../session_manager.dart';
import '../../widgets/shared/notification_bell.dart';
import '../../widgets/shared/shervice_floating_stack.dart';
import '../../widgets/shared/user_profile_button.dart';

class DriverLayoutDesktop extends StatefulWidget {
  final String driverId;
  final String driverName;
  final String companyName;

  const DriverLayoutDesktop({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.companyName,
  });

  @override
  State<DriverLayoutDesktop> createState() => _DriverLayoutDesktopState();
}

class _DriverLayoutDesktopState extends State<DriverLayoutDesktop> {
  int _selectedIndex = 0;

  late final List<Widget> _screens = [
    DriverDashboard(driverName: widget.driverName, driverId: widget.driverId),
    DriverSchedules(driverId: widget.driverId),
    DriverProfile(driverName: widget.driverName, driverId: widget.driverId),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SherviceFloatingStack(
      userRole: 'Driver',
      userName: widget.driverName,
      localIp: localIp,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 28,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset('assets/logo.jpg', fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Text(
                'Mission Control',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                ),
              ),
            ],
          ),
          actions: [
            NotificationBell(
              role: 'Driver',
              userId: widget.driverId,
              userName: widget.driverName,
              companyName: widget.companyName,
              iconSize: 25,
            ),
            const SizedBox(width: 12),
            UserProfileButton(
              name: widget.driverName,
              role: 'Driver',
              company: widget.companyName,
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 28),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: _screens[_selectedIndex],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(isDark),
      ),
    );
  }

  Widget _buildBottomNavigationBar(bool isDark) {
    final selected = const Color(0xFF2563EB);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? .22 : .06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: NavigationBar(
          height: 72,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: selected.withValues(alpha: .16),
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Schedule',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () async {
              await SessionManager.clearSession();
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
