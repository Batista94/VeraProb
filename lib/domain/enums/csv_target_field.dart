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
  operatorDocument, // CPF (identity — strict 11 digits)
  operatorLicense, // CNH registration number
  operatorLicenseCategory, // CNH category (A/B/C/D/E + combinations)
  operatorLicenseExpiry, // CNH expiry (TIMESTAMPTZ)
  operatorPhone, // Contact

  // ── Contractor fields ──
  contractorName, // Legal/company name (NOT NULL)
  contractorEmail, // Primary email (NOT NULL)
  contractorContactName, // Contact person (NOT NULL)

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
  address, // Physical address

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
  /// [externalId] is shared across all entities as the idempotency anchor.
  /// [notes] is scoped to `contract` only (the single entity with a `notes`
  /// column); exposing it elsewhere would silently drop the value at persist.
  static List<CsvTargetField> forEntity(String entity) => switch (entity) {
    'asset' => const [
      identifier,
      assetModel,
      capacity,
      assetStatus,
      externalId,
    ],
    'operator' => const [
      operatorName,
      operatorDocument,
      operatorLicense,
      operatorLicenseCategory,
      operatorLicenseExpiry,
      operatorPhone,
      externalId,
    ],
    'contractor' => const [
      contractorName,
      contractorDocument,
      contractorEmail,
      contractorContactName,
      externalId,
    ],
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
      latitude,
      longitude,
      radiusMeters,
      address,
      externalId,
    ],
    _ => values, // Safe fallback: show all for unknown entities
  };

  /// Fields mapping to NOT-NULL-without-default DB columns: they MUST be mapped
  /// for an import of [entity] to succeed. The preflight gate fails fast when
  /// any is unmapped (INV-10), preventing a 23502 null-value violation at the
  /// `batch_upsert_<entity>` RPC.
  ///
  /// Derived from the table DDL: contractors(name, primary_email, contact_name);
  /// vehicles(plate); drivers(full_name, license_number);
  /// contracts(name, contractor_name←document, valid_from_utc, valid_until_utc);
  /// operational_zones(name, latitude, longitude, radius_meters).
  static List<CsvTargetField> requiredForEntity(String entity) =>
      switch (entity) {
        'asset' => const [identifier],
        'operator' => const [operatorName, operatorLicense],
        'contractor' => const [
          contractorName,
          contractorDocument,
          contractorEmail,
          contractorContactName,
        ],
        'contract' => const [
          contractCode,
          contractorDocument,
          startDate,
          endDate,
        ],
        'zone' => const [zoneName, latitude, longitude, radiusMeters],
        _ => const [], // Unknown entity: no coverage constraint
      };
}
