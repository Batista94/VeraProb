import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/justification_token_view.dart';

void main() {
  group('JustificationTokenView', () {
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

    test('isConsumed is false when usedAtUtc is null', () {
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
      expect(view.isConsumed, isFalse);
    });
  });
}
