import 'package:flutter/material.dart';

import '../../login/login.dart';
import '../../staff/staff_dashboard.dart';
import '../../staff/staff_drivers.dart';
import '../../staff/staff_payroll.dart';
import '../../staff/staff_reports_manager.dart';
import '../../staff/staff_routes.dart';
import '../../staff/staff_settings.dart';
import '../../staff/staff_trips.dart';
import '../../staff/staff_vehicle.dart';
import '../../session_manager.dart';
import '../enterprise/enterprise_shell.dart';
import '../notification_bell.dart';
import '../../interface/staff_profile_button.dart';
<<<<<<< HEAD
import '../../10.analytics/shared_analytics_hub.dart';
=======
import '../../staff/staff_drivers.dart' deferred as staff_drivers;
import '../../staff/staff_payroll.dart' deferred as staff_payroll;
import '../../staff/staff_reports_manager.dart' deferred as staff_reports;
import '../../staff/staff_routes.dart' deferred as staff_routes;
import '../../staff/staff_settings.dart' deferred as staff_settings;
import '../../staff/staff_trips.dart' deferred as staff_trips;
import '../../staff/staff_passenger_survey.dart' deferred as passenger_survey;
import '../../staff/staff_vehicle.dart' deferred as staff_vehicle;
import '../../10.analytics/shared_analytics_hub.dart' deferred as analytics_hub;
>>>>>>> 42603a952471089426df6156dc37a871d1e169ae

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
          section: 'Workforce',
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
          label: 'Passenger Survey',
          icon: Icons.qr_code_2_outlined,
          section: 'Intelligence',
          screen: DeferredScreen(
            loader: passenger_survey.loadLibrary,
            builder: () => passenger_survey.StaffPassengerSurvey(),
          ),
          keywords: ['anonymous', 'feedback', 'qr', 'evaluation'],
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
