import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/justification_token_view.dart';

void main() {
  group('JustificationTokenView', () {
    test('can be constructed with required fields', () {
      final view = JustificationTokenView(
        id: 'tkn-1',
        organizationId: 'org-1',
        contractId: 'ctr-1',
        setId: 'set-1',
        token: 'uuid-token-value',
        createdByUserId: 'user-1',
        expiresAtUtc: DateTime.utc(2026, 4, 5),
        createdAtUtc: DateTime.utc(2026, 4, 3),
      );
      expect(view.id, 'tkn-1');
      expect(view.token, 'uuid-token-value');
    });

    test('usedAtUtc and justificationId are optional', () {
      final view = JustificationTokenView(
        id: 'tkn-2',
        organizationId: 'org-1',
        contractId: 'ctr-1',
        setId: 'set-1',
        token: 'uuid-token-2',
        createdByUserId: 'user-1',
        expiresAtUtc: DateTime.utc(2026, 4, 5),
        createdAtUtc: DateTime.utc(2026, 4, 3),
      );
      expect(view.usedAtUtc, isNull);
      expect(view.justificationId, isNull);
    });

    test('isConsumed is true when usedAtUtc is set', () {
      final view = JustificationTokenView(
        id: 'tkn-3',
        organizationId: 'org-1',
        contractId: 'ctr-1',
        setId: 'set-1',
        token: 'uuid-token-3',
        createdByUserId: 'user-1',
        expiresAtUtc: DateTime.utc(2026, 4, 5),
        createdAtUtc: DateTime.utc(2026, 4, 3),
        usedAtUtc: DateTime.utc(2026, 4, 3, 12, 0),
        justificationId: 'jst-1',
      );
      expect(view.isConsumed, isTrue);
    });
  });
}
