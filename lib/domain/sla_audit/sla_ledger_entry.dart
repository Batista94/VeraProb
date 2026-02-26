import 'package:equatable/equatable.dart';

/// The ultimate forensic asset for SLA Audit.
///
/// Represents an immutable historical fact that occurred in the SLA domain.
/// Unlike [DomainEvent], this is designed for long-term forensic storage
/// and is mapped from application-layer decisions.
class SlaLedgerEntry extends Equatable {
  /// Monotonic sequence ID from the database.
  /// Null if not yet persisted.
  final int? id;

  /// Forensic type of the entry (e.g., 'PLAN_DECLARED', 'EXECUTION_BOUND').
  final String type;

  /// Causal linkage: The specific obligation (SET) this entry refers to.
  /// For plan-level events, this might be null or represent the whole declaration.
  final String? setId;

  /// Causal linkage: The contract this obligation belongs to.
  final String contractId;

  /// Causal linkage: The specific version of the plan declaration.
  final int planVersion;

  /// The timestamp in UTC when the fact occurred.
  final DateTime occurredAtUtc;

  /// Complementary forensic data in a structured but flexible format.
  final Map<String, dynamic> payload;

  const SlaLedgerEntry({
    this.id,
    required this.type,
    this.setId,
    required this.contractId,
    required this.planVersion,
    required this.occurredAtUtc,
    this.payload = const {},
  });

  @override
  List<Object?> get props => [
    id,
    type,
    setId,
    contractId,
    planVersion,
    occurredAtUtc,
    payload,
  ];
}
