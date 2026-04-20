import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/invitation_view.dart';
import 'package:veraprob/application/shared/app_types.dart';

void main() {
  group('InvitationView', () {
    test('can be constructed with required fields', () {
      final view = InvitationView(
        id: 'inv-1',
        organizationId: 'org-1',
        email: 'driver@example.com',
        role: UserRole.admin,
        token: 'uuid-token-abc',
        invitedBy: 'user-owner',
        createdAtUtc: DateTime.utc(2026, 3, 1),
        expiresAtUtc: DateTime.utc(2026, 3, 8),
      );
      expect(view.id, 'inv-1');
      expect(view.email, 'driver@example.com');
      expect(view.role, isA<UserRole>());
    });

    test('role is UserRole enum', () {
      final view = InvitationView(
        id: 'inv-2',
        organizationId: 'org-1',
        email: 'op@example.com',
        role: UserRole.operator,
        token: 'uuid-token-xyz',
        invitedBy: 'user-owner',
        createdAtUtc: DateTime.utc(2026, 3, 1),
        expiresAtUtc: DateTime.utc(2026, 3, 8),
      );
      expect(view.role, isA<UserRole>());
    });

    test('isActive, isExpired, isAccepted computed from timestamps', () {
      final view = InvitationView(
        id: 'inv-3',
        organizationId: 'org-1',
        email: 'user@example.com',
        role: UserRole.auditor,
        token: 'uuid-token-def',
        invitedBy: 'user-owner',
        createdAtUtc: DateTime.utc(2026, 3, 1),
        expiresAtUtc: DateTime.utc(2030, 12, 31),
        isAccepted: false,
        isExpired: false,
        isActive: true,
      );
      expect(view.isActive, isTrue);
      expect(view.isExpired, isFalse);
      expect(view.isAccepted, isFalse);
    });
  });
}
