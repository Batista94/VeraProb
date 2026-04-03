import 'package:equatable/equatable.dart';

import 'justification_category.dart';
import 'justification_status.dart';

/// Aggregate Root for a contractor's defense submission against a specific
/// SLA breach factEvent (identified by [setId] + [contractId]).
///
/// Identity-based equality: two instances with the same [id] are equal
/// regardless of review state — callers should compare [status] explicitly.
///
/// [copyWith] only exposes the review fields that may legitimately change
/// after creation (INV-7): [status], [reviewedByUserId], [reviewedAtUtc].
class ContractorJustification extends Equatable {
  final String id;
  final String organizationId;
  final String contractId;
  final String setId;

  /// Non-null when submitted via tokenized driver self-service path.
  /// Null when entered manually by an operator.
  final String? submittedByToken;

  final JustificationCategory category;
  final String description;
  final JustificationStatus status;

  final String? reviewedByUserId;
  final DateTime? reviewedAtUtc;
  final DateTime createdAtUtc;

  const ContractorJustification({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.setId,
    required this.submittedByToken,
    required this.category,
    required this.description,
    required this.status,
    required this.reviewedByUserId,
    required this.reviewedAtUtc,
    required this.createdAtUtc,
  });

  bool get isPending => status == JustificationStatus.pending;
  bool get isApproved => status == JustificationStatus.approved;
  bool get isRejected => status == JustificationStatus.rejected;

  ContractorJustification copyWith({
    JustificationStatus? status,
    String? reviewedByUserId,
    DateTime? reviewedAtUtc,
  }) {
    return ContractorJustification(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      setId: setId,
      submittedByToken: submittedByToken,
      category: category,
      description: description,
      status: status ?? this.status,
      reviewedByUserId: reviewedByUserId ?? this.reviewedByUserId,
      reviewedAtUtc: reviewedAtUtc ?? this.reviewedAtUtc,
      createdAtUtc: createdAtUtc,
    );
  }

  /// Identity-based equality — props contains only [id] so that a pending
  /// and an approved instance of the same justification compare as equal,
  /// consistent with aggregate root semantics.
  @override
  List<Object?> get props => [id];
}
