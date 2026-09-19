import 'package:flutter/material.dart';
import '../../widgets/shared/shared_dashboard_view.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const SharedDashboardView(showClientTrips: true);
  }
}
