import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../widgets/shared/shared_drivers_view.dart';
import '../../widgets/driver/driver_form_dialog.dart';
import '../../widgets/driver/driver_profile_model.dart';
import '../../constant.dart';

class AdminDriver extends StatefulWidget {
  const AdminDriver({super.key});

  @override
  State<AdminDriver> createState() => _AdminDriverState();
}

class _AdminDriverState extends State<AdminDriver> {
  // Changing string seed forces an absolute UI state redraw on data operations
  String _refreshSeed = DateTime.now().millisecondsSinceEpoch.toString();

  void _showDriverModal(BuildContext context, DriverProfileModel? driver) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DriverFormDialog(
        driver: driver,
        backendUrl: backendUrl,
        onDelete: () => _confirmPurgeDriver(context, driver!),
        onSuccess: () {
          _triggerInstantRefresh();
        },
      ),
    );
  }

  void _confirmPurgeDriver(BuildContext context, DriverProfileModel driver) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Deletion',
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently erase ${driver.name} from the fleet network?',
          style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final res = await http
                    .delete(Uri.parse('$backendUrl/auth/delete-driver/${driver.userId}'))
                    .timeout(const Duration(seconds: 10));

                if (res.statusCode == 200) {
                  _triggerInstantRefresh();
                }
              } catch (e) {
                debugPrint("❌ Failure purging account records: $e");
              }
            },
            child: const Text(
              'Delete permanently',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SharedDriversView(
        key: ValueKey('admin_drivers_list_$_refreshSeed'),
        canManage: true,
        onDriverTapped: (ctx, model) => _showDriverModal(ctx, model),
        
        // Pass UI text and actions directly so the view can wrap them dynamically
        title: 'Driver Management',
        subtitle: 'Manage driver profiles, assignments, and performance records.',
        actionWidget: ElevatedButton.icon(
          onPressed: () => _showDriverModal(context, null),
          icon: const Icon(Icons.person_add, color: Colors.white, size: 18),
          label: const Text(
            'Add Driver',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}