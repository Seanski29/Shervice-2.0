import 'package:flutter/material.dart';
import 'driver_layout_mobile.dart';

class DriverLayout extends StatelessWidget {
  final String driverId; // 👈 1. Add this
  final String driverName;
  final String companyName;

  const DriverLayout({
    super.key,
    required this.driverId, // 👈 2. Require this
    required this.driverName,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          final phoneWidth = constraints.maxWidth < 420
              ? constraints.maxWidth - 24
              : 390.0;
          final phoneHeight = constraints.maxHeight.isFinite
              ? (constraints.maxHeight - 24).clamp(1.0, 844.0)
              : 844.0;
          return ColoredBox(
            color: const Color(0xFFCBD5E1),
            child: Center(
              child: Container(
                width: phoneWidth,
                height: phoneHeight,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: DriverLayoutMobile(
                    driverId: driverId,
                    driverName: driverName,
                    companyName: companyName,
                  ),
                ),
              ),
            ),
          );
        }
        return DriverLayoutMobile(
          driverId: driverId, // 👈 3. Pass it down
          driverName: driverName,
          companyName: companyName,
        );
      },
    );
  }
}
