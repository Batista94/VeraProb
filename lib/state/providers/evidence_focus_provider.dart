import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Immutable geospatial focus point triggered by evidence interaction
/// (e.g., playing an audio evidence in the dossier).
///
/// Flows **unidirectionally**: [ForensicAudioPlayer] writes →
/// [TelemetrySyncMap] reads via [selectedEvidenceFocusProvider].
///
/// Position is resolved from the nearest telemetry point to
/// [timestamp] (telegram_message_date), NOT from the file itself (INV-18).
class EvidenceMapFocus {
  /// Evidence upload ID for toggle/deselection logic.
  final String evidenceId;

  /// Timestamp of the evidence (telegram_message_date).
  final DateTime timestamp;

  /// Vehicle position at [timestamp], resolved from telemetry.
  final LatLng position;

  const EvidenceMapFocus({
    required this.evidenceId,
    required this.timestamp,
    required this.position,
  });
}

/// Unidirectional state for evidence-to-map sync.
///
/// - **Writer:** [ForensicAudioPlayer] / evidence card (on tap/play)
/// - **Reader:** [TelemetrySyncMap] (via `ref.listen`)
/// - **Null:** No evidence focused → map unchanged.
final selectedEvidenceFocusProvider = StateProvider<EvidenceMapFocus?>(
  (ref) => null,
);
