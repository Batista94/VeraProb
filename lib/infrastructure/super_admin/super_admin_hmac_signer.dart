import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:veraprob/infrastructure/shared/canonical_json.dart';

/// Computes x-timestamp and x-signature headers for super-admin-proxy requests.
/// Uses canonicalJsonEncode() from shared utility for Deno-parity key sorting (INV-15).
Map<String, String> buildSuperAdminHmacHeaders({
  required Map<String, dynamic> body,
  required String hmacKeyV1,
  DateTime? nowUtc,
}) {
  final ts =
      ((nowUtc ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000);
  final signingPayload = <String, dynamic>{...body, 'timestamp': ts};
  final canonical = canonicalJsonEncode(signingPayload);
  final hmac = Hmac(sha256, utf8.encode(hmacKeyV1));
  final signature = 'v1|${hmac.convert(utf8.encode(canonical))}';
  return {'x-timestamp': ts.toString(), 'x-signature': signature};
}
