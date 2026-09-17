import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/shared/legal_policies_button.dart';
import '../../theme/dark_mode_toggle.dart'; // Added Import!
import 'package:http/http.dart' as http;
import 'package:skeletonizer/skeletonizer.dart';
import '../../constant.dart';
import '../../widgets/driver/driver_rating_badge.dart';

class DriverProfile extends StatefulWidget {
  final String driverName;
  final String driverId;

  const DriverProfile({
    super.key,
    required this.driverName,
    required this.driverId,
  });

  @override
  State<DriverProfile> createState() => _DriverProfileState();
}

class _DriverProfileState extends State<DriverProfile> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _fetchPersonalDriverProfile();
  }

  Future<void> _fetchPersonalDriverProfile() async {
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/test-db'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['connection_status'] == 'SUCCESS') {
          final List<dynamic> profiles = data['sample_data_payload'] ?? [];

          final matchingRow = profiles.firstWhere(
            (p) =>
                p['full_name'].toString().trim().toLowerCase() ==
                widget.driverName.trim().toLowerCase(),
            orElse: () => null,
          );

          setState(() {
            _profileData = matchingRow;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("❌ Profile loader intercept mismatch anomaly: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAccountPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final String targetUserId = _profileData?['user_id'] ?? '';

      if (targetUserId.isEmpty) {
        _showSnackBar(
          "Profile sync failed. Cannot resolve user identity.",
          Colors.red,
        );
        setState(() => _isSaving = false);
        return;
      }

      final response = await http
          .post(
            Uri.parse('$backendUrl/auth/update-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': targetUserId,
              'new_password': _passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        _showSnackBar(
          "Password updated securely in the cloud vault!",
          Colors.green,
        );
        _passwordController.clear();
        _confirmPasswordController.clear();
      } else {
        _showSnackBar(
          responseData['message'] ?? "Failed to update password.",
          Colors.red,
        );
      }
    } catch (e) {
      _showSnackBar("Network error: Could not reach the server.", Colors.red);
      debugPrint("Password update failed: $e");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFF8FAFC);

    final bool isMobile = MediaQuery.of(context).size.width < 800;
    final double horizontalPadding = isMobile ? 12.0 : 24.0;

    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark
        ? Colors.grey.shade400
        : const Color(0xFF64748B);
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);
    final inputBgColor = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);

    final license = _profileData?['license_no'] ?? 'N/A';
    final hiredDate = _profileData?['date_hired'] ?? 'Not Recorded';

    return Scaffold(
      backgroundColor: bgColor,
      body: Skeletonizer(
        enabled: _isLoading,
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 20.0,
          ),
          children: [
            // ─── HEADER ───
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver Account',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage your profile, security, and preferences.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: subTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ─── PROFILE CARD ───
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: isDark
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.blue.shade50,
                    child: Text(
                      widget.driverName
                          .substring(0, widget.driverName.contains(' ') ? 2 : 1)
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        widget.driverName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Active',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.green.shade400
                                    : Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.amber.withValues(alpha: 0.1)
                                  : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DriverRatingBadge(
                              key: UniqueKey(),
                              driverUuid: widget.driverId,
                              backendUrl: backendUrl,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── OPERATIONAL RECORDS ───
            Text(
              'Operational Records',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: subTextColor,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  _infoRow(
                    Icons.card_membership,
                    "License Number",
                    license,
                    textColor,
                    subTextColor,
                  ),
                  Divider(height: 24, color: borderColor),
                  _infoRow(
                    Icons.calendar_today,
                    "Date Hired",
                    hiredDate,
                    textColor,
                    subTextColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── SECURITY ───
            Text(
              'Security',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: subTextColor,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Change Account Password",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: "New Password",
                        labelStyle: TextStyle(
                          color: subTextColor,
                          fontSize: 13,
                        ),
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
                          borderSide: const BorderSide(
                            color: Color(0xFF3B82F6),
                            width: 1.5,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: subTextColor,
                        ),
                        filled: true,
                        fillColor: inputBgColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      validator: (val) => val == null || val.length < 6
                          ? "Password must contain at least 6 characters"
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: "Confirm New Password",
                        labelStyle: TextStyle(
                          color: subTextColor,
                          fontSize: 13,
                        ),
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
                          borderSide: const BorderSide(
                            color: Color(0xFF3B82F6),
                            width: 1.5,
                          ),
                        ),
                        prefixIcon: Icon(Icons.lock_reset, color: subTextColor),
                        filled: true,
                        fillColor: inputBgColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      validator: (val) => val != _passwordController.text
                          ? "Passwords do not match"
                          : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _updateAccountPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Update System Password",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ─── PREFERENCES ───
            Text(
              'Preferences',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: subTextColor,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: const DarkModeToggle(),
            ),
            const SizedBox(height: 20),

            // ─── LEGAL ───
            const LegalPoliciesLinks(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Helper widget modified to accept dynamic colors
  Widget _infoRow(
    IconData icon,
    String label,
    String value,
    Color textColor,
    Color subTextColor,
  ) {
    return Row(
      children: [
        Icon(icon, color: subTextColor),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: subTextColor)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}