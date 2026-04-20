import 'infraction_recurrence_report.dart';
import 'sanction_review_queue_entry.dart';
import 'vehicle_infraction_recurrence_repository.dart';

/// Domain service that computes the monthly recurrence context for a vehicle.
///
/// INV-18: Pure Dart — zero Flutter/Supabase dependencies.
/// INV-9: [referenceUtc] MUST be UTC (asserted at runtime).
class VehicleInfractionRecurrenceService {
  final VehicleInfractionRecurrenceRepository _repository;

  const VehicleInfractionRecurrenceService({
    required VehicleInfractionRecurrenceRepository repository,
  }) : _repository = repository;

  /// Computes recurrence context for [vehiclePlate] in the month of
  /// [referenceUtc].
  ///
  /// Returns `null` if [vehiclePlate] is null or empty — no plate means no
  /// recurrence context can be shown.
  ///
  /// Otherwise, returns an [InfractionRecurrenceReport] where
  /// [InfractionRecurrenceReport.infractionNumberThisMonth] is
  /// `priorCount + 1` and [InfractionRecurrenceReport.priorInfractions] lists
  /// all prior entries in ascending chronological order.
  Future<InfractionRecurrenceReport?> computeRecurrence({
    required String organizationId,
    required String? vehiclePlate,
    required DateTime referenceUtc,
    required String currentQueueEntryId,
  }) async {
    if (vehiclePlate == null || vehiclePlate.isEmpty) return null;
    assert(referenceUtc.isUtc, 'referenceUtc must be UTC (INV-9)');

    final priors = await _repository.findByPlateInMonth(
      organizationId: organizationId,
      vehiclePlate: vehiclePlate,
      referenceUtc: referenceUtc,
      excludeQueueEntryId: currentQueueEntryId,
    );

    final dots = priors.map(_toDot).toList();

    return InfractionRecurrenceReport(
      vehiclePlate: vehiclePlate,
      infractionNumberThisMonth: dots.length + 1,
      priorInfractions: dots,
    );
  }

  PriorInfractionDot _toDot(SanctionReviewQueueEntry entry) {
    return PriorInfractionDot(
      occurredAtUtc: entry.createdAtUtc,
      clauseRef: entry.verdictEvidence.clauseRef,
    );
  }
}
