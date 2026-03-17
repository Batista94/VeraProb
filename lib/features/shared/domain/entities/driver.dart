enum DriverStatus { active, inactive, pending }

class Driver {
  final String id;
  final String organizationId;
  final String name;
  final String licenseNumber;
  final DriverStatus status;

  const Driver({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.licenseNumber,
    this.status = DriverStatus.active,
  });

  Driver copyWith({
    String? id,
    String? organizationId,
    String? name,
    String? licenseNumber,
    DriverStatus? status,
  }) {
    return Driver(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      name: name ?? this.name,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Driver && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
