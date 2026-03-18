import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../shared/money.dart';
import 'attestation_header.dart';
import 'audit_package_status.dart';
import 'billing_cycle_report.dart';
import 'domain_exception.dart';

/// Immutable, sealed evidence aggregate for a billing cycle.
///
/// An [AuditPackage] is the exportable artifact that a tenant (operator)
/// delivers to their contractor or presents in a legal dispute.
/// It aggregates [BillingCycleReport] data with cryptographic provenance.
///
/// **Lifecycle (D1-Canonical — two-row strategy, INV-1 compliant):**
///   1. [AuditPackage.createDraft] → [AuditPackageStatus.draft] — persisted as row A.
///   2. [seal] → returns a NEW [AuditPackage] with [AuditPackageStatus.sealed]
///      and a computed [packageHash] — persisted as row B. Row A is never updated.
///   3. [supersede] → returns a NEW [AuditPackage] with [AuditPackageStatus.superseded]
///      — the old sealed row remains immutable per INV-1.
///
/// **INV-16 (Export Sealing):** [packageHash] must be present before any export.
///   Call [seal] and persist the result before generating CSV/PDF.
/// **INV-17 (Attestation Mandate):** [attestationHeader] must be non-null on sealed packages.
/// **INV-2 (Financial Precision):** All financial aggregates in Money (cents).
/// **INV-3 (UTC Everywhere):** All timestamps are UTC.
/// **INV-4 (Domain Sovereignty):** Zero Flutter/Supabase dependencies.
/// **INV-6 (Multi-Tenant):** [organizationId] on every record.
class AuditPackage extends Equatable {
  static const String kSchemaVersion = '7.1.0';

  // ── Identity ──────────────────────────────────────────────────────────────
  final String id;
  final String organizationId;

  /// Null means "all contracts" in the organization scope.
  final String? contractId;

  /// Denormalized for portability — appears in exports without a DB join.
  final String contractorName;

  // ── Billing period ─────────────────────────────────────────────────────────
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;

  // ── Content provenance ─────────────────────────────────────────────────────
  /// SHA-256 deterministic hash of the [BillingCycleReport] canonical string.
  /// Links this package to the exact report computation.
  final String billingCycleReportId;

  /// The highest `lastLedgerEntryId` across all constituent daily snapshots.
  /// Any ledger entry with id ≤ [reportLedgerBoundary] is inside this package's scope.
  final int reportLedgerBoundary;

  /// Ordered UUIDs of the [ContractualFinancialDailySnapshot] records aggregated.
  /// Stored as UUID[] in the database (D2-Challenger: array over junction table).
  final List<String> snapshotIds;

  // ── Financial summary (denormalized for export portability) ────────────────
  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;
  final double complianceRate;

  // ── Cryptographic seal (INV-18) ────────────────────────────────────────────
  /// SHA-256 of the canonical package content JSON.
  /// Null until [seal] is called. A package without a hash MUST NOT be exported.
  final String? packageHash;
  final String hashAlgorithm;

  // ── Platform metadata ──────────────────────────────────────────────────────
  final String schemaVersion;
  final String engineVersionAtGeneration;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  final AuditPackageStatus status;

  /// Set when this package supersedes a previous one. Preserves lineage.
  final String? previousPackageId;

  /// Required when [previousPackageId] is set.
  final String? supersessionReason;

  final DateTime generatedAtUtc;
  final String generatedByUserId;

  // ── Legal attestation (INV-19) ─────────────────────────────────────────────
  final AttestationHeader attestationHeader;

  const AuditPackage._({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.contractorName,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.billingCycleReportId,
    required this.reportLedgerBoundary,
    required this.snapshotIds,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.complianceRate,
    required this.packageHash,
    required this.hashAlgorithm,
    required this.schemaVersion,
    required this.engineVersionAtGeneration,
    required this.status,
    required this.previousPackageId,
    required this.supersessionReason,
    required this.generatedAtUtc,
    required this.generatedByUserId,
    required this.attestationHeader,
  });

  /// Creates a new [AuditPackage] in [AuditPackageStatus.draft] state.
  ///
  /// [reportLedgerBoundary] must be `max(snapshot.lastLedgerEntryId)` across
  /// all constituent daily snapshots — this is the deterministic scope anchor.
  ///
  /// Does NOT compute [packageHash] — call [seal] to finalize.
  factory AuditPackage.createDraft({
    required String organizationId,
    required String? contractId,
    required String contractorName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required BillingCycleReport report,
    required int reportLedgerBoundary,
    required String engineVersionAtGeneration,
    required String generatedByUserId,
    required AttestationHeader attestationHeader,
  }) {
    _validateCommon(
      organizationId: organizationId,
      contractorName: contractorName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      reportLedgerBoundary: reportLedgerBoundary,
      engineVersionAtGeneration: engineVersionAtGeneration,
      generatedByUserId: generatedByUserId,
    );

    return AuditPackage._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      contractId: contractId,
      contractorName: contractorName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      billingCycleReportId: report.id,
      reportLedgerBoundary: reportLedgerBoundary,
      snapshotIds: List.unmodifiable(report.snapshotIds),
      totalContractedRevenue: report.totalContractedRevenue,
      protectedRevenue: report.protectedRevenue,
      revenueAtRisk: report.revenueAtRisk,
      lostRevenue: report.lostRevenue,
      totalObligations: report.totalObligations,
      executedCount: report.executedCount,
      noShowCount: report.noShowCount,
      evidenceGapCount: report.evidenceGapCount,
      complianceRate: report.complianceRate,
      packageHash: null,
      hashAlgorithm: 'SHA-256',
      schemaVersion: kSchemaVersion,
      engineVersionAtGeneration: engineVersionAtGeneration,
      status: AuditPackageStatus.draft,
      previousPackageId: null,
      supersessionReason: null,
      generatedAtUtc: report.generatedAtUtc,
      generatedByUserId: generatedByUserId,
      attestationHeader: attestationHeader,
    );
  }

  /// Returns a NEW [AuditPackage] with [AuditPackageStatus.sealed] and a
  /// computed [packageHash] (SHA-256 of canonical content JSON).
  ///
  /// The original draft instance is NOT modified (domain entity immutability).
  /// The caller is responsible for persisting BOTH instances as separate rows (D1-Canonical).
  ///
  /// Throws [DomainException] if already sealed or superseded.
  AuditPackage seal() {
    if (status != AuditPackageStatus.draft) {
      throw DomainException(
        'Cannot seal an AuditPackage with status "$status". '
        'Only draft packages can be sealed.',
      );
    }

    final hash = _computePackageHash();

    return AuditPackage._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      contractId: contractId,
      contractorName: contractorName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      billingCycleReportId: billingCycleReportId,
      reportLedgerBoundary: reportLedgerBoundary,
      snapshotIds: snapshotIds,
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      complianceRate: complianceRate,
      packageHash: hash,
      hashAlgorithm: 'SHA-256',
      schemaVersion: kSchemaVersion,
      engineVersionAtGeneration: engineVersionAtGeneration,
      status: AuditPackageStatus.sealed,
      previousPackageId: null,
      supersessionReason: null,
      generatedAtUtc: generatedAtUtc,
      generatedByUserId: generatedByUserId,
      attestationHeader: attestationHeader,
    );
  }

  /// Returns a NEW [AuditPackage] with [AuditPackageStatus.superseded], linking
  /// back to this package via [previousPackageId].
  ///
  /// Preserves the lineage chain for historical audit (INV-1: this row is never deleted).
  /// Throws [DomainException] if [reason] is empty, or if already superseded.
  AuditPackage supersede({required String reason}) {
    if (status == AuditPackageStatus.superseded) {
      throw const DomainException(
        'Package is already superseded. Create a new draft instead.',
      );
    }
    if (reason.trim().isEmpty) {
      throw const DomainException(
        'A supersession reason is required (INV-15 lineage traceability).',
      );
    }

    return AuditPackage._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      contractId: contractId,
      contractorName: contractorName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      billingCycleReportId: billingCycleReportId,
      reportLedgerBoundary: reportLedgerBoundary,
      snapshotIds: snapshotIds,
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      complianceRate: complianceRate,
      packageHash: packageHash,
      hashAlgorithm: hashAlgorithm,
      schemaVersion: schemaVersion,
      engineVersionAtGeneration: engineVersionAtGeneration,
      status: AuditPackageStatus.superseded,
      previousPackageId: id,
      supersessionReason: reason,
      generatedAtUtc: generatedAtUtc,
      generatedByUserId: generatedByUserId,
      attestationHeader: attestationHeader,
    );
  }

  /// Recomputes the [packageHash] from stored fields and compares to the stored value.
  /// Returns `false` if any content field was mutated after sealing.
  ///
  /// Only meaningful on [AuditPackageStatus.sealed] packages.
  bool verifyIntegrity() {
    if (packageHash == null) return false;
    return _computePackageHash() == packageHash;
  }

  /// Reconstitutes from persistence. Does NOT recompute hash.
  /// Use [verifyIntegrity] after reconstitution if tamper detection is needed.
  factory AuditPackage.reconstitute({
    required String id,
    required String organizationId,
    required String? contractId,
    required String contractorName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required String billingCycleReportId,
    required int reportLedgerBoundary,
    required List<String> snapshotIds,
    required Money totalContractedRevenue,
    required Money protectedRevenue,
    required Money revenueAtRisk,
    required Money lostRevenue,
    required int totalObligations,
    required int executedCount,
    required int noShowCount,
    required int evidenceGapCount,
    required double complianceRate,
    required String? packageHash,
    required String hashAlgorithm,
    required String schemaVersion,
    required String engineVersionAtGeneration,
    required AuditPackageStatus status,
    required String? previousPackageId,
    required String? supersessionReason,
    required DateTime generatedAtUtc,
    required String generatedByUserId,
    required AttestationHeader attestationHeader,
  }) {
    return AuditPackage._(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      contractorName: contractorName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      billingCycleReportId: billingCycleReportId,
      reportLedgerBoundary: reportLedgerBoundary,
      snapshotIds: List.unmodifiable(snapshotIds),
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      complianceRate: complianceRate,
      packageHash: packageHash,
      hashAlgorithm: hashAlgorithm,
      schemaVersion: schemaVersion,
      engineVersionAtGeneration: engineVersionAtGeneration,
      status: status,
      previousPackageId: previousPackageId,
      supersessionReason: supersessionReason,
      generatedAtUtc: generatedAtUtc,
      generatedByUserId: generatedByUserId,
      attestationHeader: attestationHeader,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Canonical content for hash computation.
  ///
  /// Field order is fixed — do not change without incrementing [kSchemaVersion].
  /// [generatedAtUtc] is intentionally excluded: it is a provenance timestamp,
  /// not content. Same financial data regenerated at a different time must
  /// produce the SAME hash.
  String _computePackageHash() {
    final sortedSnapshotIds = List<String>.from(snapshotIds)..sort();

    final canonical = {
      'schema_version': kSchemaVersion,
      'organization_id': organizationId,
      'contract_id': contractId ?? 'ALL',
      'billing_cycle_report_id': billingCycleReportId,
      'period_start_utc': periodStartUtc.toIso8601String(),
      'period_end_utc': periodEndUtc.toIso8601String(),
      'report_ledger_boundary': reportLedgerBoundary,
      'snapshot_ids': sortedSnapshotIds,
      'total_contracted_revenue_cents': totalContractedRevenue.cents,
      'protected_revenue_cents': protectedRevenue.cents,
      'revenue_at_risk_cents': revenueAtRisk.cents,
      'lost_revenue_cents': lostRevenue.cents,
      'total_obligations': totalObligations,
      'executed_count': executedCount,
      'no_show_count': noShowCount,
      'evidence_gap_count': evidenceGapCount,
      'compliance_rate': complianceRate,
      'engine_version_at_generation': engineVersionAtGeneration,
    };

    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  static void _validateCommon({
    required String organizationId,
    required String contractorName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required int reportLedgerBoundary,
    required String engineVersionAtGeneration,
    required String generatedByUserId,
  }) {
    if (organizationId.trim().isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (contractorName.trim().isEmpty) {
      throw const DomainException('contractorName must not be empty');
    }
    if (!periodStartUtc.isUtc) {
      throw const DomainException(
        'periodStartUtc must be UTC (INV-3).',
      );
    }
    if (!periodEndUtc.isUtc) {
      throw const DomainException(
        'periodEndUtc must be UTC (INV-3).',
      );
    }
    if (!periodEndUtc.isAfter(periodStartUtc)) {
      throw const DomainException(
        'periodEndUtc must be after periodStartUtc.',
      );
    }
    if (reportLedgerBoundary < 0) {
      throw const DomainException(
        'reportLedgerBoundary must be >= 0.',
      );
    }
    if (engineVersionAtGeneration.trim().isEmpty) {
      throw const DomainException('engineVersionAtGeneration must not be empty');
    }
    if (generatedByUserId.trim().isEmpty) {
      throw const DomainException('generatedByUserId must not be empty');
    }
  }

  @override
  List<Object?> get props => [id];
}
