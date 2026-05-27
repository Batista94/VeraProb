// pr_scanner: ignore-regression

/// Port for logging the generated PDF Dossiers (INV-9 + Cadeia de Custódia Híbrida).
abstract class IPdfDossierLogRepository {
  /// Persists a log entry proving that a dossier with [documentHash] was generated
  /// for the [slaLedgerEntryId] within the [organizationId] by [operatorId].
  Future<void> logGeneration({
    required String organizationId,
    required String slaLedgerEntryId,
    required String documentHash,
    required String operatorId,
  });
}
