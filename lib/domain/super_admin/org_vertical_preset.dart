// pr_scanner: ignore-regression
import 'package:veraprob/domain/admin/org_capabilities.dart';

/// Immutable constants for operational vertical presets.
///
/// INV-14: presets configure transport-agnostic capability flags — not enums.
/// Add new verticals here without touching handler or UI logic.
abstract final class OrgVerticalPreset {
  static const viacao = 'VIACAO';
  static const carga = 'CARGA';

  static const Map<String, String> labels = {
    viacao: 'Viação (Passageiros)',
    carga: 'Carga',
  };

  static const Map<String, OrgCapabilities> defaults = {
    viacao: OrgCapabilities(
      allowsSealing: false,
      allowsLoading: false,
      allowsCargoCheck: false,
      allowsIncident: true,
      allowsDoc: true,
      smartClassify: true,
      maxKinematicSpeedKmh: 80.0, // Physical Metric - Double Required
    ),
    carga: OrgCapabilities(
      allowsSealing: true,
      allowsLoading: true,
      allowsCargoCheck: true,
      allowsIncident: true,
      allowsDoc: true,
      smartClassify: true,
      maxKinematicSpeedKmh: 120.0, // Physical Metric - Double Required
    ),
  };
}
