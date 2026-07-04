import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Encodes [payload] as the middle segment of a fake 3-part JWT.
///
/// Header and signature are stubs — only the base64url payload matters for
/// `decodeJwtPayload`, which the permission providers use to read
/// `app_metadata` claims off the access token. No signing/verification.
String encodeFakeJwt(Map<String, dynamic> payload) {
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return 'header.$body.signature';
}

/// Builds a signed-in [Session] whose access token carries [appMetadata] under
/// the JWT `app_metadata` claim (mirrors `custom_access_token_hook` output).
///
/// The static `user.appMetadata` is left empty on purpose: the providers read
/// claims from the decoded token, not this field.
Session fakeSessionWithAppMeta(
  Map<String, dynamic> appMetadata, {
  String userId = 'user-1',
}) {
  return Session(
    accessToken: encodeFakeJwt(<String, dynamic>{
      'sub': userId,
      'app_metadata': appMetadata,
    }),
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const <String, dynamic>{},
      userMetadata: const <String, dynamic>{},
      aud: 'authenticated',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ),
  );
}
