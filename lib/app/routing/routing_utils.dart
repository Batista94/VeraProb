/// UUID v4 validation at router boundary (QA F-3 / INV-26).
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Returns [raw] when it is a well-formed UUID; `null` otherwise.
///
/// Rejects empty strings, the literal `"null"`, and malformed values.
/// Prevents vehicleId injection through URL query parameters.
String? parseVehicleIdParam(String? raw) {
  if (raw == null || raw.isEmpty || raw == 'null') return null;
  return _uuidPattern.hasMatch(raw) ? raw : null;
}
