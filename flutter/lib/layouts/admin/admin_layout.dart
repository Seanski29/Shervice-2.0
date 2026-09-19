import 'package:flutter/material.dart';

import 'admin_layout_desktop.dart';

class AdminLayout extends StatelessWidget {
  const AdminLayout({
    super.key,
    required this.adminId,
    this.adminName = 'Admin',
  });

  final String adminId;
  final String adminName;

  @override
  Widget build(BuildContext context) {
    return AdminDesktopLayout(adminId: adminId, adminName: adminName);
  }
}
