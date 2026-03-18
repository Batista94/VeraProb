/// Integrity classification assigned to a [CanonicalFact] at normalization time.
///
/// The Engine consults this flag before issuing an SLA verdict:
/// - [ok]: trustworthy fact, eligible for evaluation.
/// - Any other value: fact is stored but flagged; Engine may skip or warn.
///
/// Flags are set by the Edge Function Adapter and are immutable after insertion.
/// They mirror the CHECK constraint in the `canonical_facts` DB table.
enum IngestionIntegrityFlag {
  /// Fact passed all validation checks. Safe for Engine evaluation.
  ok,

  /// `received_at_utc - gps_timestamp` exceeds the late-arrival threshold.
  /// Fact is stored and eligible for evaluation, but the Engine must account
  /// for potential timeline reconstruction impact (see 6.5.2).
  lateArrival,

  /// `gps_timestamp` is in the future relative to `received_at_utc`.
  /// Indicates device clock drift or spoofing. Fact is stored but excluded
  /// from Engine evaluation.
  futureTimestamp,

  /// Implied speed between consecutive pings exceeds the physical maximum
  /// (default: 200 km/h). GPS jitter artefact. Excluded from evaluation.
  kinematicAnomaly,

  /// Coordinates are (0.0, 0.0) — the "Null Island" GPS firmware default
  /// when satellite lock is lost. Fact is stored but excluded from evaluation.
  nullIsland,

  /// GPS accuracy radius exceeds the configured maximum (default: 100 m).
  /// Position is too uncertain to anchor a geofence evaluation.
  lowAccuracy,
}
