import 'package:equatable/equatable.dart';

/// Single-use time-limited token that grants a driver unauthenticated access
/// to the justification submission form for a specific SET / contract.
///
/// Mirrors [ContractReviewToken] with the addition of [setId].
///
/// **Invariants:**
/// - [token] is a UUID v4 generated server-side (128-bit collision space — PO-1).
/// - [expiresAtUtc] is operator-configured at 1–72 hours (PO-6).
/// - Submission stamps [usedAtUtc] — token is never deleted (INV-7).
class JustificationSubmissionToken extends Equatable {
  final String id;
  final String organizationId;
  final String contractId;
  final String setId;

  /// FK to the [ContractorJustification] created when the token is consumed.
  /// Null until the driver submits the form.
  final String? justificationId;

  /// The shareable UUID embedded in the self-service URL.
  final String token;

  final String createdByUserId;
  final DateTime expiresAtUtc;

  /// Stamped once when the driver submits — never reset (INV-11).
  final DateTime? usedAtUtc;

  final DateTime createdAtUtc;

  const JustificationSubmissionToken({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.setId,
    required this.justificationId,
    required this.token,
    required this.createdByUserId,
    required this.expiresAtUtc,
    required this.usedAtUtc,
    required this.createdAtUtc,
  });

  /// Returns `true` if the token has not been used and has not expired.
  bool get isActive =>
      usedAtUtc == null && DateTime.now().toUtc().isBefore(expiresAtUtc);

  @override
  List<Object?> get props => [
    id,
    organizationId,
    contractId,
    setId,
    justificationId,
    token,
    createdByUserId,
    expiresAtUtc,
    usedAtUtc,
    createdAtUtc,
  ];
}
