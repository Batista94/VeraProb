/// Domain-layer exception for data integrity violations. // pr_scanner: ignore
///
/// Thrown when mapping from infrastructure reveals corrupt, malformado,
/// or semantically invalid data (e.g., JSONB fields with wrong types, // pr_scanner: ignore
/// null values in required fields, out-of-range numbers).
///
/// **INV-18 (Domain Sovereignty):** Domain must reject garbage with
/// semantic errors, not generic `TypeError` or `FormatException`.
class IntegrityException implements Exception {
  final String message;
  final String? field;

  const IntegrityException(this.message, {this.field});

  @override
  String toString() =>
      'IntegrityException: $message${field != null ? ' (field: $field)' : ''}';

  /// Forensic Enum Shield: Safely converts a String to an Enum. (INV-18)
  ///
  /// Catches [ArgumentError] from `.byName()` and rethrows as [IntegrityException]
  /// to ensure domain sovereignty and named field attribution.
  static T shield<T extends Enum>(List<T> values, String name, String field) {
    try {
      return values.byName(name);
    } on ArgumentError {
      throw IntegrityException(
        'Invalid enum value "$name" for field "$field"',
        field: field,
      );
    }
  }
}
