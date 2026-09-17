import 'package:flutter/material.dart';

class MaintenanceAlert {
  final String vehicleId;
  final String description;
  final int daysRemaining;
  final double structuralValue;
  final Color severityColor;

  const MaintenanceAlert({
    required this.vehicleId,
    required this.description,
    required this.daysRemaining,
    required this.structuralValue,
    required this.severityColor,
  });

  factory MaintenanceAlert.fromJson(Map<String, dynamic> json) {
    final String status = json['health_status'] ?? 'Maintenance Required';
    Color color = Colors.orange;
    double val = 0.75;
    int days = 5;

    // Preserve your predictive telemetry constraints from earlier configurations
    if (status == 'Critical' || json['plate_number'] == 'GT-VAN-014') {
      color = Colors.red;
      val = 0.9;
      days = 2;
    }

    return MaintenanceAlert(
      vehicleId: json['plate_number'] ?? 'Unknown Asset',
      description: json['description'] ?? 'Vehicle flagged for maintenance. System diagnostics overhaul required.',
      daysRemaining: days,
      structuralValue: val,
      severityColor: color,
    );
  }
}