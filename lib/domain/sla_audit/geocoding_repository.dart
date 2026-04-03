abstract class GeocodingRepository {
  Future<List<PlaceSuggestion>> search(String query);
}

class PlaceSuggestion {
  final String displayName;
  final double lat;
  final double lng;

  const PlaceSuggestion({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}
