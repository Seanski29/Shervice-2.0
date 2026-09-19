import 'package:flutter/material.dart';

import 'admin_layout_desktop.dart';

/// Compatibility entry point. The enterprise shell is responsive and owns
/// both desktop and compact navigation behavior.
class AdminMobileLayout extends StatelessWidget {
  const AdminMobileLayout({
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
