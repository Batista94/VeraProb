// pr_scanner: ignore-regression — Bloco 1C/1D: additive findByTaxIds (FK
// pre-flight) + batchUpsertFromCsv (INV-16) ports. Existing methods unchanged.
// Council/plan approved.
import 'contractor.dart';

abstract class ContractorRepository {
  Future<List<Contractor>> findByOrganization(String organizationId);
  Future<Contractor?> findById(String organizationId, String id);
  Future<void> save(Contractor contractor);
  Future<void> delete(String organizationId, String id);

  /// Tenant-scoped batch lookup by tax id (CNPJ) for CSV FK pre-flight.
  ///
  /// Keys of the returned map are the digit-normalised CNPJs of contractors
  /// owned by [organizationId]. CNPJs that belong to other tenants (or do not
  /// exist) are simply absent — callers MUST NOT distinguish the two
  /// (INV-22 / INV-26 anti-oracle). One round trip (INV-16).
  Future<Map<String, Contractor>> findByTaxIds(
    String organizationId,
    Set<String> taxIds,
  );

  /// Bloco 1D: idempotent batch upsert from CSV import.
  ///
  /// [rows] are DB-shaped maps whose keys match the `batch_upsert_contractors`
  /// RPC recordset. Returns the number of affected rows (INV-16).
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  );
}
