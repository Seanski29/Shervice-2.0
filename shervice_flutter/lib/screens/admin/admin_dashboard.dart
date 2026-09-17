import 'package:flutter/material.dart';
import '../../widgets/shared/shared_dashboard_view.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if Dark Mode is active
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SharedDashboardView(
      showClientTrips: true, // Admins track company metrics
      headerWidget: Text(
        'Admin Dashboard',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          // Dynamic text color
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
