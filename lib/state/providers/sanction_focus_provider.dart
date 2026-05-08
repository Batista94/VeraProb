import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Immutable geospatial focus point selected by the auditor in the
/// Sanction Verdict Queue.
///
/// Flows **unidirectionally**: [SanctionVerdictCard] writes →
/// [TelemetrySyncMap] reads via [selectedSanctionFocusProvider].
///
/// INV-23 compliant: the map consuming this state is strictly read-only.
class SanctionMapFocus {
  /// Unique sanction ID for toggle/deselection logic.
  final String sanctionId;

  /// Vehicle/event position at the moment of the infraction.
  final LatLng infractionPoint;

  /// Optional geofence center (e.g., bus stop origin).
  final LatLng? geofenceCenter;

  /// Geofence radius in metres. Defaults to 50m.
  final double geofenceRadiusMeters;

  const SanctionMapFocus({
    required this.sanctionId,
    required this.infractionPoint,
    this.geofenceCenter,
    this.geofenceRadiusMeters = 50.0,
  });
}

/// Unidirectional state for the Telemetry Map-Sync feature (WS-5).
///
/// - **Writer:** [SanctionVerdictCard] (on tap)
/// - **Reader:** [TelemetrySyncMap] (via `ref.listen`)
/// - **Null:** No sanction selected → map shows default overview.
class _SelectedSanctionFocusNotifier extends Notifier<SanctionMapFocus?> {
  @override
  SanctionMapFocus? build() => null;

  void set(SanctionMapFocus? value) => state = value;
}

final selectedSanctionFocusProvider =
    NotifierProvider<_SelectedSanctionFocusNotifier, SanctionMapFocus?>(
      _SelectedSanctionFocusNotifier.new,
    );
