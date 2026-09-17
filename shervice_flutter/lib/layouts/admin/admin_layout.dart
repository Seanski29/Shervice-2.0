import 'package:flutter/material.dart';
import 'admin_layout_desktop.dart';
import 'admin_layout_mobile.dart';

class AdminLayout extends StatelessWidget {
  final String adminId;
  final String adminName;

  const AdminLayout({
    super.key,
    required this.adminId,
    this.adminName = 'Admin',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          // 👇 Pass it to Desktop
          return AdminDesktopLayout(adminId: adminId, adminName: adminName);
        } else {
          // 👇 Pass it to Mobile
          return AdminMobileLayout(adminId: adminId, adminName: adminName);
        }
      },
    );
  }
}
