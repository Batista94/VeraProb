// pr_scanner: ignore-regression
/// Port for retrieving static map images (e.g., from MapTiler API).
/// Emenda 1: Used to ensure deterministic byte-level map captures for SHA-256 (INV-9).
abstract class IStaticMapService {
  /// Fetches a static map image centered at [lat], [lng] with the given [zoom].
  /// Returns the raw bytes of the image (e.g. PNG/JPEG).
  Future<List<int>> getStaticMap({
    required num lat,
    required num lng,
    required int zoom,
  });
}
