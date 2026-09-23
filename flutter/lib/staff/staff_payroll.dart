import 'package:flutter/material.dart';

import '../9.payroll/payroll.dart';

class StaffPayroll extends StatelessWidget {
  const StaffPayroll({super.key});

  @override
  Widget build(BuildContext context) {
    return const Payroll(userRole: 'staff');
  }
}
