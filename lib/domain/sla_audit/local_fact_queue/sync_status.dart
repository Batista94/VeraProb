/// Lifecycle state of a [PendingFact] in the local Edge Ledger queue.
///
/// Transitions:
///   pending → inFlight → acknowledged  (happy path)
///   inFlight → failed                   (network / integrity error)
///   failed  → inFlight                  (retry after back-off)
///   replayed → acknowledged             (gap-fill after handshake)
enum SyncStatus {
  /// Buffered locally; not yet submitted to Supabase.
  pending,

  /// Submission in progress; awaiting server acknowledgement.
  inFlight,

  /// Server confirmed receipt. Safe to purge after 48 h (INV-12).
  acknowledged,

  /// Submission failed. Will be retried with exponential back-off.
  failed,

  /// Received via gap-fill handshake replay; equivalent to acknowledged
  /// once the OCC has consumed the fact.
  replayed,
}
