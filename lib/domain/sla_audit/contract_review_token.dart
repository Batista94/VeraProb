import 'package:equatable/equatable.dart';

/// Value object representing a time-limited, single-use token that grants
/// a contractor public access to review and accept a specific contract.
///
/// Token possession is the sole authorization for the acceptance operation
/// (zero-trust, mirrors the Invitation pattern from Block 5).
///
/// **Invariants:**
/// - [token] is a UUID v4 generated in Dart (INV-7: Deterministic Replay).
/// - [expiresAtUtc] is set at creation and never changes (INV-3: UTC).
/// - Acceptance stamps [usedAtUtc] — token is never deleted (INV-1: Immutable).
class ContractReviewToken extends Equatable {
  final String id;
  final String contractId;
  final String organizationId;

  /// The shareable secret embedded in the review URL.
  /// UUID v4 generated in Dart, passed to the DB RPC as a param.
  final String token;

  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;

  /// Null while the token is still active.
  /// Stamped when the contractor accepts — never deleted (INV-1).
  final DateTime? usedAtUtc;

  const ContractReviewToken({
    required this.id,
    required this.contractId,
    required this.organizationId,
    required this.token,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    this.usedAtUtc,
  });

  /// Returns `true` if the token has not been used and has not expired.
  bool get isActive =>
      usedAtUtc == null && DateTime.now().toUtc().isBefore(expiresAtUtc);

  @override
  List<Object?> get props => [
    id,
    contractId,
    organizationId,
    token,
    createdAtUtc,
    expiresAtUtc,
    usedAtUtc,
  ];
}
