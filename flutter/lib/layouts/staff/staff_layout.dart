import 'package:flutter/material.dart';

import 'staff_layout_desktop.dart';

class StaffLayout extends StatelessWidget {
  const StaffLayout({
    super.key,
    required this.staffId,
    required this.staffName,
    required this.companyName,
  });

  final String staffId;
  final String staffName;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    return StaffLayoutDesktop(
      staffId: staffId,
      staffName: staffName,
      companyName: companyName,
    );
  }
}
