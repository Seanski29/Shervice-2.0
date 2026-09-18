import 'package:flutter/material.dart';
import '../../widgets/shared/shared_drivers_view.dart';
import '../../widgets/driver/driver_form_dialog.dart';
import '../../widgets/driver/driver_profile_model.dart';

class AdminDriver extends StatefulWidget {
  const AdminDriver({super.key});

  @override
  State<AdminDriver> createState() => _AdminDriverState();
}

class _AdminDriverState extends State<AdminDriver> {
  // Changing string seed forces an absolute UI state redraw on data operations
  String _refreshSeed = DateTime.now().millisecondsSinceEpoch.toString();

  void _showDriverModal(BuildContext context, DriverProfileModel? driver) {
    if (driver == null) {
      // Trigger Add Driver Dialog
      DriverFormDialogs.showAddDriverDialog(
        context,
        onSuccess: _triggerInstantRefresh,
      );
    } else {
      // Trigger View/Edit/Delete Driver Modal
      DriverFormDialogs.showViewDriverModal(
        context,
        driver,
        onEdit: () => DriverFormDialogs.showEditDriverDialog(
          context,
          driver,
          onSuccess: _triggerInstantRefresh,
        ),
        onDelete: () => DriverFormDialogs.showDeleteConfirmationDialog(
          context,
          driver,
          onSuccess: _triggerInstantRefresh,
        ),
      );
    }
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SharedDriversView(
        key: ValueKey('admin_drivers_list_$_refreshSeed'),
        canManage: true,
        onDriverTapped: (ctx, model) => _showDriverModal(ctx, model),

        // Pass UI text and actions directly so the view can wrap them dynamically
        title: 'Driver Management',
        subtitle:
            'Manage driver profiles, assignments, and performance records.',

        // The Add Driver action widget
        actionWidget: ElevatedButton.icon(
          onPressed: () => _showDriverModal(context, null),
          icon: const Icon(Icons.person_add, color: Colors.white, size: 18),
          label: const Text(
            'Add Driver',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}
