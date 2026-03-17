/// Port (interface) for atomic contract approval operations executed via
/// Supabase RPCs.
///
/// Implemented by the infrastructure layer.
/// Separating this port mirrors the [InvitationCommandService] pattern —
/// atomic multi-row operations belong in a dedicated service, not the
/// repository's upsert/save path.
abstract class ContractApprovalCommandService {
  /// Atomically:
  ///   1. Transitions [contractId] from 'draft' → 'awaitingContractorAcceptance'
  ///   2. Inserts a [ContractReviewToken] row with the given [token]
  ///
  /// [token] and [tokenId] are generated in Dart (INV-7: Deterministic Replay).
  /// Throws if the contract is not found in draft status, or if authorization fails.
  Future<void> submitForApproval({
    required String contractId,
    required String organizationId,
    required String tokenId,
    required String token,
    required DateTime expiresAtUtc,
  });

  /// Atomically:
  ///   1. Validates the [token] (not expired, not used)
  ///   2. Stamps [used_at_utc] on the token row (INV-1: no DELETE)
  ///   3. Transitions the linked contract → 'active'
  ///
  /// Returns a record with [contractId] and [organizationId] so the handler
  /// can construct the ledger event without a second round-trip.
  ///
  /// Throws if the token is invalid, expired, or already used.
  Future<({String contractId, String organizationId})> acceptByContractor({
    required String token,
  });
}
