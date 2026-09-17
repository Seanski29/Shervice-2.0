import 'package:flutter/material.dart';
import '../../screens/admin/admin_dashboard.dart';
import '../../screens/admin/admin_schedules.dart';
import '../../screens/admin/admin_drivers.dart';
import '../../screens/admin/admin_vehicles.dart';
import '../../screens/admin/admin_users.dart';
import '../../screens/admin/admin_settings.dart';
import '../../login/login.dart';
import '../../widgets/shared/notification_bell.dart';
import '../../widgets/shared/shervice_floating_stack.dart';
import '../../constant.dart';
import '../../session_manager.dart';
import '../../widgets/admin/admin_profile_button.dart';
import '../../widgets/shared/shared_analytics_hub.dart';
import '../../screens/admin/admin_companies.dart';

class AdminMobileLayout extends StatefulWidget {
  final String adminId;
  final String adminName;

  const AdminMobileLayout({
    super.key,
    required this.adminId,
    this.adminName = 'Admin',
  });

  @override
  State<AdminMobileLayout> createState() => _AdminMobileLayoutState();
}

class _AdminMobileLayoutState extends State<AdminMobileLayout> {
  int _selectedIndex = 0;

  late final List<Widget> _screens = [
    const AdminDashboard(),
    const AdminSchedules(),
    const AdminDriver(),
    const AdminFleet(),
    const AdminUsers(),
    const AdminCompanies(),
    const SharedAnalyticsHub(),
    AdminSettings(adminId: widget.adminId),
  ];

  final List<String> _shortTitles = [
    'Overview',
    'Schedules',
    'Drivers',
    'Fleet',
    'Users',
    'Companies',
    'Analytics',
    'Settings',
  ];

  final List<IconData> _icons = [
    Icons.grid_view,
    Icons.calendar_month_outlined,
    Icons.people_outline,
    Icons.directions_car_outlined,
    Icons.admin_panel_settings_outlined,
    Icons.business_outlined,
    Icons.analytics_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SherviceFloatingStack(
      userRole: 'Admin',
      userName: widget.adminName,
      localIp: localIp,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          // Retain Dark Blue in Light Mode, shift to deep slate in Dark Mode
          backgroundColor: isDark
              ? const Color(0xFF0F172A)
              : const Color(0xFF1E3A8A),
          foregroundColor:
              Colors.white, // Forces all icons/text in AppBar to white
          elevation: 0,
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/logo.jpg', fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
              Image.asset(
                'assets/shervice - white.jpg',
                height: 22,
                fit: BoxFit.contain,
              ),
            ],
          ),
          actions: [
            NotificationBell(
              role: 'Admin',
              userId: widget.adminId,
              userName: widget.adminName,
              companyName: '',
              iconSize: 26,
            ),
            const SizedBox(width: 8),
            AdminProfileButton(
              adminId: widget.adminId,
              adminName: widget.adminName,
              compact: true,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.logout, size: 22),
              tooltip: 'Logout',
              onPressed: () => _handleLogout(context, isDark),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _screens[_selectedIndex],
          ),
        ),
        bottomNavigationBar: _buildCustomBottomNav(isDark),
      ),
    );
  }

  Widget _buildCustomBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            width: 1,
          ),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(_screens.length, (index) {
                final isSelected = _selectedIndex == index;
                final selectedColor = isDark
                    ? Colors.blue.shade400
                    : Colors.blue.shade700;
                final unselectedColor = isDark
                    ? Colors.grey.shade500
                    : Colors.grey.shade400;

                return InkWell(
                  onTap: () => setState(() => _selectedIndex = index),
                  splashColor: selectedColor.withValues(alpha: 0.1),
                  highlightColor: Colors.transparent,
                  child: Container(
                    width:
                        MediaQuery.of(context).size.width /
                        5, // Shows 5 items on screen, rest are scrollable
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _icons[index],
                          color: isSelected ? selectedColor : unselectedColor,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _shortTitles[index],
                          style: TextStyle(
                            color: isSelected ? selectedColor : unselectedColor,
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? Colors.grey.shade800 : Colors.transparent,
            ),
          ),
          title: Text(
            'Confirm Logout',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          content: Text(
            'Are you sure you want to log out of your account?',
            style: TextStyle(
              color: isDark ? Colors.grey.shade300 : const Color(0xFF475569),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await SessionManager.clearSession();
                if (!mounted || !dialogContext.mounted) return;
                final navigator = Navigator.of(dialogContext);
                navigator.pop();
                navigator.pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444), // Consistent Red
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}
