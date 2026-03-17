import 'contract_review_token.dart';

/// Port (interface) for persisting and querying [ContractReviewToken] entities.
///
/// Implemented by the infrastructure layer (Postgres).
/// Domain layer depends only on this abstraction (INV-4: Domain Sovereignty).
abstract class ContractReviewTokenRepository {
  /// Persists a new [ContractReviewToken].
  Future<void> save(ContractReviewToken token);

  /// Returns the active (non-expired, non-used) token matching [token],
  /// or `null` if not found.
  Future<ContractReviewToken?> findActiveByToken(String token);
}
