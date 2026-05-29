abstract class GeocodingRepository {
  Future<List<PlaceSuggestion>> search(String query);

  /// Resolves [lat]/[lng] to a human-readable address.
  ///
  /// Returns `null` when the location cannot be resolved.
  Future<String?> reverseGeocode(
    double lat, // Physical Metric - Double Required
    double lng, // Physical Metric - Double Required
  );
}

class PlaceSuggestion {
  final String displayName;
  final double lat; // Physical Metric - Double Required
  final double lng; // Physical Metric - Double Required

  const PlaceSuggestion({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}
