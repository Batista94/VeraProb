// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'package:equatable/equatable.dart';

import 'justification_status.dart';
import 'sla_justification_category.dart';

/// Aggregate Root for a driver's defense submission against a specific
/// infraction event detected by the OperationalStateNormalizer (CX-04).
///
/// **Forensic Anchor:** [vehicleId] + [occurrenceTimestamp] form the immutable
/// linkage to the original `VehicleOperationalState.stateChangedAt`. These
/// fields are excluded from [copyWith] to guarantee forensic integrity —
/// an auditor can always trace a justification back to the exact physical
/// event that triggered it.
///
/// **CX05-INV-21 (State Immutability):** Approval of this justification
/// NEVER alters the underlying `VehicleOperationalState`. It only toggles
/// `isPenaltyActive` in the SLA penalty engine.
///
/// Identity-based equality: two instances with the same [id] are equal
/// regardless of review state.
class SLAJustification extends Equatable {
  final String id;
  final String organizationId;

  /// Forensic anchor — the vehicle that generated the infraction event.
  final String vehicleId;

  /// Forensic anchor — maps to `VehicleOperationalState.stateChangedAt`.
  /// Immutable after creation. The Red Team auditor verifies this is never
  /// tampered with.
  final DateTime occurrenceTimestamp;

  final SLAJustificationCategory category;

  /// Minimum 10 characters (validated in SubmitJustificationHandler).
  final String description;

  /// Links to photos/documents in Supabase Storage.
  /// Each entry has a corresponding SHA-256 hash in [evidenceHashes]
  /// for forensic sealing (CX05-INV-23).
  final List<String> evidenceUrls;

  /// SHA-256 hex digests computed from the raw file bytes BEFORE upload
  /// to Supabase Storage. Guarantees evidence was not replaced post-submission.
  /// Must have the same length as [evidenceUrls].
  final List<String> evidenceHashes;

  final JustificationStatus status;
  final DateTime createdAt;

  /// Non-null after review by a Gestor (APPROVED or REJECTED).
  final String? reviewerId;

  /// Free-text notes from the reviewer explaining the decision.
  final String? resolutionNotes;

  const SLAJustification({
    required this.id,
    required this.organizationId,
    required this.vehicleId,
    required this.occurrenceTimestamp,
    required this.category,
    required this.description,
    required this.evidenceUrls,
    required this.evidenceHashes,
    required this.status,
    required this.createdAt,
    required this.reviewerId,
    required this.resolutionNotes,
  });

  bool get isPending => status == JustificationStatus.pending;
  bool get isApproved => status == JustificationStatus.approved;
  bool get isRejected => status == JustificationStatus.rejected;
  bool get isExpired => status == JustificationStatus.expired;

  /// Only review fields may change after creation.
  /// [vehicleId], [occurrenceTimestamp], [evidenceUrls], [evidenceHashes] are
  /// deliberately excluded to preserve forensic integrity.
  SLAJustification copyWith({
    JustificationStatus? status,
    String? reviewerId,
    String? resolutionNotes,
  }) {
    return SLAJustification(
      id: id,
      organizationId: organizationId,
      vehicleId: vehicleId,
      occurrenceTimestamp: occurrenceTimestamp,
      category: category,
      description: description,
      evidenceUrls: evidenceUrls,
      evidenceHashes: evidenceHashes,
      status: status ?? this.status,
      createdAt: createdAt,
      reviewerId: reviewerId ?? this.reviewerId,
      resolutionNotes: resolutionNotes ?? this.resolutionNotes,
    );
  }

  /// Identity-based equality — props contains only [id] so that a pending
  /// and an approved instance of the same justification compare as equal,
  /// consistent with aggregate root semantics.
  @override
  List<Object?> get props => [id];
}
