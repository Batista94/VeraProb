import 'package:veraprob/domain/sla_audit/smart_defaults.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';

/// Application-layer wrapper around [SmartDefaults].
///
/// Converts domain defaults into [PenaltiesFormData] so that features/
/// never imports the domain layer for smart default logic.
abstract final class SmartDefaultsService {
  /// Returns recommended penalty form defaults for [vertical].
  static PenaltiesFormData defaultsFor(TransportVertical vertical) {
    return PenaltiesFormData.fromDomain(SmartDefaults.defaultsFor(vertical));
  }
}
