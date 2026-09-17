class DriverProfileModel {
  final String id;
  final String userId;
  final String name;
  final String email;
  final String licenseNumber;
  final String birthday;
  final double rating;
  final String status;
  final String dateHired;
  final String licenseExpiry;

  const DriverProfileModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.licenseNumber,
    required this.birthday,
    required this.rating,
    required this.status,
    required this.dateHired,
    required this.licenseExpiry,
  });

  factory DriverProfileModel.fromJson(Map<String, dynamic> json) {
    return DriverProfileModel(
      id: (json['driver_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      name: (json['full_name'] ?? 'Unnamed Driver').toString(),
      email:
          (json['username'] ??
                  json['email'] ??
                  json['Username'] ??
                  json['Email'] ??
                  'No Email Linked')
              .toString(),
      licenseNumber: (json['license_no'] ?? json['license_number'] ?? 'N/A')
          .toString(),
      birthday: (json['birthday'] ?? '1995-05-15').toString(),
      rating: double.tryParse(json['rating']?.toString() ?? '5.0') ?? 5.0,
      status: (json['employment_status'] ?? json['status'] ?? 'Active')
          .toString(),
      dateHired: (json['date_hired'] ?? 'Not Recorded').toString(),
      licenseExpiry: (json['license_expiry'] ?? '2031-12-31').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'driver_id': id,
      'user_id': userId,
      'full_name': name,
      'license_no': licenseNumber,
      'birthday': birthday,
      'rating': rating,
      'employment_status': status,
      'date_hired': dateHired,
      'license_expiry': licenseExpiry,
    };
  }
}