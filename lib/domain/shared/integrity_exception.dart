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
}
