import 'dart:convert';

/// Decodes the payload of a JWT access token without verifying the signature.
///
/// GoTrue's `custom_access_token_hook` injects claims (e.g. `super_admin`,
/// `org_id`, `role`) into the ACCESS TOKEN at sign-in time. These claims live
/// in the JWT payload and are NOT reflected in `session.user.appMetadata`,
/// which reads `auth.users.raw_app_meta_data` — a separate, static DB field.
///
/// Use this function wherever hook-injected claims are needed.
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return {};
  final normalized = base64Url.normalize(parts[1]);
  final decoded = utf8.decode(base64Url.decode(normalized));
  return jsonDecode(decoded) as Map<String, dynamic>;
}
