import 'dart:convert';

/// Produces deterministic key-sorted JSON identical to Deno's canonical_json.ts.
/// Used for HMAC signing parity across Dart client and Edge Functions (INV-15).
String canonicalJsonEncode(Map<String, dynamic> payload) =>
    jsonEncode(canonicalJsonSortKeys(payload));

/// Recursively sorts Map keys alphabetically and normalizes types.
dynamic canonicalJsonSortKeys(dynamic obj) {
  if (obj is Map) {
    final sorted = Map<String, dynamic>.fromEntries(
      (obj.keys.cast<String>().toList()..sort()).map(
        (k) => MapEntry(k, canonicalJsonSortKeys(obj[k])),
      ),
    );
    return sorted;
  }
  if (obj is List) return obj.map(canonicalJsonSortKeys).toList();
  if (obj is DateTime) {
    final iso = obj.toUtc().toIso8601String();
    return iso.endsWith('Z') ? iso : '${iso}Z';
  }
  return obj;
}
