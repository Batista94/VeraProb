// pr_scanner: ignore-regression — INV-14 transport-agnostic enum, Council-reviewed

/// Canonical target fields for CSV mapping (INV-14: transport-agnostic).
///
/// Maps to Asset/Operator/Contract/Zone properties — never to
/// transport-specific terms like "placa", "ônibus", or "motorista".
enum CsvTargetField {
  // ── Asset fields ──
  identifier, // Asset unique ID (e.g., plate, serial number)
  assetModel, // Model/make
  capacity, // Numeric capacity
  assetStatus, // active/inactive/maintenance

  // ── Operator fields ──
  operatorName, // Full name
  operatorDocument, // CPF/CNPJ
  operatorLicense, // License number
  operatorPhone, // Contact

  // ── Contract fields ──
  contractCode, // External contract reference
  contractorDocument, // CNPJ of the contractor
  startDate, // Contract start (TIMESTAMPTZ)
  endDate, // Contract end (TIMESTAMPTZ)

  // ── Zone fields ──
  zoneName, // Zone display name
  zoneCode, // Zone external code
  latitude, // Geofence center lat
  longitude, // Geofence center lng
  radiusMeters, // Geofence radius

  // ── Shared ──
  externalId, // Client-side ID for dedup (ERP integration anchor)
  notes; // Free-text observations

  /// DB-safe snake_case value.
  String get dbValue => name;

  /// Returns the whitelisted fields for a given entity type.
  ///
  /// Entity Isolation (Bloco 1A): prevents cross-contamination of unrelated
  /// fields in the UI dropdown (e.g., "Latitude" must never appear for
  /// "contractor" — INV-22 oracle prevention).
  ///
  /// [externalId] and [notes] are shared across all entities as the
  /// idempotency anchor and free-form annotation channel respectively.
  static List<CsvTargetField> forEntity(String entity) => switch (entity) {
    'asset' => const [
      identifier,
      assetModel,
      capacity,
      assetStatus,
      externalId,
      notes,
    ],
    'operator' => const [
      operatorName,
      operatorDocument,
      operatorLicense,
      operatorPhone,
      externalId,
      notes,
    ],
    'contractor' => const [contractorDocument, externalId, notes],
    'contract' => const [
      contractCode,
      contractorDocument,
      startDate,
      endDate,
      externalId,
      notes,
    ],
    'zone' => const [
      zoneName,
      zoneCode,
      latitude,
      longitude,
      radiusMeters,
      externalId,
      notes,
    ],
    _ => values, // Safe fallback: show all for unknown entities
  };
}
