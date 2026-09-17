import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'driver_profile_model.dart';

class DriverFormDialog extends StatefulWidget {
  final DriverProfileModel? driver;
  final VoidCallback? onDelete;
  final VoidCallback? onSuccess;
  final String backendUrl;

  const DriverFormDialog({
    super.key,
    this.driver,
    this.onDelete,
    this.onSuccess,
    required this.backendUrl,
  });

  @override
  State<DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends State<DriverFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isWritingUnlocked = false;

  late TextEditingController _nameController;
  late TextEditingController _licenseController;
  late TextEditingController _emailController;
  late TextEditingController _birthdayController;
  final _passwordController = TextEditingController();

  String _currentStatus = 'Active';

  @override
  void initState() {
    super.initState();
    final bool isEdit = widget.driver != null;
    _isWritingUnlocked = !isEdit;

    _nameController = TextEditingController(
      text: isEdit ? widget.driver!.name : '',
    );
    _licenseController = TextEditingController(
      text: isEdit ? widget.driver!.licenseNumber : '',
    );
    _emailController = TextEditingController(
      text: isEdit ? widget.driver!.email : '',
    );
    _birthdayController = TextEditingController(
      text: isEdit ? widget.driver!.birthday : '1995-05-15',
    );
    _currentStatus = isEdit ? widget.driver!.status : 'Active';
  }

  InputDecoration _fieldStyle({
    required BuildContext context,
    required String label,
    required IconData icon,
    bool forcesDisabled = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool editable = _isWritingUnlocked && !forcesDisabled;

    final fillColor = editable
        ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC))
        : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade100);
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final textColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: textColor, size: 20),
      filled: true,
      fillColor: fillColor,
      labelStyle: TextStyle(
        color: textColor,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
      floatingLabelStyle: const TextStyle(color: Color(0xFF3B82F6)),
    );
  }

  Future<void> _selectDate(TextEditingController controller) async {
    DateTime parsed =
        DateTime.tryParse(controller.text) ?? DateTime(1995, 5, 15);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(1950),
      lastDate: DateTime(2045),
    );
    if (picked != null) {
      setState(() {
        controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _submitDataStream() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final bool isEdit = widget.driver != null;

    try {
      final http.Response res;
      final Map<String, dynamic> payload = {
        'full_name': _nameController.text.trim(),
        'license_no': _licenseController.text.trim(),
        'email': _emailController.text.trim(),
        'birthday': _birthdayController.text.trim(),
        'employment_status': _currentStatus,
      };

      if (isEdit) {
        res = await http
            .put(
              Uri.parse(
                '${widget.backendUrl}/auth/update-driver/${widget.driver!.userId}',
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));

        if (_passwordController.text.isNotEmpty) {
          final passResponse = await http
              .post(
                Uri.parse('${widget.backendUrl}/auth/update-password'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'user_id': widget.driver!.userId,
                  'new_password': _passwordController.text,
                }),
              )
              .timeout(const Duration(seconds: 10));

          final passData = jsonDecode(passResponse.body);
          if (passResponse.statusCode != 200 || passData['success'] != true) {
            throw Exception(
              passData['message'] ?? "Failed to override driver password.",
            );
          }
        }
      } else {
        final DateTime now = DateTime.now();
        final String formattedHired =
            "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

        payload['password'] = _passwordController.text;
        payload['license_expiry'] = '2031-12-31';
        payload['date_hired'] = formattedHired;

        res = await http
            .post(
              Uri.parse('${widget.backendUrl}/auth/register-driver'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));
      }

      if (!mounted) return;
      final responseData = jsonDecode(res.body);

      if ((res.statusCode == 200 || res.statusCode == 201) &&
          responseData['success'] != false) {
        if (widget.onSuccess != null) widget.onSuccess!();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Driver profile saved successfully!"),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error: ${responseData['message'] ?? 'Server validation error.'}",
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Form submission exception: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Network error: $e"),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.driver != null;
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputTextColor = isDark ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: isMobile ? double.infinity : 520,
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- Header ----
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit
                      ? 'Driver Profile (DRV-${widget.driver!.id})'
                      : 'Register New Driver',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.grey.shade400 : Colors.black87,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ---- Form ----
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: inputTextColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Full Name',
                          icon: Icons.person,
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _licenseController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: inputTextColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'License Number',
                          icon: Icons.card_membership,
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: inputTextColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Account Email',
                          icon: Icons.email,
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _currentStatus,
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Employment Status',
                          icon: Icons.work_outline,
                        ),
                        dropdownColor: Theme.of(context).cardColor,
                        style: TextStyle(color: inputTextColor, fontSize: 13),
                        items: ['Active', 'On Leave'].map((String status) {
                          return DropdownMenuItem<String>(
                            value: status,
                            child: Text(status),
                          );
                        }).toList(),
                        onChanged: !_isWritingUnlocked
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _currentStatus = val);
                                }
                              },
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _birthdayController,
                        readOnly: true,
                        style: TextStyle(color: inputTextColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: 'Date of Birth (YYYY-MM-DD)',
                          icon: Icons.cake,
                        ),
                        onTap: !_isWritingUnlocked
                            ? null
                            : () => _selectDate(_birthdayController),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        readOnly: !_isWritingUnlocked,
                        style: TextStyle(color: inputTextColor),
                        decoration: _fieldStyle(
                          context: context,
                          label: isEdit
                              ? 'Reset Password (Leave empty to keep current)'
                              : 'Account Password',
                          icon: Icons.lock_reset,
                        ),
                        validator: (v) {
                          if (!isEdit && (v == null || v.length < 6))
                            return 'Password must be >= 6 chars';
                          if (isEdit &&
                              v != null &&
                              v.isNotEmpty &&
                              v.length < 6)
                            return 'Password must be >= 6 chars';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      if (isEdit) ...[
                        TextFormField(
                          initialValue: widget.driver!.dateHired,
                          readOnly: true,
                          style: TextStyle(color: inputTextColor),
                          decoration: _fieldStyle(
                            context: context,
                            label: 'Date Hired',
                            icon: Icons.event_available,
                            forcesDisabled: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          initialValue: widget.driver!.licenseExpiry,
                          readOnly: true,
                          style: TextStyle(color: inputTextColor),
                          decoration: _fieldStyle(
                            context: context,
                            label: 'License Expiration',
                            icon: Icons.assignment_late,
                            forcesDisabled: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ---- Actions ----
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isEdit && widget.onDelete != null)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete!();
                    },
                    child: const Text(
                      'Delete',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isEdit && !_isWritingUnlocked)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF64748B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _isWritingUnlocked = true),
                        child: const Text(
                          'Edit Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: _isLoading ? null : _submitDataStream,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isEdit ? 'Save Changes' : 'Register Driver',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
