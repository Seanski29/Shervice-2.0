import 'package:flutter/material.dart';
import '../../screens/admin/admin_dashboard.dart';
import '../../screens/admin/admin_schedules.dart';
import '../../screens/admin/admin_drivers.dart';
import '../../screens/admin/admin_vehicles.dart';
import '../../screens/admin/admin_users.dart';
import '../../screens/admin/admin_reports_manager.dart';
import '../../screens/admin/admin_settings.dart';
import '../../login/login.dart';
import '../../widgets/shared/notification_bell.dart';
import '../../widgets/shared/shervice_floating_stack.dart';
import '../../constant.dart';
import '../../session_manager.dart';
import '../../widgets/admin/admin_profile_button.dart';
import '../../widgets/shared/shared_analytics_hub.dart';
import '../../screens/admin/admin_companies.dart';

class AdminDesktopLayout extends StatefulWidget {
  final String adminId;
  final String adminName;

  const AdminDesktopLayout({
    super.key,
    required this.adminId,
    this.adminName = 'Admin',
  });

  @override
  State<AdminDesktopLayout> createState() => _AdminDesktopLayoutState();
}

class _AdminDesktopLayoutState extends State<AdminDesktopLayout> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    _screens = [
      const AdminDashboard(),
      const AdminSchedules(),
      const AdminDriver(),
      const AdminFleet(),
      const AdminUsers(),
      const AdminCompanies(),
      const SharedAnalyticsHub(),
      const AdminReportsManager(),
      AdminSettings(adminId: widget.adminId),
      // Note: You can add AdminFeedbacks() here if you want it mapped to a sidebar index!
    ];
  }

  void _toggleSidebar() {
    setState(() => _isSidebarExpanded = !_isSidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return SherviceFloatingStack(
      userRole: 'Admin',
      userName: widget.adminName,
      localIp: localIp,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Row(
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
      ),
    );
  }

  // ─── SIDEBAR (Kept static dark blue as per brand guidelines) ───
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
                // Logo
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
                      children: [
                        Image.asset(
                          'assets/shervice - white.jpg',
                          height: 25,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Admin Portal',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ─── TOGGLE BUTTON (inside sidebar when expanded) ───
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
                _buildNavItem(0, 'Dashboard', Icons.dashboard_outlined),
                _buildNavItem(
                  1,
                  'Schedule Management',
                  Icons.calendar_month_outlined,
                ),
                _buildNavItem(2, 'Driver Management', Icons.people_outline),
                _buildNavItem(
                  3,
                  'Vehicle Management',
                  Icons.directions_car_outlined,
                ),
                _buildNavItem(
                  4,
                  'User Management',
                  Icons.admin_panel_settings_outlined,
                ),
                _buildNavItem(
                  5,
                  'Company Management',
                  Icons.business_outlined,
                ), // 👈 NEW
                _buildNavItem(6, 'Analytics', Icons.analytics),
                _buildNavItem(
                  7,
                  'Import & Export',
                  Icons.import_export_outlined,
                ),
                _buildNavItem(8, 'Settings', Icons.settings_outlined),
              ],
            ),
          ),
          _buildNavItem(99, 'Log Out', Icons.logout, isLogout: true),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── HEADER (Now fully responsive to Dark Mode) ───
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
          // ─── TOGGLE BUTTON (only when sidebar is collapsed) ───
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
            role: 'Admin',
            userId: widget.adminId,
            userName: widget.adminName,
            companyName: '',
            iconSize: 28,
          ),
          const SizedBox(width: 16),
          AdminProfileButton(
            adminId: widget.adminId,
            adminName: widget.adminName,
          ),
        ],
      ),
    );
  }

  // ─── NAVIGATION ITEM ───
  Widget _buildNavItem(
    int index,
    String title,
    IconData icon, {
    bool isLogout = false,
  }) {
    bool isActive = _selectedIndex == index && !isLogout;
    return InkWell(
      onTap: () {
        if (isLogout) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Confirm Logout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text('Are you sure you want to log out?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
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
        } else {
          setState(() => _selectedIndex = index);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.white70,
              size: 20,
            ),
            if (_isSidebarExpanded) ...[
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
