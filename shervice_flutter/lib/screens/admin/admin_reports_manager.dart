import 'package:flutter/material.dart';
import '../../widgets/shared/shared_reports_manager.dart';

class AdminReportsManager extends StatelessWidget {
  const AdminReportsManager({super.key});

  @override
  Widget build(BuildContext context) {
    return const SharedReportsManager(
      userRole: 'admin',
    );
  }
}