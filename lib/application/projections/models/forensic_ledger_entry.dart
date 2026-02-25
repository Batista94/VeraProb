import 'package:equatable/equatable.dart';

/// DTO representing a structured, read-only view of a Forensic Decision
///
/// This is used by the UI Projection layer to display audit logs
/// without coupling the Presentation layer to core Domain entities.
class ForensicLedgerEntry extends Equatable {
  final String decisionId;
  final String actionType;
  final String actorId;
  final String result;
  final DateTime timestamp;

  const ForensicLedgerEntry({
    required this.decisionId,
    required this.actionType,
    required this.actorId,
    required this.result,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [
    decisionId,
    actionType,
    actorId,
    result,
    timestamp,
  ];
}
