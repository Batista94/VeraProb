import '../../domain/sla_audit/attestation_header.dart';
import '../../domain/sla_audit/audit_package.dart';
import '../../domain/sla_audit/audit_package_repository.dart';
import '../../domain/sla_audit/audit_package_status.dart';
import '../../domain/sla_audit/domain_exception.dart';
import 'reporting_service.dart';

/// Orchestrates the [AuditPackage] lifecycle: draft creation, sealing,
/// and supersession.
///
/// **D1-Canonical two-row strategy (INV-1 compliant):**
/// - [createDraftAndSeal] persists TWO rows: the draft (row A) then the sealed
///   package (row B). Row A is never updated.
/// - The sealed package is what callers use for exports.
///
/// **INV-18:** The package must be sealed before any export. This service
///   enforces that constraint by returning only sealed packages.
class AuditPackageService {
  final AuditPackageRepository _auditPackageRepo;
  final ReportingService _reportingService;

  AuditPackageService({
    required AuditPackageRepository auditPackageRepo,
    required ReportingService reportingService,
  }) : _auditPackageRepo = auditPackageRepo,
       _reportingService = reportingService;

  /// Generates a [BillingCycleReport], creates a draft, seals it, and persists
  /// both rows. Returns the sealed [AuditPackage].
  ///
  /// [reportLedgerBoundary] is computed here as max(snapshot.lastLedgerEntryId)
  /// across all constituent daily snapshots — this is the deterministic scope anchor.
  ///
  /// Throws [DomainException] if a sealed package for the same org/contract/period
  /// already exists (idempotency guard).
  Future<AuditPackage> createDraftAndSeal({
    required String organizationId,
    required String? contractId,
    required String contractorName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required String engineVersionAtGeneration,
    required String generatedByUserId,
    required AttestationHeader attestationHeader,
  }) async {
    // Idempotency: return existing sealed package if already exists
    final existing = await _auditPackageRepo.findActiveSealedPackage(
      organizationId: organizationId,
      contractId: contractId,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
    );
    if (existing != null) {
      return existing;
    }

    // 1. Generate BillingCycleReport from daily snapshots
    final report = await _reportingService.generateBillingCycleReport(
      organizationId: organizationId,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      contractId: contractId,
    );

    // 2. Compute reportLedgerBoundary = lastLedgerEntryId of the latest snapshot
    //    This is the deterministic scope anchor (Architect mandate).
    final reportLedgerBoundary = report.snapshots.isEmpty
        ? null
        : report.snapshots.last.lastLedgerEntryId;

    // 3. Create draft and persist as row A
    final draft = AuditPackage.createDraft(
      organizationId: organizationId,
      contractId: contractId,
      contractorName: contractorName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      report: report,
      reportLedgerBoundary: reportLedgerBoundary,
      engineVersionAtGeneration: engineVersionAtGeneration,
      generatedByUserId: generatedByUserId,
      attestationHeader: attestationHeader,
    );
    await _auditPackageRepo.save(draft);

    // 4. Seal (computes SHA-256 packageHash) and persist as row B
    //    Row A (draft) is never updated — INV-1 compliance.
    final sealed = draft.seal();
    await _auditPackageRepo.save(sealed);

    return sealed;
  }

  /// Supersedes an existing sealed package with a new one.
  ///
  /// Use this when late-arriving telemetry or data corrections require a
  /// re-generation of a previously sealed report. The original package is
  /// preserved with status [AuditPackageStatus.superseded] (INV-1: no deletion).
  Future<AuditPackage> supersede({
    required String currentPackageId,
    required String organizationId,
    required String contractorName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required String reason,
    required String engineVersionAtGeneration,
    required String generatedByUserId,
    required AttestationHeader attestationHeader,
  }) async {
    final current = await _auditPackageRepo.findById(
      id: currentPackageId,
      organizationId: organizationId,
    );
    if (current == null) {
      throw DomainException(
        'AuditPackage "$currentPackageId" not found for organization "$organizationId".',
      );
    }
    if (current.status != AuditPackageStatus.sealed) {
      throw DomainException(
        'Only sealed packages can be superseded. Current status: "${current.status}".',
      );
    }

    // Mark the current package as superseded (new row, INV-1 compliant)
    final superseded = current.supersede(reason: reason);
    await _auditPackageRepo.save(superseded);

    // Generate the replacement package
    return createDraftAndSeal(
      organizationId: organizationId,
      contractId: current.contractId,
      contractorName: contractorName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      engineVersionAtGeneration: engineVersionAtGeneration,
      generatedByUserId: generatedByUserId,
      attestationHeader: attestationHeader,
    );
  }

  /// Returns sealed packages for an organization, most recent first.
  Future<List<AuditPackage>> listSealedPackages({
    required String organizationId,
    int limit = 20,
  }) => _auditPackageRepo.findSealedByOrganization(
    organizationId: organizationId,
    limit: limit,
  );
}
