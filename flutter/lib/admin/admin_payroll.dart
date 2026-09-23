import 'package:flutter/material.dart';

import '../9.payroll/payroll.dart';

class AdminPayroll extends StatelessWidget {
  const AdminPayroll({super.key});

  @override
  Widget build(BuildContext context) {
    return const Payroll(userRole: 'admin');
  }
}
