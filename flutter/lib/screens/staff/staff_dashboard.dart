import 'package:flutter/material.dart';
import '../../widgets/shared/shared_dashboard_view.dart';

class StaffDashboard extends StatelessWidget {
  final String staffName;
  final String companyName;

  const StaffDashboard({
    super.key,
    required this.staffName,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    return const SharedDashboardView(showClientTrips: true);
  }
}
