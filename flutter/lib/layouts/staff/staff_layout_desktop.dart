import 'package:flutter/material.dart';

import '../../login/login.dart';
import '../../screens/staff/staff_dashboard.dart';
import '../../screens/staff/staff_drivers.dart';
import '../../screens/staff/staff_payroll.dart';
import '../../screens/staff/staff_reports_manager.dart';
import '../../screens/staff/staff_routes.dart';
import '../../screens/staff/staff_settings.dart';
import '../../screens/staff/staff_trips.dart';
import '../../screens/staff/staff_vehicle.dart';
import '../../session_manager.dart';
import '../enterprise/enterprise_shell.dart';
import '../../widgets/notifcations/notification_bell.dart';
import '../../widgets/shared/shared_analytics_hub.dart';
import '../../widgets/staff/staff_profile_button.dart';

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
          screen: StaffTrips(staffId: staffId),
          keywords: const ['trips', 'daily log'],
        ),
        EnterpriseNavigationItem(
          label: 'Vehicles',
          icon: Icons.directions_bus_outlined,
          section: 'Operations',
          screen: StaffVehicle(staffId: staffId),
          keywords: const ['fleet', 'maintenance'],
        ),
        const EnterpriseNavigationItem(
          label: 'Drivers',
          icon: Icons.badge_outlined,
          section: 'Operations',
          screen: StaffDrivers(),
          keywords: ['operators', 'profiles'],
        ),
        const EnterpriseNavigationItem(
          label: 'Routes',
          icon: Icons.route_outlined,
          section: 'Operations',
          screen: StaffRoutes(),
          keywords: ['destinations', 'optimization'],
        ),
        const EnterpriseNavigationItem(
          label: 'Attendance',
          icon: Icons.fact_check_outlined,
          section: 'Workforce',
          screen: StaffReportsManager(),
          keywords: ['timecard', 'hours'],
        ),
        const EnterpriseNavigationItem(
          label: 'Payroll',
          icon: Icons.payments_outlined,
          section: 'Workforce',
          screen: StaffPayroll(),
          keywords: ['compensation', 'payslip'],
        ),
        const EnterpriseNavigationItem(
          label: 'Analytics',
          icon: Icons.query_stats_outlined,
          section: 'Intelligence',
          screen: SharedAnalyticsHub(),
          keywords: ['performance', 'reports', 'insights'],
        ),
        EnterpriseNavigationItem(
          label: 'Settings',
          icon: Icons.settings_outlined,
          section: 'Hidden',
          screen: StaffSettings(
            staffId: staffId,
            staffName: staffName,
            companyName: companyName,
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