import 'package:flutter/material.dart';
import '../../widgets/shared/vehicle_fleet_view.dart';

class StaffVehicle extends StatefulWidget {
  final String staffId;

  const StaffVehicle({super.key, required this.staffId});

  @override
  State<StaffVehicle> createState() => _StaffVehicleState();
}

class _StaffVehicleState extends State<StaffVehicle> {
  String _refreshSeed = DateTime.now().millisecondsSinceEpoch.toString();

  void _triggerInstantRefresh() {
    if (mounted) {
      setState(() {
        _refreshSeed = DateTime.now().millisecondsSinceEpoch.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: VehicleFleetView(
        key: ValueKey('staff_fleet_list_$_refreshSeed'),
        userRole: 'staff', // 🔒 Hides Admin actions
        userId: widget.staffId,
        onRefreshNeeded: _triggerInstantRefresh,
        title: 'Vehicle Management',
        subtitle: 'View fleet assets, telemetry, and log maintenance reports.',
      ),
    );
  }
}