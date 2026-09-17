class CompanyTripMetric {
  final String companyName;
  final int tripCount;
  final double utilization;

  const CompanyTripMetric({
    required this.companyName,
    required this.tripCount,
    required this.utilization,
  });

  factory CompanyTripMetric.fromJson(Map<String, dynamic> json) {
    return CompanyTripMetric(
      companyName: json['company_name'] ?? 'Unknown Client',
      tripCount: int.tryParse(json['trip_count']?.toString() ?? '0') ?? 0,
      utilization: (double.tryParse(json['utilization']?.toString() ?? '0.0') ?? 0.0).clamp(0.0, 1.0),
    );
  }
}