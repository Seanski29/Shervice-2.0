import 'package:flutter/material.dart';
import '../../widgets/staff/attendance.dart';

class StaffReportsManager extends StatelessWidget {
  const StaffReportsManager({super.key});

  @override
  Widget build(BuildContext context) {
    return const Attendance(userRole: 'staff');
  }
}
