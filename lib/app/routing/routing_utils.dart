/// UUID v4 validation at router boundary (QA F-3 / INV-26).
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Sandbox deep-link shape: `/admin/hub/contracts/:contractId/sandbox`.
final RegExp sandboxContractPathPattern = RegExp(
  r'^/admin/hub/contracts/([^/]+)/sandbox$',
);

/// Returns [raw] when it is a well-formed UUID; `null` otherwise.
///
/// Rejects empty strings, the literal `"null"`, and malformed values.
/// Prevents vehicleId injection through URL query parameters.
String? parseVehicleIdParam(String? raw) {
  if (raw == null || raw.isEmpty || raw == 'null') return null;
  return _uuidPattern.hasMatch(raw) ? raw : null;
}

/// Same boundary validation as [parseVehicleIdParam] for contract path segments.
String? parseContractIdParam(String? raw) => parseVehicleIdParam(raw);

/// Validated contract UUID from a sandbox URL, or `null` when not a sandbox path.
String? parseSandboxContractIdFromPath(String path) {
  if (path == '/admin/hub/contracts/sandbox') return null;
  final match = sandboxContractPathPattern.firstMatch(path);
  if (match == null) return null;
  return parseContractIdParam(match.group(1));
}
