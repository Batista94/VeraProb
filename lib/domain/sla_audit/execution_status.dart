/// The lifecycle status of a contractual service execution obligation.
///
/// Represents the judgment outcome for a single SET within a time window.
enum ExecutionStatus {
  /// Awaiting evaluation — no verdict yet.
  pending,

  /// Vehicle was bound to the obligation within the time window.
  executed,

  /// Time window expired with no matching vehicle detected.
  noShow,

  /// Insufficient telemetry evidence to determine execution.
  evidenceGap,

  /// Penalty suppressed because an approved justification was received (INV-15).
  inhibited,
}
