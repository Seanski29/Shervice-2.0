import 'package:flutter/material.dart';
import 'oic_layout_desktop.dart';
import '../mobile_access_unavailable.dart';

class OicLayout extends StatelessWidget {
  final String oicId;
  final String oicName;
  final String companyName;

  const OicLayout({
    super.key,
    required this.oicId,
    required this.oicName,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return OicLayoutDesktop(
            oicId: oicId,
            oicName: oicName,
            companyName: companyName,
          );
        }

        return const MobileAccessUnavailable(role: 'OIC');
      },
    );
  }
}
