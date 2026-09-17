import 'package:flutter/material.dart';
import '../../widgets/shared/shared_drivers_view.dart';
import '../../widgets/driver/driver_form_dialog.dart';
import '../../widgets/driver/driver_profile_model.dart';
import '../../constant.dart';

class StaffDrivers extends StatefulWidget {
  const StaffDrivers({super.key});

  @override
  State<StaffDrivers> createState() => _StaffDriversState();
}

class _StaffDriversState extends State<StaffDrivers> {
  // Changing string seed forces an absolute UI state redraw on data operations
  String _refreshSeed = DateTime.now().millisecondsSinceEpoch.toString();

  void _showDriverModal(BuildContext context, DriverProfileModel driver) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DriverFormDialog(
        driver: driver,
        backendUrl: backendUrl,
        onDelete: null, // 🔒 Staff cannot delete records
        onSuccess: () {
          _triggerInstantRefresh(); // Instantly catches modifications on save
        },
      ),
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
        canManage: false, // 🔒 Prevents Staff from seeing admin management options
        onDriverTapped: (ctx, model) {
          if (model != null) _showDriverModal(ctx, model);
        },
        
        // 👇 Utilizing the newly revitalized SharedDriversView parameters
        title: 'Driver Records',
        subtitle: 'View and manage driver profiles.',
        // Notice we do NOT pass an actionWidget here. 
        // This ensures the "Add Driver" button stays hidden for Staff, while keeping the layout structurally identical to the Admin side!
      ),
    );
  }
}