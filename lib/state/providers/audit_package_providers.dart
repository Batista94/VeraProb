import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/audit_package_service.dart';
import 'package:veraprob/application/sla_audit/csv_export_service.dart';
import 'package:veraprob/application/sla_audit/pdf_export_service.dart';
import 'package:veraprob/application/sla_audit/reporting_service.dart';
import 'package:veraprob/domain/sla_audit/audit_package.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_audit_package_repository.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'sla_financial_providers.dart';

// ── Repositories ────────────────────────────────────────────────────────────

final _auditPackageRepositoryProvider = Provider((ref) {
  // TODO(Phase 7.2): swap to PostgresAuditPackageRepository when Postgres mode
  return InMemoryAuditPackageRepository();
});

// ── Services ────────────────────────────────────────────────────────────────

final auditPackageServiceProvider = Provider<AuditPackageService>((ref) {
  final repo = ref.watch(_auditPackageRepositoryProvider);
  final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
  return AuditPackageService(
    auditPackageRepo: repo,
    reportingService: ReportingService(snapshotRepo: snapshotRepo),
  );
});

final csvExportServiceProvider = Provider<CsvExportService>(
  (ref) => CsvExportService(),
);

final pdfExportServiceProvider = Provider<PdfExportService>(
  (ref) => PdfExportService(),
);

// ── Read Models ──────────────────────────────────────────────────────────────

/// List of sealed audit packages for the current organization.
final sealedAuditPackagesProvider = FutureProvider<List<AuditPackage>>((
  ref,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return const [];

  final service = ref.watch(auditPackageServiceProvider);
  return service.listSealedPackages(organizationId: organizationId, limit: 20);
});

/// CSV export bytes for a given sealed package ID.
/// Usage: ref.read(csvExportProvider(packageId).future)
final csvExportProvider = FutureProvider.family<String, String>((
  ref,
  packageId,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) throw StateError('Not authenticated');

  final repo = ref.watch(_auditPackageRepositoryProvider);
  final package = await repo.findById(
    id: packageId,
    organizationId: organizationId,
  );
  if (package == null) throw StateError('Package $packageId not found');

  final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
  final reportingService = ReportingService(snapshotRepo: snapshotRepo);
  final report = await reportingService.generateBillingCycleReport(
    organizationId: organizationId,
    periodStartUtc: package.periodStartUtc,
    periodEndUtc: package.periodEndUtc,
    contractId: package.contractId,
  );

  final csvService = ref.watch(csvExportServiceProvider);
  return csvService.generateCsv(package: package, report: report);
});

/// PDF export bytes for a given sealed package ID.
final pdfExportProvider = FutureProvider.family<List<int>, String>((
  ref,
  packageId,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) throw StateError('Not authenticated');

  final repo = ref.watch(_auditPackageRepositoryProvider);
  final package = await repo.findById(
    id: packageId,
    organizationId: organizationId,
  );
  if (package == null) throw StateError('Package $packageId not found');

  final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
  final reportingService = ReportingService(snapshotRepo: snapshotRepo);
  final report = await reportingService.generateBillingCycleReport(
    organizationId: organizationId,
    periodStartUtc: package.periodStartUtc,
    periodEndUtc: package.periodEndUtc,
    contractId: package.contractId,
  );

  final pdfService = ref.watch(pdfExportServiceProvider);
  return pdfService.generatePdf(package: package, report: report);
});
