import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/invitation_view.dart';

void main() {
  group('InvitationView', () {
    test('can be constructed with required fields', () {
      final view = InvitationView(
        id: 'inv-1',
        organizationId: 'org-1',
        email: 'driver@example.com',
        role: 'admin',
        token: 'uuid-token-abc',
        invitedBy: 'user-owner',
        createdAtUtc: DateTime.utc(2026, 3, 1),
        expiresAtUtc: DateTime.utc(2026, 3, 8),
      );
      expect(view.id, 'inv-1');
      expect(view.email, 'driver@example.com');
      expect(view.role, isA<String>());
    });

    test('role is String — no enum leak from domain', () {
      final view = InvitationView(
        id: 'inv-2',
        organizationId: 'org-1',
        email: 'op@example.com',
        role: 'operator',
        token: 'uuid-token-xyz',
        invitedBy: 'user-owner',
        createdAtUtc: DateTime.utc(2026, 3, 1),
        expiresAtUtc: DateTime.utc(2026, 3, 8),
      );
      expect(view.role, isA<String>());
    });

    test('isActive, isExpired, isAccepted computed from timestamps', () {
      final view = InvitationView(
        id: 'inv-3',
        organizationId: 'org-1',
        email: 'user@example.com',
        role: 'viewer',
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
