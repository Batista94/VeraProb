/// The lifecycle status of a contractual service execution obligation.
///
/// FSM transitions:
/// ```
/// planned → inTransit        (startTransit — Telegram button OR geofence entry)
/// planned → completed        (bindExecution — engine dwell confirmed)
/// planned → failed           (markFailed — sweep expired OR pg_cron 24h)
/// inTransit → completed      (bindExecution OR complete)
/// inTransit → completedWithGaps (completeWithGaps — /finish forced)
/// inTransit → failed         (markFailed — sweep expired)
/// failed → completed         (bindExecution — INV-12 late arrival)
/// completedWithGaps → completed (bindExecution — INV-12 late arrival)
/// planned/inTransit → inhibited (justification approved — INV-15)
/// ```
enum ExecutionStatus {
  /// Scheduled, awaiting window start or driver transit initiation.
  planned,

  /// Route active — driver started or geofence entry detected.
  /// Mandatory status for evidence acceptance.
  inTransit,

  /// Closed with 100% evidence checklist fulfilled.
  completed,

  /// Closed via forced finish with pending evidence gaps (forensic negligence).
  completedWithGaps,

  /// Time window expired without transition to inTransit.
  failed,

  /// Penalty suppressed because an approved justification was received (INV-15).
  inhibited,
}
