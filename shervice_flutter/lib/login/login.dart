import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constant.dart';
import '../session_manager.dart';

import '../layouts/admin/admin_layout.dart';
import '../layouts/driver/driver_layout.dart';
import '../layouts/oic/oic_layout.dart';
import '../layouts/staff/staff_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showPassword = false;
  bool _isDarkMode = false;
  bool _isThemeLoaded = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // ValueNotifier drastically improves performance by avoiding full widget rebuilds on hover
  final ValueNotifier<Alignment> _mouseAlignment = ValueNotifier(
    Alignment.center,
  );

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _isThemeLoaded = true;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  Future<void> _handleLogin() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please fill in all fields.', Colors.orange.shade700);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final navigator = Navigator.of(context);
    bool isLoadingDismissed = false;

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (mounted) {
        navigator.pop();
        isLoadingDismissed = true;
      }

      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final userData = responseData['data'];
        final String rawRole = (userData['role'] ?? '').toString();
        final String role = rawRole.trim().toLowerCase();

        if (role == 'admin') {
          final String realAdminId =
              (userData['user_id'] ?? userData['id'] ?? '').toString();
          final String adminDisplayName =
              (userData['name'] ?? userData['full_name'] ?? 'Admin').toString();

          await SessionManager.saveUserSession(
            'admin',
            realAdminId,
            adminDisplayName,
            'GT LANTIN',
          );

          if (mounted) {
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (context) => AdminLayout(
                  adminId: realAdminId,
                  adminName: adminDisplayName,
                ),
              ),
            );
          }
        } else if (role == 'oic') {
          final String realUserId =
              (userData['user_id'] ?? userData['id'] ?? '').toString();
          final String oicDisplayName =
              (userData['name'] ?? userData['full_name'] ?? 'OIC').toString();
          final String oicCompany = (userData['company'] ?? 'Internal')
              .toString();

          await SessionManager.saveUserSession(
            'oic',
            realUserId,
            oicDisplayName,
            oicCompany,
          );

          if (mounted) {
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (context) => OicLayout(
                  oicId: realUserId,
                  oicName: oicDisplayName,
                  companyName: oicCompany,
                ),
              ),
            );
          }
        } else if (role == 'staff') {
          final String realUserId =
              (userData['user_id'] ?? userData['id'] ?? '').toString();
          final String staffDisplayName =
              (userData['name'] ?? userData['full_name'] ?? 'Staff Member')
                  .toString();
          final String staffCompany = (userData['company'] ?? 'Internal')
              .toString();

          await SessionManager.saveUserSession(
            'staff',
            realUserId,
            staffDisplayName,
            staffCompany,
          );

          if (mounted) {
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (context) => StaffLayout(
                  staffId: realUserId,
                  staffName: staffDisplayName,
                  companyName: staffCompany,
                ),
              ),
            );
          }
        } else if (role == 'driver') {
          final String realUserId =
              (userData['user_id'] ?? userData['id'] ?? '').toString();
          final String driverDisplayName =
              (userData['name'] ?? userData['full_name'] ?? 'Driver')
                  .toString();
          final String driverCompany = (userData['company'] ?? 'Internal')
              .toString();

          await SessionManager.saveUserSession(
            'driver',
            realUserId,
            driverDisplayName,
            driverCompany,
          );

          if (mounted) {
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (context) => DriverLayout(
                  driverId: realUserId,
                  driverName: driverDisplayName,
                  companyName: driverCompany,
                ),
              ),
            );
          }
        } else {
          _showSnackBar(
            'Unrecognized user role assigned.',
            Colors.red.shade600,
          );
        }
      } else {
        final errorMsg = responseData['message'] ?? 'Authentication failed.';
        _showSnackBar(errorMsg, Colors.red.shade600);
      }
    } catch (e) {
      if (mounted && !isLoadingDismissed) navigator.pop();
      _showSnackBar(
        'Unable to connect to the backend server.',
        Colors.red.shade600,
      );
      debugPrint("❌ Login execution fault logged: $e");
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _mouseAlignment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isThemeLoaded)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final size = MediaQuery.of(context).size;

    final lightTheme = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      useMaterial3: true,
    );

    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B82F6),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      useMaterial3: true,
    );

    final currentTheme = _isDarkMode ? darkTheme : lightTheme;
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = _isDarkMode
        ? Colors.grey.shade400
        : Colors.grey.shade600;

    final cardBgColor = _isDarkMode
        ? Colors.white.withOpacity(0.05)
        : Colors.white.withOpacity(0.85);
    final cardBorderColor = _isDarkMode
        ? Colors.white.withOpacity(0.1)
        : Colors.blue.shade100;

    return Theme(
      data: currentTheme,
      child: Scaffold(
        body: MouseRegion(
          onHover: (PointerHoverEvent event) {
            final alignX = (event.position.dx / size.width) * 2 - 1;
            final alignY = (event.position.dy / size.height) * 2 - 1;
            _mouseAlignment.value = Alignment(alignX, alignY);
          },
          child: Stack(
            children: [
              // ValueListenableBuilder restricts rebuilds to just the background, eliminating lag
              ValueListenableBuilder<Alignment>(
                valueListenable: _mouseAlignment,
                builder: (context, alignment, child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: alignment,
                        radius: 1.5,
                        colors: _isDarkMode
                            ? [
                                Colors.white.withOpacity(
                                  0.15,
                                ), // Distinct white glow
                                const Color(0xFF1E293B),
                                const Color(0xFF020617), // Darker edge
                              ]
                            : [
                                Colors.white, // Bright white center
                                const Color(0xFFDBEAFE),
                                const Color(
                                  0xFF60A5FA,
                                ), // Darker blue edge for obvious contrast
                              ],
                        stops: const [0.0, 0.35, 1.0],
                      ),
                    ),
                  );
                },
              ),

              Positioned(
                top: -100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.withOpacity(_isDarkMode ? 0.1 : 0.05),
                    backgroundBlendMode: _isDarkMode
                        ? BlendMode.screen
                        : BlendMode.multiply,
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),

              // Centered Login Modal
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40.0,
                          vertical: 48.0,
                        ),
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: cardBorderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(
                                _isDarkMode ? 0.4 : 0.05,
                              ),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _isDarkMode
                                    ? const Color(0xFF1E293B)
                                    : Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.2),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  './assets/logo.jpg',
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.business,
                                        size: 50,
                                        color: Colors.blue.shade400,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Image.asset(
                              './assets/shervice.jpg',
                              height: 60,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
                                    "SHERVICE",
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: textColor,
                                      letterSpacing: 2,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Welcome back. Sign in to continue.",
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 40),

                            _buildTextField(
                              controller: _emailController,
                              label: "Email Address",
                              icon: Icons.email_outlined,
                              isDarkMode: _isDarkMode,
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: _passwordController,
                              label: "Password",
                              icon: Icons.lock_outline,
                              isPassword: true,
                              isDarkMode: _isDarkMode,
                            ),
                            const SizedBox(height: 32),

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  elevation: _isDarkMode ? 0 : 4,
                                  shadowColor: Colors.blue.withOpacity(0.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  "Log In",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              "GT LANTIN SHUTTLE SERVICES",
                              style: TextStyle(
                                fontSize: 11,
                                color: subtitleColor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Theme toggle repositioned to bottom right and made smaller
              Positioned(
                bottom: 24,
                right: 24,
                child: GestureDetector(
                  onTap: _toggleTheme,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isDarkMode
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: cardBorderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isDarkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: 18,
                      color: _isDarkMode
                          ? Colors.blue.shade300
                          : Colors.orange.shade400,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDarkMode,
    bool isPassword = false,
  }) {
    final inputFillColor = isDarkMode
        ? const Color(0xFF0F172A).withOpacity(0.5)
        : Colors.grey.shade50.withOpacity(0.5);
    final borderColor = isDarkMode
        ? Colors.grey.shade700
        : Colors.grey.shade300;

    return TextField(
      controller: controller,
      obscureText: isPassword && !_showPassword,
      keyboardType: isPassword
          ? TextInputType.text
          : TextInputType.emailAddress,
      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        filled: true,
        fillColor: inputFillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                  size: 20,
                  color: isDarkMode
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              )
            : null,
      ),
    );
  }
}
