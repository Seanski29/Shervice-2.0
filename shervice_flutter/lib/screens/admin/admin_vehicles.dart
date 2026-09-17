import 'package:flutter/material.dart';
import '../../widgets/shared/vehicle_fleet_view.dart';

class AdminFleet extends StatefulWidget {
  const AdminFleet({super.key});

  @override
  State<AdminFleet> createState() => _AdminFleetState();
}

class _AdminFleetState extends State<AdminFleet> {
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
        key: ValueKey('admin_fleet_list_$_refreshSeed'),
        userRole: 'admin', 
        onRefreshNeeded: _triggerInstantRefresh,
        title: 'Vehicle Management',
        subtitle: 'Manage vehicle profiles, documents, and compliance status.',
      ),
    );
  }
}