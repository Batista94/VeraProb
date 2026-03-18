import '../../../domain/shared/money.dart';
import '../../../domain/sla_audit/audit_package.dart';

/// Read model: contractor-facing view of a single sealed billing cycle.
///
/// Presents the [AuditPackage] data from the contractor's perspective:
/// every obligation with status, applied penalties, and access to the
/// sealed evidence package for dispute resolution.
///
/// **LGPD compliance:** exposes only aggregate financial data — no driver
/// or passenger personal data is surfaced in this projection (INV-6).
///
/// Built directly from a sealed [AuditPackage] to preserve the same
/// deterministic content that backs the exported PDF/CSV (INV-16, INV-17).
class ContractorPortalView {
  final String sealedPackageId;
  final String packageHash;

  final String contractorName;
  final String? contractId;

  final DateTime periodStartUtc;
  final DateTime periodEndUtc;

  // ── Obligation summary ─────────────────────────────────────────────────────
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;

  /// complianceRate ∈ [0.0, 100.0]
  final double complianceRate;

  // ── Financial summary ──────────────────────────────────────────────────────
  final Money totalContractedRevenue;
  final Money lostRevenue;

  const ContractorPortalView({
    required this.sealedPackageId,
    required this.packageHash,
    required this.contractorName,
    required this.contractId,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.complianceRate,
    required this.totalContractedRevenue,
    required this.lostRevenue,
  });

  /// Builds a [ContractorPortalView] from a sealed [AuditPackage].
  ///
  /// Throws [ArgumentError] if [package] is not sealed (packageHash must be set).
  factory ContractorPortalView.fromPackage(AuditPackage package) {
    final hash = package.packageHash;
    if (hash == null) {
      throw ArgumentError(
        'ContractorPortalView requires a sealed AuditPackage '
        '(packageHash must not be null — INV-16).',
      );
    }

    return ContractorPortalView(
      sealedPackageId: package.id,
      packageHash: hash,
      contractorName: package.contractorName,
      contractId: package.contractId,
      periodStartUtc: package.periodStartUtc,
      periodEndUtc: package.periodEndUtc,
      totalObligations: package.totalObligations,
      executedCount: package.executedCount,
      noShowCount: package.noShowCount,
      evidenceGapCount: package.evidenceGapCount,
      complianceRate: package.complianceRate,
      totalContractedRevenue: package.totalContractedRevenue,
      lostRevenue: package.lostRevenue,
    );
  }
}
