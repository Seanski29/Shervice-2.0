import 'package:flutter/material.dart';

import '../../login/login.dart';
import '../../staff/staff_dashboard.dart';
import '../../session_manager.dart';
import '../enterprise/deferred_screen.dart';
import '../enterprise/enterprise_shell.dart';
import '../notification_bell.dart';
import '../../interface/staff_profile_button.dart';
import '../../staff/staff_drivers.dart' deferred as staff_drivers;
import '../../staff/staff_payroll.dart' deferred as staff_payroll;
import '../../staff/staff_reports_manager.dart' deferred as staff_reports;
import '../../staff/staff_routes.dart' deferred as staff_routes;
import '../../staff/staff_settings.dart' deferred as staff_settings;
import '../../staff/staff_trips.dart' deferred as staff_trips;
import '../../staff/staff_vehicle.dart' deferred as staff_vehicle;
import '../../10.analytics/shared_analytics_hub.dart' deferred as analytics_hub;

class StaffLayoutDesktop extends StatelessWidget {
  const StaffLayoutDesktop({
    super.key,
    required this.staffId,
    required this.companyName,
    this.staffName = 'Staff',
  });

  final String staffId;
  final String staffName;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    return EnterpriseShell(
      role: 'Staff',
      userName: staffName,
      navigationItems: [
        EnterpriseNavigationItem(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          section: 'Workspace',
          screen: StaffDashboard(
            staffName: staffName,
            companyName: companyName,
          ),
          keywords: const ['overview', 'operations'],
        ),
        EnterpriseNavigationItem(
          label: 'Trip Summary',
          icon: Icons.assignment_outlined,
          section: 'Operations',
          screen: DeferredScreen(
            loader: staff_trips.loadLibrary,
            builder: () => staff_trips.StaffTrips(staffId: staffId),
          ),
          keywords: const ['trips', 'daily log'],
        ),
        EnterpriseNavigationItem(
          label: 'Vehicles',
          icon: Icons.directions_bus_outlined,
          section: 'Operations',
          screen: DeferredScreen(
            loader: staff_vehicle.loadLibrary,
            builder: () => staff_vehicle.StaffVehicle(staffId: staffId),
          ),
          keywords: const ['fleet', 'maintenance'],
        ),
        EnterpriseNavigationItem(
          label: 'Drivers',
          icon: Icons.badge_outlined,
          section: 'Workforce',
          screen: DeferredScreen(
            loader: staff_drivers.loadLibrary,
            builder: _buildStaffDrivers,
          ),
          keywords: ['operators', 'profiles'],
        ),
        EnterpriseNavigationItem(
          label: 'Routes',
          icon: Icons.route_outlined,
          section: 'Operations',
          screen: DeferredScreen(
            loader: staff_routes.loadLibrary,
            builder: _buildStaffRoutes,
          ),
          keywords: ['destinations', 'optimization'],
        ),
        EnterpriseNavigationItem(
          label: 'Attendance',
          icon: Icons.fact_check_outlined,
          section: 'Workforce',
          screen: DeferredScreen(
            loader: staff_reports.loadLibrary,
            builder: _buildStaffReports,
          ),
          keywords: ['timecard', 'hours'],
        ),
        EnterpriseNavigationItem(
          label: 'Payroll',
          icon: Icons.payments_outlined,
          section: 'Workforce',
          screen: DeferredScreen(
            loader: staff_payroll.loadLibrary,
            builder: _buildStaffPayroll,
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
        EnterpriseNavigationItem(
          label: 'Settings',
          icon: Icons.settings_outlined,
          section: 'Hidden',
          screen: DeferredScreen(
            loader: staff_settings.loadLibrary,
            builder: () => staff_settings.StaffSettings(
              staffId: staffId,
              staffName: staffName,
              companyName: companyName,
            ),
          ),
          keywords: const ['preferences', 'theme', 'account'],
        ),
      ],
      notification: NotificationBell(
        role: 'Staff',
        userId: staffId,
        userName: staffName,
        companyName: companyName,
        iconSize: 22,
      ),
      profile: StaffProfileButton(
        staffId: staffId,
        staffName: staffName,
        companyName: companyName,
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

Widget _buildStaffDrivers() => staff_drivers.StaffDrivers();
Widget _buildStaffRoutes() => staff_routes.StaffRoutes();
Widget _buildStaffReports() => staff_reports.StaffReportsManager();
Widget _buildStaffPayroll() => staff_payroll.StaffPayroll();
Widget _buildAnalyticsHub() => analytics_hub.SharedAnalyticsHub();
