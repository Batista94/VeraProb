enum DriverStatus { active, inactive, pending }

class Driver {
  final String id;
  final String name;
  final String licenseNumber;
  final DriverStatus status;

  const Driver({
    required this.id,
    required this.name,
    required this.licenseNumber,
    this.status = DriverStatus.active,
  });

  Driver copyWith({
    String? id,
    String? name,
    String? licenseNumber,
    DriverStatus? status,
  }) {
    return Driver(
      id: id ?? this.id,
      name: name ?? this.name,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      status: status ?? this.status,
    );
  }

  // Equatable-like behavior for value comparison
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Driver && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
