import 'package:equatable/equatable.dart';

/// Result of a [ChainIntegrityVerifier.verify] call over a sequence of
/// [PendingFact] records.
///
/// **INV-18:** Pure Dart — zero Flutter / Supabase dependencies.
class ChainVerificationResult extends Equatable {
  /// `true` when all facts passed their individual [PendingFact.verifyIntegrity]
  /// check.
  final bool isValid;

  /// Position (0-based) of the first tampered fact; `null` when [isValid].
  final int? firstFailureIndex;

  /// [PendingFact.factId] of the first tampered fact; `null` when [isValid].
  final String? firstFailingFactId;

  const ChainVerificationResult._({
    required this.isValid,
    this.firstFailureIndex,
    this.firstFailingFactId,
  });

  /// Creates a successful result (all facts intact).
  const ChainVerificationResult.valid()
    : this._(isValid: true);

  /// Creates a failure result identifying the first tampered fact.
  const ChainVerificationResult.failure({
    required int index,
    required String factId,
  }) : this._(
         isValid: false,
         firstFailureIndex: index,
         firstFailingFactId: factId,
       );

  @override
  List<Object?> get props => [
    isValid,
    firstFailureIndex,
    firstFailingFactId,
  ];
}
