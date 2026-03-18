import 'audit_package.dart';
import 'audit_package_status.dart';

/// Port (interface) for persisting and querying [AuditPackage] records.
///
/// Implementations must enforce INV-1: append-only. No UPDATE or DELETE.
/// All queries are scoped by [organizationId] (INV-6).
abstract class AuditPackageRepository {
  /// Persists a new [AuditPackage] row.
  ///
  /// Both draft and sealed rows are persisted via this method —
  /// the D1-Canonical two-row sealing strategy means [save] is called twice:
  /// once for the draft, once for the sealed result of [AuditPackage.seal].
  Future<void> save(AuditPackage package);

  /// Returns the [AuditPackage] with the given [id] scoped to [organizationId].
  /// Returns null if not found or if the record belongs to a different org.
  Future<AuditPackage?> findById({
    required String id,
    required String organizationId,
  });

  /// Returns all packages for a [contractId] whose period overlaps
  /// [[periodStart], [periodEnd]], ordered by [periodStartUtc] DESC.
  Future<List<AuditPackage>> findByContractAndPeriod({
    required String contractId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String organizationId,
  });

  /// Returns the most recent [limit] sealed packages for the organization,
  /// ordered by [generatedAtUtc] DESC.
  Future<List<AuditPackage>> findSealedByOrganization({
    required String organizationId,
    int limit = 20,
  });

  /// Returns the active sealed package for a contract in a given period, or null.
  /// "Active" means [AuditPackageStatus.sealed] (not superseded).
  Future<AuditPackage?> findActiveSealedPackage({
    required String organizationId,
    required String? contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
  });
}
