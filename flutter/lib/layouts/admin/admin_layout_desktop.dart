import 'package:flutter/material.dart';

import '../../login/login.dart';
import '../../6.companies/admin_companies.dart';
import '../../admin/admin_dashboard.dart';
import '../../admin/admin_drivers.dart';
import '../../admin/admin_payroll.dart';
import '../../admin/admin_reports_manager.dart';
import '../../admin/admin_routes.dart';
import '../../admin/admin_schedules.dart';
import '../../admin/admin_settings.dart';
import '../../5.users/admin_users.dart';
import '../../admin/admin_vehicles.dart';
import '../../session_manager.dart';
import '../../admin/admin_profile_button.dart';
import '../enterprise/enterprise_shell.dart';
import '../notification_bell.dart';
import '../../10.analytics/shared_analytics_hub.dart';

class AdminDesktopLayout extends StatelessWidget {
  const AdminDesktopLayout({
    super.key,
    required this.adminId,
    this.adminName = 'Admin',
  });

  final String adminId;
  final String adminName;

  @override
  Widget build(BuildContext context) {
    return EnterpriseShell(
      role: 'Admin',
      userName: adminName,
      navigationItems: [
        const EnterpriseNavigationItem(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          section: 'Workspace',
          screen: AdminDashboard(),
          keywords: ['overview', 'operations'],
        ),
        const EnterpriseNavigationItem(
          label: 'Trip Summary',
          icon: Icons.calendar_month_outlined,
          section: 'Operations',
          screen: AdminSchedules(),
          keywords: ['dispatch', 'calendar', 'assignments'],
        ),
        
        const EnterpriseNavigationItem(
          label: 'Vehicles',
          icon: Icons.directions_bus_outlined,
          section: 'Operations',
          screen: AdminFleet(),
          keywords: ['fleet', 'maintenance'],
        ),
        const EnterpriseNavigationItem(
          label: 'Routes',
          icon: Icons.route_outlined,
          section: 'Operations',
          screen: AdminRoutes(),
          keywords: ['destinations', 'optimization'],
        ),
        const EnterpriseNavigationItem(
          label: 'Users',
          icon: Icons.manage_accounts_outlined,
          section: 'Organization',
          screen: AdminUsers(),
          keywords: ['accounts', 'roles', 'access'],
        ),
        const EnterpriseNavigationItem(
          label: 'Companies',
          icon: Icons.business_outlined,
          section: 'Organization',
          screen: AdminCompanies(),
          keywords: ['clients', 'tenants'],
        ),
        const EnterpriseNavigationItem(
          label: 'Attendance',
          icon: Icons.fact_check_outlined,
          section: 'Workforce',
          screen: AdminReportsManager(),
          keywords: ['timecard', 'hours'],
        ),
        const EnterpriseNavigationItem(
          label: 'Drivers',
          icon: Icons.badge_outlined,
          section: 'Workforce',
          screen: AdminDriver(),
          keywords: ['operators', 'profiles'],
        ),
        const EnterpriseNavigationItem(
          label: 'Payroll',
          icon: Icons.payments_outlined,
          section: 'Workforce',
          screen: AdminPayroll(),
          keywords: ['compensation', 'payslip'],
        ),
        const EnterpriseNavigationItem(
          label: 'Analytics',
          icon: Icons.query_stats_outlined,
          section: 'Intelligence',
          screen: SharedAnalyticsHub(),
          keywords: ['performance', 'reports', 'insights'],
        ),
        // NOTE: No 'const' keyword here because adminId is dynamic
        EnterpriseNavigationItem(
          label: 'Settings',
          icon: Icons.settings_outlined,
          section: 'Hidden',
          screen: AdminSettings(adminId: adminId),
          keywords: const ['preferences', 'theme', 'account'],
        ),
      ],
      notification: NotificationBell(
        role: 'Admin',
        userId: adminId,
        userName: adminName,
        companyName: '',
        iconSize: 22,
      ),
      profile: AdminProfileButton(
        adminId: adminId,
        adminName: adminName,
        compact: true,
      ),
      onLogout: () => _logout(context),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await SessionManager.clearSession();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}