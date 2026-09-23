import 'package:flutter/material.dart';
import '../8.drivers/shared_drivers_view.dart';
import '../8.drivers/driver_form_dialog.dart';
import '../8.drivers/driver_profile_model.dart';
import '../constant.dart';

class StaffDrivers extends StatefulWidget {
  const StaffDrivers({super.key});

  @override
  State<StaffDrivers> createState() => _StaffDriversState();
}

class _StaffDriversState extends State<StaffDrivers> {
  // Changing string seed forces an absolute UI state redraw on data operations
  String _refreshSeed = DateTime.now().millisecondsSinceEpoch.toString();

  void _showDriverModal(BuildContext context, DriverProfileModel driver) {
    DriverFormDialogs.showViewDriverModal(
      context,
      driver,
      onEdit: () => DriverFormDialogs.showEditDriverDialog(
        context,
        driver,
        onSuccess: _triggerInstantRefresh,
      ),
      // Staff cannot delete records, so onDelete is purposely omitted.
    );
  }

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
      // Dynamic Scaffold Background
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      body: SharedDriversView(
        // The unique value key tells Flutter to destroy the old layout cache and fetch fresh data
        key: ValueKey('staff_drivers_list_$_refreshSeed'),
        canManage: false,
        onDriverTapped: (ctx, model) {
          if (model != null) _showDriverModal(ctx, model);
        },

        // Shared directory parameters keep role layouts structurally identical.
        title: 'Drivers',
        subtitle: '',
        // Notice we do NOT pass an actionWidget here.
        // This ensures the "Add Driver" button stays hidden for Staff, while keeping the layout structurally identical to the Admin side!
      ),
    );
  }
}
