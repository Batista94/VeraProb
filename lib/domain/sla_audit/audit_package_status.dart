/// Lifecycle states for an [AuditPackage].
///
/// State machine:
///   draft → sealed       (packageHash computed, export-ready)
///   sealed → superseded  (replaced by a new package; reason required)
///
/// Once [sealed], a package's content is cryptographically committed (INV-18).
/// Once [superseded], it is historical and should not be used for active billing.
enum AuditPackageStatus {
  /// Content may still change. No packageHash yet. Not safe for export.
  draft,

  /// Content is cryptographically sealed (SHA-256). Safe for legal export.
  sealed,

  /// Replaced by a newer package. Preserved for lineage (INV-1: no deletion).
  superseded,
}
