import 'package:http/http.dart' as http;
import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';
import 'package:veraprob/domain/reporting/i_static_map_service.dart';
import 'package:veraprob/infrastructure/config/environment.dart';

/// MapTiler-backed implementation of [IStaticMapService].
///
/// Fetches a static PNG map tile for the given coordinates using the
/// MapTiler Static Maps API. Throws [PdfGenerationException] if the
/// HTTP response is not 200.
///
/// Physical Metric - Double Required (INV-12): [lat] and [lng] are geographic
/// coordinates and must not be rounded to integer precision.
class MapTilerStaticMapService implements IStaticMapService {
  final http.Client _httpClient;

  MapTilerStaticMapService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  @override
  Future<List<int>> getStaticMap({
    required num lat,
    required num lng,
    required int zoom,
  }) async {
    const key = EnvironmentConfig.mapTilerKey;
    final url = Uri.parse(
      'https://api.maptiler.com/maps/streets-v2/static/'
      '$lng,$lat,$zoom/600x400.png?key=$key',
    );

    try {
      final response = await _httpClient.get(url);
      if (response.statusCode != 200) {
        throw PdfGenerationException(
          'MapTiler API returned HTTP ${response.statusCode} for static map request.',
        );
      }
      return response.bodyBytes.toList();
    } on PdfGenerationException {
      rethrow;
    } catch (e) {
      throw PdfGenerationException(
        'Failed to fetch static map: ${e.toString()}',
      );
    }
  }
}
