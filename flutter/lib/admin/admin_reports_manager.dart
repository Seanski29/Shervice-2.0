import 'package:flutter/material.dart';
import '../7.attendance/attendance.dart';

class AdminReportsManager extends StatelessWidget {
  const AdminReportsManager({super.key});

  @override
  Widget build(BuildContext context) {
    return const Attendance(userRole: 'admin');
  }
}
