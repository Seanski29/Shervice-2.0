class DriverProfileModel {
  final dynamic id;
  final String userId;
  final String name;
  final String birthday;
  final String phoneNumber;
  final String dateHired;
  final String status;
  final String isBackup;
  final String? mlClassification;

  DriverProfileModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.birthday,
    required this.phoneNumber,
    required this.dateHired,
    required this.status,
    this.isBackup = 'No',
    this.mlClassification,
  });

  factory DriverProfileModel.fromJson(Map<String, dynamic> json) {
    return DriverProfileModel(
      id: json['driver_id'] ?? json['id'] ?? 0,
      userId: json['user_id']?.toString() ?? '',
      name: json['full_name'] ?? json['name'] ?? 'Unknown Driver',
      birthday: json['birthday']?.toString() ?? '1995-05-15',
      phoneNumber:
          json['phone_no']?.toString() ??
          json['phoneNumber']?.toString() ??
          '09123456789',
      dateHired: json['date_hired']?.toString() ?? '2024-01-01',
      status: json['employment_status'] ?? json['status'] ?? 'Active',
      isBackup: json['is_backup'] ?? 'No',
      mlClassification: json['ml_classification']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'driver_id': id,
      'user_id': userId,
      'full_name': name,
      'birthday': birthday,
      'phone_no': phoneNumber,
      'date_hired': dateHired,
      'employment_status': status,
      'is_backup': isBackup,
      'ml_classification': mlClassification,
    };
  }
}
