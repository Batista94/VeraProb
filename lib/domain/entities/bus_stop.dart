class BusStop {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? code;

  const BusStop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.code,
  });
}
