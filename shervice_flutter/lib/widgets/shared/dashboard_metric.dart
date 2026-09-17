import 'package:flutter/material.dart';

class DashboardMetric {
  final String title;
  final String value;
  final String subTitle;
  final IconData icon;
  final Color baseColor;

  const DashboardMetric({
    required this.title,
    required this.value,
    required this.subTitle,
    required this.icon,
    required this.baseColor,
  });
}