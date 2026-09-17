import 'package:flutter/material.dart';
import 'staff_layout_desktop.dart';
import '../mobile_access_unavailable.dart';

class StaffLayout extends StatelessWidget {
  final String staffId;
  final String staffName;
  final String companyName;

  const StaffLayout({
    super.key,
    required this.staffId,
    required this.staffName,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2. Add the mobile path
        if (constraints.maxWidth > 800) {
          return StaffLayoutDesktop(
            staffId: staffId,
            staffName: staffName,
            companyName: companyName,
          );
        }
        return const MobileAccessUnavailable(role: 'Staff');
      },
    );
  }
}
