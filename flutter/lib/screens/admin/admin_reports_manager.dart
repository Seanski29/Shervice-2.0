import 'package:flutter/material.dart';
import '../../widgets/staff/attendance.dart';

class AdminReportsManager extends StatelessWidget {
  const AdminReportsManager({super.key});

  @override
  Widget build(BuildContext context) {
    return const Attendance(userRole: 'admin');
  }
}
