import 'dart:convert';
import 'package:flutter/material.dart';
import '../layouts/enterprise/enterprise_states.dart';
import 'package:http/http.dart' as http;
import 'driver_profile_model.dart';
import '../constant.dart';
import '../layouts/enterprise/enterprise_theme.dart';

class DriverFormDialogs {
  // --- 1. VIEW DRIVER MODAL (WEB FRIENDLY) ---
  static void showViewDriverModal(
    BuildContext context,
    DriverProfileModel driver, {
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color statusColor;
    switch (driver.status.toLowerCase()) {
      case 'active':
        statusColor = const Color(0xFF10B981); // Green
        break;
      case 'on leave':
        statusColor = const Color(0xFFF59E0B); // Amber
        break;
      case 'suspended':
        statusColor = const Color(0xFFEF4444); // Red
        break;
      default:
        statusColor = const Color(0xFF64748B); // Grey
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driver.name,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Driver ID: ${driver.id}",
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          driver.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => Navigator.pop(ctx),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.phone_outlined,
                    "Phone Number",
                    driver.phoneNumber,
                    isDark,
                  ),
                  _buildDetailRow(
                    Icons.cake_outlined,
                    "Birthday",
                    driver.birthday,
                    isDark,
                  ),
                  _buildDetailRow(
                    Icons.event_available_outlined,
                    "Date Hired",
                    driver.dateHired,
                    isDark,
                  ),
                  if (driver.mlClassification != null)
                    _buildDetailRow(
                      Icons.analytics_outlined,
                      "Classification",
                      driver.mlClassification!,
                      isDark,
                    ),
                  const SizedBox(height: 24),
                  if (onEdit != null || onDelete != null)
                    Row(
                      children: [
                        if (onEdit != null)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                onEdit();
                              },
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text("Edit"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        if (onEdit != null && onDelete != null)
                          const SizedBox(width: 12),
                        if (onDelete != null)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                onDelete();
                              },
                              icon: const Icon(Icons.delete_forever, size: 16),
                              label: const Text("Delete"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- 2. ADD DRIVER DIALOG ---
  static void showAddDriverDialog(
    BuildContext context, {
    required VoidCallback onSuccess,
  }) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: '09');
    final bdayCtrl = TextEditingController(text: '1995-05-15');
    final hiredCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              title: Text(
                "Add New Driver",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildInputField(
                          controller: nameCtrl,
                          label: "Full Name",
                          hint: "Juan Dela Cruz",
                          icon: Icons.person_outline,
                          isDark: isDark,
                          validator: (val) => val == null || val.trim().isEmpty
                              ? "Required"
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: phoneCtrl,
                          label: "Phone Number",
                          hint: "09XXXXXXXXX",
                          icon: Icons.phone_android_outlined,
                          keyboardType: TextInputType.phone,
                          isDark: isDark,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty)
                              return "Required";
                            if (!RegExp(r'^09\d{9}$').hasMatch(val.trim())) {
                              return "Must be 11 digits starting with 09";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: bdayCtrl,
                          label: "Date of Birth (YYYY-MM-DD)",
                          hint: "1995-05-15",
                          icon: Icons.cake_outlined,
                          isDark: isDark,
                          validator: (val) =>
                              val == null || val.isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: hiredCtrl,
                          label: "Date Hired (YYYY-MM-DD)",
                          hint: "2024-01-01",
                          icon: Icons.calendar_today_outlined,
                          isDark: isDark,
                          validator: (val) =>
                              val == null || val.isEmpty ? "Required" : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setState(() => isSubmitting = true);

                          final payload = {
                            "full_name": nameCtrl.text.trim(),
                            "phone_no": phoneCtrl.text.trim(),
                            "birthday": bdayCtrl.text.trim(),
                            "date_hired": hiredCtrl.text.trim(),
                            "employment_status": "Active",
                          };

                          try {
                            final response = await http.post(
                              Uri.parse('$backendUrl/auth/register-driver'),
                              headers: {"Content-Type": "application/json"},
                              body: jsonEncode(payload),
                            );

                            final resData = jsonDecode(response.body);
                            if (response.statusCode == 201 &&
                                resData['success'] == true) {
                              if (dialogContext.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Driver registered successfully!",
                                    ),
                                  ),
                                );
                                onSuccess();
                              }
                            } else {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      resData['message'] ??
                                          "Registration failed",
                                    ),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Error registering driver: $e"),
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setState(() => isSubmitting = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnterpriseColors.generativeAction,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: EnterpriseLoadingIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Add Driver"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 3. EDIT DRIVER DIALOG ---
  static void showEditDriverDialog(
    BuildContext context,
    DriverProfileModel driver, {
    required VoidCallback onSuccess,
  }) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: driver.name);
    final phoneCtrl = TextEditingController(text: driver.phoneNumber);
    final bdayCtrl = TextEditingController(text: driver.birthday);
    final hiredCtrl = TextEditingController(text: driver.dateHired);
    String status = driver.status;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Edit Driver",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildInputField(
                          controller: nameCtrl,
                          label: "Full Name",
                          hint: "Juan Dela Cruz",
                          icon: Icons.person_outline,
                          isDark: isDark,
                          validator: (val) => val == null || val.trim().isEmpty
                              ? "Required"
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: phoneCtrl,
                          label: "Phone Number",
                          hint: "09XXXXXXXXX",
                          icon: Icons.phone_android,
                          keyboardType: TextInputType.phone,
                          isDark: isDark,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty)
                              return "Required";
                            if (!RegExp(r'^09\d{9}$').hasMatch(val.trim())) {
                              return "Must be 11 digits starting with 09";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value:
                              [
                                'Active',
                                'On Leave',
                                'Suspended',
                              ].contains(status)
                              ? status
                              : 'Active',
                          decoration: InputDecoration(
                            labelText: "Employment Status",
                            prefixIcon: const Icon(
                              Icons.work_outline,
                              size: 20,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          dropdownColor: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          items: const [
                            DropdownMenuItem(
                              value: 'Active',
                              child: Text('Active'),
                            ),
                            DropdownMenuItem(
                              value: 'On Leave',
                              child: Text('On Leave'),
                            ),
                            DropdownMenuItem(
                              value: 'Suspended',
                              child: Text('Suspended'),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => status = val ?? 'Active'),
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: bdayCtrl,
                          label: "Date of Birth (YYYY-MM-DD)",
                          hint: "1995-05-15",
                          icon: Icons.cake_outlined,
                          isDark: isDark,
                          validator: (val) =>
                              val == null || val.isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          controller: hiredCtrl,
                          label: "Date Hired (YYYY-MM-DD)",
                          hint: "2024-01-01",
                          icon: Icons.calendar_today_outlined,
                          isDark: isDark,
                          validator: (val) =>
                              val == null || val.isEmpty ? "Required" : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setState(() => isSubmitting = true);

                          final payload = {
                            "full_name": nameCtrl.text.trim(),
                            "phone_no": phoneCtrl.text.trim(),
                            "birthday": bdayCtrl.text.trim(),
                            "date_hired": hiredCtrl.text.trim(),
                            "employment_status": status,
                          };

                          try {
                            final response = await http.put(
                              Uri.parse(
                                '$backendUrl/auth/update-driver/${driver.id}',
                              ),
                              headers: {"Content-Type": "application/json"},
                              body: jsonEncode(payload),
                            );

                            final resData = jsonDecode(response.body);
                            if (response.statusCode == 200 &&
                                resData['success'] == true) {
                              if (dialogContext.mounted) {
                                Navigator.pop(ctx);
                                onSuccess();
                              }
                            } else {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      resData['message'] ?? "Update failed",
                                    ),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Error updating driver: $e"),
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setState(() => isSubmitting = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF64748B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: EnterpriseLoadingIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Edit Details"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 4. DELETE CONFIRMATION DIALOG ---
  static void showDeleteConfirmationDialog(
    BuildContext context,
    DriverProfileModel driver, {
    required VoidCallback onSuccess,
  }) {
    _deleteDriverWithConfirmation(context, driver, onSuccess: onSuccess);
  }

  static Future<void> _deleteDriverWithConfirmation(
    BuildContext context,
    DriverProfileModel driver, {
    required VoidCallback onSuccess,
  }) async {
    final confirmed = await showEnterpriseDestructiveConfirmation(
      context,
      title: 'Delete driver record?',
      message:
          'This permanently removes ${driver.name} and the associated driver profile.',
      confirmationText: 'DELETE',
    );
    if (!confirmed || !context.mounted) return;

    try {
      final response = await http.delete(
        Uri.parse('$backendUrl/auth/delete-driver/${driver.id}'),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data['success'] != true) {
        throw Exception(data['message'] ?? 'The driver could not be deleted.');
      }
      if (!context.mounted) return;
      EnterpriseToasts.success(context, 'Driver deleted successfully.');
      onSuccess();
    } catch (error) {
      if (context.mounted) {
        EnterpriseToasts.error(context, 'Driver deletion failed: $error');
      }
    }
  }

  static void _showLegacyDeleteConfirmationDialog(
    BuildContext context,
    DriverProfileModel driver, {
    required VoidCallback onSuccess,
  }) {
    bool isDeleting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade600,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  const Text("Delete Driver"),
                ],
              ),
              content: Text(
                "Are you sure you want to delete ${driver.name}? This will purge their profile permanently.",
                style: TextStyle(
                  color: isDark
                      ? Colors.grey.shade300
                      : const Color(0xFF475569),
                  fontSize: 14,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setState(() => isDeleting = true);
                          try {
                            final response = await http.delete(
                              Uri.parse(
                                '$backendUrl/auth/delete-driver/${driver.id}',
                              ),
                            );

                            final resData = jsonDecode(response.body);
                            if (response.statusCode == 200 &&
                                resData['success'] == true) {
                              if (dialogContext.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Driver deleted successfully.",
                                    ),
                                  ),
                                );
                                onSuccess();
                              }
                            } else {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      resData['message'] ?? "Deletion failed",
                                    ),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Error deleting driver: $e"),
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setState(() => isDeleting = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: EnterpriseLoadingIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Confirm Delete"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- HELPERS ---
  static Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
          ),
          const SizedBox(width: 12),
          Text(
            "$label: ",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : const Color(0xFF64748B),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 12,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
