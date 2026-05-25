// pr_scanner: ignore

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
  externalId, // Client-side ID for dedup
  notes; // Free-text observations

  /// DB-safe snake_case value.
  String get dbValue => name;
}
