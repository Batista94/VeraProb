class Driver {
  final String id;
  final String name;
  final String licenseNumber;

  const Driver({
    required this.id,
    required this.name,
    required this.licenseNumber,
  });

  // Equatable-like behavior for value comparison
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Driver && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
