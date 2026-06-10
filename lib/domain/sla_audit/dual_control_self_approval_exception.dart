/// Thrown when the SAME auditor attempts to confirm a high-value verdict they
/// themselves requested (dual-control / four-eyes, Phase 10.5 Item 2).
///
/// The confirming auditor's identity and the requester's identity both come
/// from the JWT `sub` claim, so a match means one human is trying to satisfy
/// BOTH reviewer roles — the exact internal-collusion vector dual-control
/// exists to block. The `confirm_peer_review` RPC raises this as a distinct
/// `P0001` + DETAIL `DualControlSelfApprovalException` (NOT a 42501 anti-oracle
/// rejection): the caller is a legitimate auditor of the right tenant, so the
/// UI must surface a CLEAR message — "a different auditor must confirm".
///
/// This is a governance guard, not a transport error (INV-10: typed domain
/// exception, never a generic `Exception`).
class DualControlSelfApprovalException implements Exception {
  /// The queue entry whose confirmation was refused.
  final String queueEntryId;

  /// Human-readable explanation surfaced to the operator.
  final String message;

  const DualControlSelfApprovalException({
    required this.queueEntryId,
    this.message =
        'The second auditor must differ from the auditor who requested '
        'this verdict.',
  });

  @override
  String toString() =>
      'DualControlSelfApprovalException: $message (entry: $queueEntryId)';
}
