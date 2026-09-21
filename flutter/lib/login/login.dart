import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constant.dart';
import '../layouts/admin/admin_layout.dart';
import '../layouts/staff/staff_layout.dart';
import '../session_manager.dart';
import '../layouts/enterprise/enterprise_theme.dart';
import '../theme/theme_manager.dart';
import '../utils/network_status_monitor.dart';
import '../layouts/enterprise/enterprise_states.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _isDarkMode = false;
  bool _isThemeLoaded = false;
  bool _isSubmitting = false;
  String? _emailError;
  String? _passwordError;
  String? _authenticationError;
  final ValueNotifier<Alignment> _mouseAlignment = ValueNotifier(
    Alignment.center,
  );

  @override
  void initState() {
    super.initState();
    NetworkStatusMonitor.start();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    await ThemeManager.loadSavedTheme();
    if (!mounted) return;
    setState(() {
      _isDarkMode = ThemeManager.isDark;
      _isThemeLoaded = true;
    });
  }

  Future<void> _toggleTheme() async {
    final nextValue = !_isDarkMode;
    setState(() => _isDarkMode = nextValue);
    await ThemeManager.setDarkMode(nextValue);
  }

  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _emailError = email.isEmpty
          ? 'Email address is required.'
          : !email.contains('@')
          ? 'Enter a valid corporate email address.'
          : null;
      _passwordError = password.isEmpty ? 'Password is required.' : null;
      _authenticationError = null;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _handleLogin() async {
    if (!_validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _emailController.text.trim(),
              'password': _passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 12));
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || responseData['success'] != true) {
        throw _AuthenticationException(
          (responseData['message'] ?? 'Authentication failed.').toString(),
        );
      }

      final userData = Map<String, dynamic>.from(responseData['data'] as Map);
      final role = (userData['role'] ?? '').toString().trim().toLowerCase();
      final userId = (userData['user_id'] ?? userData['id'] ?? '').toString();
      final displayName = (userData['name'] ?? userData['full_name'] ?? 'User')
          .toString();
      if (role != 'admin' && role != 'staff') {
        throw const _AuthenticationException(
          'Only Admin and Staff accounts can access this workspace.',
        );
      }

      final company = role == 'admin'
          ? 'GT LANTIN'
          : (userData['company'] ?? 'Internal').toString();
      await SessionManager.saveUserSession(role, userId, displayName, company);
      await ThemeManager.loadSavedTheme(userId: userId);
      if (!mounted) return;
      EnterpriseToasts.success(context, 'Signed in successfully.');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => role == 'admin'
              ? AdminLayout(adminId: userId, adminName: displayName)
              : StaffLayout(
                  staffId: userId,
                  staffName: displayName,
                  companyName: company,
                ),
        ),
      );
    } on _AuthenticationException catch (error) {
      if (!mounted) return;
      setState(() => _authenticationError = error.message);
      EnterpriseToasts.error(context, error.message);
    } catch (error) {
      if (!mounted) return;
      const message =
          'Shervice could not reach the authentication service. Check the connection and retry.';
      setState(() => _authenticationError = message);
      EnterpriseToasts.error(context, message);
      debugPrint('Login request failed: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
    final theme = _isDarkMode
        ? EnterpriseTheme.dark()
        : EnterpriseTheme.light();
    if (!_isThemeLoaded) {
      return Theme(
        data: theme,
        child: const Scaffold(
          body: Center(
            child: SizedBox(width: 420, child: EnterpriseFormSkeleton()),
          ),
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = _isDarkMode
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    final cardColor = _isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.86);
    final borderColor = _isDarkMode
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.blue.shade100;

    return Theme(
      data: theme,
      child: Scaffold(
        body: MouseRegion(
          onHover: (PointerHoverEvent event) {
            if (size.width == 0 || size.height == 0) return;
            _mouseAlignment.value = Alignment(
              (event.position.dx / size.width) * 2 - 1,
              (event.position.dy / size.height) * 2 - 1,
            );
          },
          child: Stack(
            children: [
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
                                Colors.white.withValues(alpha: 0.12),
                                const Color(0xFF1E293B),
                                const Color(0xFF020617),
                              ]
                            : [
                                Colors.white,
                                const Color(0xFFDBEAFE),
                                const Color(0xFF60A5FA),
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
                    color: Colors.blue.withValues(
                      alpha: _isDarkMode ? 0.1 : 0.05,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 48,
                          ),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: _isDarkMode ? 0.4 : 0.05,
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
                                      color: Colors.blue.withValues(alpha: 0.2),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/logo.jpg',
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.contain,
                                    cacheWidth: 200,
                                    cacheHeight: 200,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.business,
                                      size: 50,
                                      color: Colors.blue.shade400,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Image.asset(
                                'assets/shervice.jpg',
                                height: 60,
                                fit: BoxFit.contain,
                                cacheWidth: 520,
                                cacheHeight: 120,
                                errorBuilder: (_, _, _) => Text(
                                  'SHERVICE',
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
                                'Welcome back. Sign in to continue.',
                                style: TextStyle(
                                  color: subtitleColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 40),
                              _buildTextField(
                                controller: _emailController,
                                label: 'Email Address',
                                icon: Icons.email_outlined,
                                isDarkMode: _isDarkMode,
                                errorText: _emailError,
                              ),
                              const SizedBox(height: 20),
                              _buildTextField(
                                controller: _passwordController,
                                label: 'Password',
                                icon: Icons.lock_outline,
                                isPassword: true,
                                isDarkMode: _isDarkMode,
                                errorText: _passwordError,
                              ),
                              if (_authenticationError != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _authenticationError!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isSubmitting
                                      ? null
                                      : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    elevation: _isDarkMode ? 0 : 4,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Log In',
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
                                'GT LANTIN SHUTTLE SERVICES',
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
              ),
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
                      border: Border.all(color: borderColor),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 4),
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
    String? errorText,
    bool isPassword = false,
  }) {
    final inputFillColor = isDarkMode
        ? const Color(0xFF0F172A).withValues(alpha: 0.5)
        : Colors.grey.shade50.withValues(alpha: 0.5);
    final borderColor = isDarkMode
        ? Colors.grey.shade700
        : Colors.grey.shade300;

    return TextField(
      controller: controller,
      obscureText: isPassword && !_showPassword,
      keyboardType: isPassword
          ? TextInputType.text
          : TextInputType.emailAddress,
      textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
      onSubmitted: isPassword && !_isSubmitting ? (_) => _handleLogin() : null,
      onChanged: (_) {
        if (errorText != null || _authenticationError != null) {
          setState(() {
            if (isPassword) {
              _passwordError = null;
            } else {
              _emailError = null;
            }
            _authenticationError = null;
          });
        }
      },
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
        errorText: errorText,
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

class _AuthenticationException implements Exception {
  const _AuthenticationException(this.message);

  final String message;
}
