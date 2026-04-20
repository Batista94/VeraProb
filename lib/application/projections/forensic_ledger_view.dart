import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';

/// DTO representing a structured, read-only view of a Forensic Decision
///
/// This is used by the UI Projection layer to display audit logs
/// without coupling the Presentation layer to core Domain entities.
class ForensicLedgerEntry extends Equatable {
  final String decisionId;
  final String actionType;
  final String actionLabel;
  final String actorId;
  final String result;
  final String? reason;
  final String narrative;
  final DateTime timestamp;

  const ForensicLedgerEntry({
    required this.decisionId,
    required this.actionType,
    required this.actionLabel,
    required this.actorId,
    required this.result,
    this.reason,
    required this.narrative,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [
    decisionId,
    actionType,
    actionLabel,
    actorId,
    result,
    reason,
    narrative,
    timestamp,
  ];
}

/// Builds a narrative sentence from an [AuthorizationDecision].
///
/// This lives in the **Projection Layer** — never in the Domain or UI.
/// It translates raw domain events into human-readable operator language.
String toNarrative(AuthorizationDecision d) {
  final actor = d.actorId.value;
  final action = actionVerb(d.actionType.key);
  final result = d.result.name == 'approved' ? '' : ' (NEGADO)';
  final reason = (d.reason != null && d.reason!.isNotEmpty)
      ? ': ${d.reason}'
      : '';

  return '$actor $action$reason$result';
}

/// Maps action keys to Portuguese narrative verbs/phrases.
String actionVerb(String key) {
  const verbs = <String, String>{
    'resolve_alert': 'resolveu alerta',
    'manual_status_override': 'ajustou status manualmente',
    'reassign_vehicle': 'realocou veículo',
    'override_route_deviation': 'autorizou desvio de rota',
    'update_trip_status': 'alterou status de viagem',
    'create_incident': 'registrou ocorrência',
    'cancel_trip': 'cancelou viagem',
    'dispatch_trip': 'despachou viagem',
    'regularize_trip': 'autorizou regularização',
    'interrupt_trip': 'interrompeu viagem',
  };
  return verbs[key] ?? key.replaceAll('_', ' ');
}
