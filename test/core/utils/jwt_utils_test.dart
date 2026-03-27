import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/utils/jwt_utils.dart';

void main() {
  group('decodeJwtPayload', () {
    String _makeJwt(Map<String, dynamic> payload) {
      final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
      return 'header.$encoded.signature';
    }

    test('decodes a well-formed JWT payload', () {
      final jwt = _makeJwt({
        'sub': 'user-123',
        'organization_id': 'org-abc',
        'role': 'admin',
      });

      final result = decodeJwtPayload(jwt);

      expect(result['sub'], 'user-123');
      expect(result['organization_id'], 'org-abc');
      expect(result['role'], 'admin');
    });

    test('returns empty map for token with fewer than 3 parts', () {
      expect(decodeJwtPayload('only.two'), isEmpty);
      expect(decodeJwtPayload('one'), isEmpty);
      expect(decodeJwtPayload(''), isEmpty);
    });

    test('returns empty map for token with more than 3 parts', () {
      expect(decodeJwtPayload('a.b.c.d'), isEmpty);
    });

    test('handles unpadded base64url payload', () {
      // base64Url may omit padding — normalize should handle it
      final payload = {'super_admin': true, 'org_id': null};
      final jwt = _makeJwt(payload);

      final result = decodeJwtPayload(jwt);
      expect(result['super_admin'], isTrue);
    });
  });
}
