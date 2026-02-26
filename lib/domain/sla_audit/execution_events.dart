import 'domain_event.dart';

/// Emitted when a vehicle is successfully bound to a contractual obligation.
class ExecutionBoundEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final String vehicleId;
  final DateTime bindingTimestampUtc;
  final double bindingLatitude;
  final double bindingLongitude;

  const ExecutionBoundEvent({
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.vehicleId,
    required this.bindingTimestampUtc,
    required this.bindingLatitude,
    required this.bindingLongitude,
  });
}

/// Emitted when a contractual obligation is declared as a no-show
/// (time window expired with no matching vehicle).
class NoShowDeclaredEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final DateTime declaredAtUtc;

  const NoShowDeclaredEvent({
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.declaredAtUtc,
  });
}

/// Emitted when a contractual obligation is declared as an evidence gap
/// (insufficient telemetry to determine execution).
class EvidenceGapDeclaredEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final DateTime declaredAtUtc;

  const EvidenceGapDeclaredEvent({
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.declaredAtUtc,
  });
}
