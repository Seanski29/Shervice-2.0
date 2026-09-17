import 'package:flutter/material.dart';
import '../../screens/staff/staff_dashboard.dart';
import '../../screens/staff/staff_vehicle.dart';
import '../../screens/staff/staff_schedules.dart';
import '../../screens/staff/staff_trips.dart';
import '../../screens/staff/staff_drivers.dart';
import '../../screens/staff/staff_reports_manager.dart';
import '../../widgets/shared/shared_analytics_hub.dart';
import '../../login/login.dart';
import '../../screens/staff/staff_settings.dart';
import '../../widgets/shared/notification_bell.dart';
import '../../widgets/shared/shervice_floating_stack.dart';
import '../../constant.dart';
import '../../session_manager.dart';
import '../../widgets/staff/staff_profile_button.dart';

class StaffLayoutDesktop extends StatefulWidget {
  final String staffId;
  final String staffName;
  final String companyName;

  const StaffLayoutDesktop({
    super.key,
    required this.staffId,
    required this.companyName,
    this.staffName = 'Staff',
  });

  @override
  State<StaffLayoutDesktop> createState() => _StaffLayoutDesktopState();
}

class _StaffLayoutDesktopState extends State<StaffLayoutDesktop> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    _screens = [
      StaffDashboard(
        staffName: widget.staffName,
        companyName: widget.companyName,
      ),
      StaffSchedules(staffId: widget.staffId),
      StaffTrips(staffId: widget.staffId),
      StaffVehicle(staffId: widget.staffId),
      const StaffDrivers(),
      const StaffReportsManager(),
      SharedAnalyticsHub(),
      StaffSettings(
        staffId: widget.staffId,
        staffName: widget.staffName,
        companyName: widget.companyName,
      ),
    ];
  }

  void _toggleSidebar() {
    setState(() => _isSidebarExpanded = !_isSidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SherviceFloatingStack(
      userRole: 'Staff',
      userName: widget.staffName,
      localIp: localIp,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Row(
          children: [
            _buildSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(child: _screens[_selectedIndex]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _isSidebarExpanded ? 260 : 76,
      color: const Color(0xFF1E293B),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/logo.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.directions_car,
                          color: Colors.blue,
                          size: 24,
                        ),
                      );
                    },
                  ),
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/shervice - white.jpg',
                          height: 25,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          errorBuilder: (context, error, stackTrace) {
                            return const Text(
                              'SHERVICE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Staff Portal',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white70),
                    onPressed: _toggleSidebar,
                    tooltip: 'Collapse',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildNavItem(0, 'Dashboard', Icons.dashboard),
                _buildNavItem(
                  1,
                  'Trip Assignment',
                  Icons.calendar_month_outlined,
                ),
                _buildNavItem(2, 'Trip History', Icons.assignment_turned_in),
                _buildNavItem(
                  3,
                  'Vehicle Management',
                  Icons.directions_car_outlined,
                ),
                _buildNavItem(4, 'Driver Records', Icons.people_outline),
                _buildNavItem(
                  5,
                  'Import & Export',
                  Icons.import_export_outlined,
                ),
                _buildNavItem(6, 'Analytics', Icons.analytics),
                _buildNavItem(7, 'Settings', Icons.settings_outlined),
              ],
            ),
          ),

          const Divider(color: Colors.white10, thickness: 1, height: 1),
          _buildNavItem(99, 'Log Out', Icons.logout, isLogout: true),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String title,
    IconData icon, {
    bool isLogout = false,
  }) {
    bool isActive = _selectedIndex == index && !isLogout;
    return InkWell(
      onTap: () =>
          isLogout ? _confirmLogout() : setState(() => _selectedIndex = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: _isSidebarExpanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.white70,
              size: 20,
            ),
            if (_isSidebarExpanded) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Logout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to log out of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              await SessionManager.clearSession();
              if (!mounted) return;
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text(
              'Logout',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (!_isSidebarExpanded)
            IconButton(
              icon: Icon(
                Icons.menu,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              onPressed: _toggleSidebar,
              tooltip: 'Expand',
            ),
          if (!_isSidebarExpanded) const SizedBox(width: 4),
          const Spacer(),
          NotificationBell(
            role: 'Staff',
            userId: widget.staffId,
            userName: widget.staffName,
            companyName: '',
            iconSize: 28,
          ),
          const SizedBox(width: 16),
          StaffProfileButton(
            staffId: widget.staffId,
            staffName: widget.staffName,
            companyName: widget.companyName,
          ),
        ],
      ),
    );
  }
}
