import 'package:flutter/material.dart';

import '../../login/login.dart';
import '../../admin/admin_dashboard.dart';
import '../../session_manager.dart';
import '../../admin/admin_profile_button.dart';
import '../enterprise/deferred_screen.dart';
import '../enterprise/enterprise_shell.dart';
import '../notification_bell.dart';
import '../../6.companies/admin_companies.dart' deferred as admin_companies;
import '../../admin/admin_drivers.dart' deferred as admin_drivers;
import '../../admin/admin_payroll.dart' deferred as admin_payroll;
import '../../admin/admin_reports_manager.dart' deferred as admin_reports;
import '../../admin/admin_routes.dart' deferred as admin_routes;
import '../../admin/admin_schedules.dart' deferred as admin_schedules;
import '../../admin/admin_settings.dart' deferred as admin_settings;
import '../../5.users/admin_users.dart' deferred as admin_users;
import '../../admin/admin_vehicles.dart' deferred as admin_vehicles;
import '../../10.analytics/shared_analytics_hub.dart' deferred as analytics_hub;

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
        EnterpriseNavigationItem(
          label: 'Trip Summary',
          icon: Icons.calendar_month_outlined,
          section: 'Operations',
          screen: DeferredScreen(
            loader: admin_schedules.loadLibrary,
            builder: _buildAdminSchedules,
          ),
          keywords: ['dispatch', 'calendar', 'assignments'],
        ),
        EnterpriseNavigationItem(
          label: 'Vehicles',
          icon: Icons.directions_bus_outlined,
          section: 'Operations',
          screen: DeferredScreen(
            loader: admin_vehicles.loadLibrary,
            builder: _buildAdminFleet,
          ),
          keywords: ['fleet', 'maintenance'],
        ),
        EnterpriseNavigationItem(
          label: 'Routes',
          icon: Icons.route_outlined,
          section: 'Operations',
          screen: DeferredScreen(
            loader: admin_routes.loadLibrary,
            builder: _buildAdminRoutes,
          ),
          keywords: ['destinations', 'optimization'],
        ),
        EnterpriseNavigationItem(
          label: 'Users',
          icon: Icons.manage_accounts_outlined,
          section: 'Organization',
          screen: DeferredScreen(
            loader: admin_users.loadLibrary,
            builder: _buildAdminUsers,
          ),
          keywords: ['accounts', 'roles', 'access'],
        ),
        EnterpriseNavigationItem(
          label: 'Companies',
          icon: Icons.business_outlined,
          section: 'Organization',
          screen: DeferredScreen(
            loader: admin_companies.loadLibrary,
            builder: _buildAdminCompanies,
          ),
          keywords: ['clients', 'tenants'],
        ),
        EnterpriseNavigationItem(
          label: 'Attendance',
          icon: Icons.fact_check_outlined,
          section: 'Workforce',
          screen: DeferredScreen(
            loader: admin_reports.loadLibrary,
            builder: _buildAdminReports,
          ),
          keywords: ['timecard', 'hours'],
        ),
        EnterpriseNavigationItem(
          label: 'Drivers',
          icon: Icons.badge_outlined,
          section: 'Workforce',
          screen: DeferredScreen(
            loader: admin_drivers.loadLibrary,
            builder: _buildAdminDrivers,
          ),
          keywords: ['operators', 'profiles'],
        ),
        EnterpriseNavigationItem(
          label: 'Payroll',
          icon: Icons.payments_outlined,
          section: 'Workforce',
          screen: DeferredScreen(
            loader: admin_payroll.loadLibrary,
            builder: _buildAdminPayroll,
          ),
          keywords: ['compensation', 'payslip'],
        ),
        EnterpriseNavigationItem(
          label: 'Analytics',
          icon: Icons.query_stats_outlined,
          section: 'Intelligence',
          screen: DeferredScreen(
            loader: analytics_hub.loadLibrary,
            builder: _buildAnalyticsHub,
          ),
          keywords: ['performance', 'reports', 'insights'],
        ),
        // NOTE: No 'const' keyword here because adminId is dynamic
        EnterpriseNavigationItem(
          label: 'Settings',
          icon: Icons.settings_outlined,
          section: 'Hidden',
          screen: DeferredScreen(
            loader: admin_settings.loadLibrary,
            builder: () => admin_settings.AdminSettings(adminId: adminId),
          ),
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

Widget _buildAdminSchedules() => admin_schedules.AdminSchedules();
Widget _buildAdminFleet() => admin_vehicles.AdminFleet();
Widget _buildAdminRoutes() => admin_routes.AdminRoutes();
Widget _buildAdminUsers() => admin_users.AdminUsers();
Widget _buildAdminCompanies() => admin_companies.AdminCompanies();
Widget _buildAdminReports() => admin_reports.AdminReportsManager();
Widget _buildAdminDrivers() => admin_drivers.AdminDriver();
Widget _buildAdminPayroll() => admin_payroll.AdminPayroll();
Widget _buildAnalyticsHub() => analytics_hub.SharedAnalyticsHub();
