import 'package:flutter/material.dart';
import '../../screens/driver/driver_dashboard.dart';
import '../../screens/driver/driver_schedules.dart';
import '../../screens/driver/driver_profile.dart';
import '../../login/login.dart';
import '../../widgets/shared/notification_bell.dart';
import '../../widgets/shared/shervice_floating_stack.dart';
import '../../constant.dart';
import '../../session_manager.dart';

class DriverLayoutMobile extends StatefulWidget {
  final String driverId;
  final String driverName;
  final String companyName;

  const DriverLayoutMobile({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.companyName,
  });

  @override
  State<DriverLayoutMobile> createState() => _DriverLayoutMobileState();
}

class _DriverLayoutMobileState extends State<DriverLayoutMobile> {
  int _selectedIndex = 0;

  late final List<Widget> _screens = [
    DriverDashboard(driverName: widget.driverName, driverId: widget.driverId),
    DriverSchedules(driverId: widget.driverId),
    DriverProfile(driverName: widget.driverName, driverId: widget.driverId),
  ];

  final List<String> _titles = ['Dashboard', 'Schedule', 'Profile'];
  final List<IconData> _icons = [
    Icons.dashboard_outlined,
    Icons.calendar_month_outlined,
    Icons.person_outline,
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
          // Retain Dark Blue in Light Mode, shift to deep slate in Dark Mode
          backgroundColor: isDark
              ? const Color(0xFF0F172A)
              : const Color(0xFF1E3A8A),
          foregroundColor:
              Colors.white, // Forces all icons/text in AppBar to white
          elevation: 0,
          centerTitle: true,
          titleSpacing: 0,
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
              const SizedBox(width: 6),
              Flexible(
                child: Image.asset(
                  'assets/shervice - white.jpg',
                  height: 20,
                  fit: BoxFit.contain,
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
              iconSize: 24,
            ),
            IconButton(
              icon: const Icon(Icons.logout, size: 20),
              tooltip: 'Logout',
              onPressed: () => _confirmLogout(context, isDark),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(child: _screens[_selectedIndex]),
        bottomNavigationBar: _buildBottomNav(isDark),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
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
          height: 68,
          child: Row(
            children: List.generate(_titles.length, (index) {
              final isSelected = _selectedIndex == index;
              final selectedColor = isDark
                  ? Colors.blue.shade400
                  : Colors.blue.shade700;
              final unselectedColor = isDark
                  ? Colors.grey.shade500
                  : Colors.grey.shade400;

              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedIndex = index),
                  splashColor: selectedColor.withValues(alpha: 0.1),
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _icons[index],
                        color: isSelected ? selectedColor : unselectedColor,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Flexible(
                        child: Text(
                          _titles[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? selectedColor : unselectedColor,
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444), // Consistent Red
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              await SessionManager.clearSession();
              if (!mounted || !ctx.mounted) return;
              final navigator = Navigator.of(ctx);
              navigator.pop();
              navigator.pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
