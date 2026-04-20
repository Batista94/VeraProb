import 'package:veraprob/domain/sla_audit/audit_package.dart';
import 'package:veraprob/domain/sla_audit/audit_package_repository.dart';
import 'package:veraprob/domain/sla_audit/audit_package_status.dart';

/// In-memory implementation of [AuditPackageRepository] for testing.
///
/// Simulates the two-row (D1-Canonical) sealing strategy:
/// both draft and sealed rows are stored and retrievable.
class InMemoryAuditPackageRepository implements AuditPackageRepository {
  final List<AuditPackage> _packages = [];

  @override
  Future<void> save(AuditPackage package) async {
    _packages.add(package);
  }

  @override
  Future<AuditPackage?> findById({
    required String id,
    required String organizationId,
  }) async {
    try {
      return _packages.firstWhere(
        (p) => p.id == id && p.organizationId == organizationId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<AuditPackage>> findByContractAndPeriod({
    required String contractId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String organizationId,
  }) async {
    return _packages
        .where(
          (p) =>
              p.organizationId == organizationId &&
              p.contractId == contractId &&
              !p.periodStartUtc.isAfter(periodEnd) &&
              !p.periodEndUtc.isBefore(periodStart),
        )
        .toList()
      ..sort((a, b) => b.periodStartUtc.compareTo(a.periodStartUtc));
  }

  @override
  Future<List<AuditPackage>> findSealedByOrganization({
    required String organizationId,
    int limit = 20,
  }) async {
    return _packages
        .where(
          (p) =>
              p.organizationId == organizationId &&
              p.status == AuditPackageStatus.sealed,
        )
        .toList()
      ..sort((a, b) => b.generatedAtUtc.compareTo(a.generatedAtUtc))
      ..take(limit);
  }

  @override
  Future<AuditPackage?> findActiveSealedPackage({
    required String organizationId,
    required String? contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
  }) async {
    try {
      return _packages.firstWhere(
        (p) =>
            p.organizationId == organizationId &&
            p.contractId == contractId &&
            p.periodStartUtc.isAtSameMomentAs(periodStartUtc) &&
            p.periodEndUtc.isAtSameMomentAs(periodEndUtc) &&
            p.status == AuditPackageStatus.sealed,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Test helpers ───────────────────────────────────────────────────────────
  List<AuditPackage> get all => List.unmodifiable(_packages);
  int get count => _packages.length;
  void clear() => _packages.clear();
}
