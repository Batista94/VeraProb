/// Port: Core → Module boundary for contractual evidence dispatch.
///
/// Allows Core services (e.g. SimulationControlService) to publish
/// operational evidence facts without depending on any module implementation.
///
/// Implemented by the Transport module in:
/// lib/application/sla_audit/sla_contractual_event_port.dart
abstract class ContractualEventPort {
  /// Dispatches evidence that a trip was manually interrupted by an operator.
  Future<void> dispatchTripInterrupted({
    required String organizationId,
    required String tripId,
    String? vehicleId,
    required String operatorId,
    String? reason,
    required DateTime occurredAtUtc,
  });

  /// Dispatches evidence that a trip was manually cancelled by an operator.
  Future<void> dispatchTripCancelled({
    required String organizationId,
    required String tripId,
    String? vehicleId,
    required String operatorId,
    String? reason,
    required DateTime occurredAtUtc,
  });

  /// Dispatches evidence that an operator registered a manual occurrence.
  Future<void> dispatchOccurrenceRegistered({
    required String organizationId,
    required String tripId,
    String? vehicleId,
    required String operatorId,
    required String occurrenceType,
    String? notes,
    required Map<String, dynamic> metadata,
    required DateTime occurredAtUtc,
  });
}
