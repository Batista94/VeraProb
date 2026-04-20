import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/admin/invitation.dart';
import 'package:veraprob/domain/enums/user_role.dart';

void main() {
  Invitation makeInvitation({
    DateTime? expiresAtUtc,
    DateTime? acceptedAtUtc,
    DateTime? revokedAtUtc,
  }) {
    return Invitation(
      id: 'inv-1',
      organizationId: 'org-1',
      email: 'test@example.com',
      role: UserRole.operator,
      token: 'token-abc',
      invitedBy: 'user-admin-1',
      createdAtUtc: DateTime.utc(2026, 1, 1),
      expiresAtUtc: expiresAtUtc ?? DateTime.utc(2099, 12, 31),
      acceptedAtUtc: acceptedAtUtc,
      revokedAtUtc: revokedAtUtc,
    );
  }

  group('Invitation', () {
    group('isExpiredAt', () {
      final now = DateTime.utc(2026, 4, 8, 12, 0, 0);

      test('returns false when expiry is in the future', () {
        final inv = makeInvitation(
          expiresAtUtc: now.add(const Duration(days: 1)),
        );
        expect(inv.isExpiredAt(now), isFalse);
      });

      test('returns true when expiry is in the past', () {
        final inv = makeInvitation(
          expiresAtUtc: now.subtract(const Duration(days: 1)),
        );
        expect(inv.isExpiredAt(now), isTrue);
      });
    });

    group('isAccepted', () {
      test('returns false when acceptedAtUtc is null', () {
        expect(makeInvitation().isAccepted, isFalse);
      });

      test('returns true when acceptedAtUtc is set', () {
        final inv = makeInvitation(acceptedAtUtc: DateTime.utc(2026, 3, 1));
        expect(inv.isAccepted, isTrue);
      });
    });

    group('isRevoked', () {
      test('returns false when revokedAtUtc is null', () {
        expect(makeInvitation().isRevoked, isFalse);
      });

      test('returns true when revokedAtUtc is set', () {
        final inv = makeInvitation(revokedAtUtc: DateTime.utc(2026, 3, 1));
        expect(inv.isRevoked, isTrue);
      });
    });

    group('isActiveAt', () {
      final now = DateTime.utc(2026, 4, 8, 12, 0, 0);

      test('returns true when not expired, not accepted, not revoked', () {
        expect(makeInvitation().isActiveAt(now), isTrue);
      });

      test('returns false when expired', () {
        final inv = makeInvitation(
          expiresAtUtc: now.subtract(const Duration(hours: 1)),
        );
        expect(inv.isActiveAt(now), isFalse);
      });

      test('returns false when accepted', () {
        final inv = makeInvitation(acceptedAtUtc: DateTime.utc(2026, 3, 1));
        expect(inv.isActiveAt(now), isFalse);
      });

      test('returns false when revoked', () {
        final inv = makeInvitation(revokedAtUtc: DateTime.utc(2026, 3, 1));
        expect(inv.isActiveAt(now), isFalse);
      });
    });

    test('equality is value-based via Equatable', () {
      final a = makeInvitation();
      final b = makeInvitation();
      expect(a, equals(b));
    });
  });
}
