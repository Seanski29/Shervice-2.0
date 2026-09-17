import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../constant.dart';
import '../../theme/dark_mode_toggle.dart';
import '../../widgets/shared/legal_policies_button.dart';

class OicSettings extends StatefulWidget {
  final String oicId;
  final String oicName;
  final String companyName;

  const OicSettings({
    super.key,
    required this.oicId,
    required this.oicName,
    required this.companyName,
  });

  @override
  State<OicSettings> createState() => _OicSettingsState();
}

class _OicSettingsState extends State<OicSettings> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSaving = false;

  Future<void> _updateAccountPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/auth/update-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': widget.oicId,
              'new_password': _passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        _showSnackBar("Password updated!", const Color(0xFF10B981));
        _passwordController.clear();
        _confirmPasswordController.clear();
      } else {
        _showSnackBar(
          responseData['message'] ?? "Failed to update password.",
          const Color(0xFFEF4444),
        );
      }
    } catch (e) {
      _showSnackBar("Network error.", const Color(0xFFEF4444));
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
        duration: const Duration(seconds: 2),
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
    final bool isMobile = MediaQuery.of(context).size.width < 800;
    final double horizontalPadding = isMobile ? 12.0 : 24.0;

    // 🔴 1. Check if the app is currently in Dark Mode
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🔴 2. Define colors based on the mode
    final bgColor = isDark ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);
    final borderColor = isDark ? Colors.grey.shade800 : const Color(0xFFE2E8F0);
    final inputBgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 20.0),
        children: [
          // ─── HEADER ───
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Settings',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your profile, security, and preferences.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: subTextColor),
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
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: isDark ? Colors.blue.withValues(alpha: 0.2) : const Color(0xFFEFF6FF),
                  child: Text(
                    widget.oicName.isNotEmpty ? widget.oicName[0].toUpperCase() : 'O',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.oicName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 2),
                    Text('Officer in Charge', style: TextStyle(fontSize: 13, color: subTextColor)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.green.withValues(alpha: 0.2) : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.companyName.isNotEmpty ? widget.companyName : 'GT LANTIN',
                        style: TextStyle(color: isDark ? Colors.green.shade400 : const Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ─── SECURITY ───
          Text('Security', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 0.8)),
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
                  Text("Change Account Password", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: "New Password",
                      labelStyle: TextStyle(color: subTextColor, fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
                      prefixIcon: Icon(Icons.lock_outline, color: subTextColor),
                      filled: true,
                      fillColor: inputBgColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    validator: (val) => val == null || val.length < 6 ? "Password must contain at least 6 characters" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: "Confirm New Password",
                      labelStyle: TextStyle(color: subTextColor, fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
                      prefixIcon: Icon(Icons.lock_reset, color: subTextColor),
                      filled: true,
                      fillColor: inputBgColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    validator: (val) => val != _passwordController.text ? "Passwords do not match" : null,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _updateAccountPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("Update System Password", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ─── PREFERENCES ───
          Text('Preferences', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 0.8)),
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
    );
  }
}