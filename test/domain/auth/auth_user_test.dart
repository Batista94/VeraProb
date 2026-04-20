/// Unit tests for [AuthUser] domain value object.
///
/// Verifies immutability, null-email handling, and tenant isolation guarantees.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/enums/user_role.dart';

void main() {
  group('AuthUser', () {
    test('creates a valid user with all fields', () {
      const user = AuthUser(
        id: 'user-1',
        email: 'admin@veraprob.com',
        tenantId: 'org-123',
        role: UserRole.admin,
        isMfaEnabled: true,
      );

      expect(user.id, equals('user-1'));
      expect(user.email, equals('admin@veraprob.com'));
      expect(user.tenantId, equals('org-123'));
      expect(user.role, equals(UserRole.admin));
      expect(user.isMfaEnabled, isTrue);
    });

    test('creates a valid user with null email (phone/OAuth login)', () {
      const user = AuthUser(id: 'user-phone-1', tenantId: 'org-456');

      expect(user.id, equals('user-phone-1'));
      expect(user.email, isNull);
      expect(user.tenantId, equals('org-456'));
      expect(user.role, isNull);
      expect(user.isMfaEnabled, isFalse);
    });

    test('hasEmail returns true when email is present', () {
      const user = AuthUser(id: 'u1', email: 'a@b.com', tenantId: 'o1');
      expect(user.hasEmail, isTrue);
    });

    test('hasEmail returns false when email is null', () {
      const user = AuthUser(id: 'u1', tenantId: 'o1');
      expect(user.hasEmail, isFalse);
    });

    test('hasEmail returns false when email is empty string', () {
      const user = AuthUser(id: 'u1', email: '', tenantId: 'o1');
      expect(user.hasEmail, isFalse);
    });

    test('displayName returns email when available', () {
      const user = AuthUser(id: 'u1', email: 'a@b.com', tenantId: 'o1');
      expect(user.displayName, equals('a@b.com'));
    });

    test('displayName returns first 8 chars of id when email is null', () {
      const user = AuthUser(id: 'abcdefgh-1234', tenantId: 'o1');
      expect(user.displayName, equals('abcdefgh'));
    });

    test('equality: two users with same fields are equal', () {
      const u1 = AuthUser(
        id: 'u1',
        email: 'a@b.com',
        tenantId: 'o1',
        role: UserRole.operator,
        isMfaEnabled: true,
      );
      const u2 = AuthUser(
        id: 'u1',
        email: 'a@b.com',
        tenantId: 'o1',
        role: UserRole.operator,
        isMfaEnabled: true,
      );
      expect(u1, equals(u2));
    });

    test('equality: different tenantId means different user', () {
      const u1 = AuthUser(id: 'u1', tenantId: 'o1');
      const u2 = AuthUser(id: 'u1', tenantId: 'o2');
      expect(u1, isNot(equals(u2)));
    });

    test('hashCode is consistent for equal objects', () {
      const u1 = AuthUser(id: 'u1', email: 'a@b.com', tenantId: 'o1');
      const u2 = AuthUser(id: 'u1', email: 'a@b.com', tenantId: 'o1');
      expect(u1.hashCode, equals(u2.hashCode));
    });

    test('toString produces readable representation', () {
      const user = AuthUser(
        id: 'u1',
        email: 'a@b.com',
        tenantId: 'o1',
        role: UserRole.admin,
      );
      final str = user.toString();
      expect(str, contains('u1'));
      expect(str, contains('a@b.com'));
      expect(str, contains('o1'));
      expect(str, contains('admin'));
    });
  });
}
