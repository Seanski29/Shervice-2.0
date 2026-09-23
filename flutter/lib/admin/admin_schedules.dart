import 'package:flutter/material.dart';
import '../2.trip_summary/trip_summary.dart';

class AdminSchedules extends StatelessWidget {
  const AdminSchedules({super.key});

  @override
  Widget build(BuildContext context) {
    return const StaffTrips(
      staffId: 'all',
      canManageSummaries: false,
      title: 'Trip Summary',
      subtitle: 'View documented trip summaries across staff operations.',
    );
  }
}
