import 'package:flutter/material.dart';
import '../1.dashboard/fast_dashboard_view.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const FastDashboardView(showClientTrips: true);
  }
}
