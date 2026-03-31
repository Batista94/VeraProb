import 'chain_verification_result.dart';
import 'pending_fact.dart';

/// Pure domain service that verifies the SHA-256 integrity of every
/// [PendingFact] in a sequence.
///
/// Each fact's [PendingFact.verifyIntegrity] recomputes the digest over its
/// stored [PendingFact.factPayloadJson] and compares it to the stored
/// [PendingFact.contentHash].  A mismatch means the SQLite row was mutated —
/// which violates INV-8.
///
/// **INV-18:** Pure Dart — zero Flutter / Supabase dependencies.
class ChainIntegrityVerifier {
  const ChainIntegrityVerifier();

  /// Iterates [facts] in order and returns on the first integrity failure.
  ///
  /// Returns [ChainVerificationResult.valid] when [facts] is empty or all
  /// facts pass their individual integrity check.
  ChainVerificationResult verify(List<PendingFact> facts) {
    for (var i = 0; i < facts.length; i++) {
      if (!facts[i].verifyIntegrity()) {
        return ChainVerificationResult.failure(
          index: i,
          factId: facts[i].factId,
        );
      }
    }
    return const ChainVerificationResult.valid();
  }
}
