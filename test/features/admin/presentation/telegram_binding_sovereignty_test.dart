// Adversarial unit tests for TelegramBindingDialog sovereignty guard.
//
// INV-1: dialog must validate JWT org_id matches widget.organizationId
//        before calling the handler — widget prop is NOT the sovereignty anchor.
// INV-10: mismatch must throw SovereigntyViolationException (not silent skip).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/features/admin/presentation/widgets/telegram_binding_dialog.dart';

void main() {
  group('TelegramBindingDialog.assertOrgIdMatch (INV-1)', () {
    test('passes when widget org_id matches JWT org_id', () {
      expect(
        () => TelegramBindingDialog.assertOrgIdMatch(
          widgetOrgId: 'org-abc',
          jwtOrgId: 'org-abc',
        ),
        returnsNormally,
      );
    });

    test(
      'throws SovereigntyViolationException when org_ids differ (INV-1)',
      () {
        expect(
          () => TelegramBindingDialog.assertOrgIdMatch(
            widgetOrgId: 'org-abc',
            jwtOrgId: 'org-xyz-attacker',
          ),
          throwsA(
            isA<SovereigntyViolationException>()
                .having((e) => e.payloadOrgId, 'payloadOrgId', 'org-abc')
                .having((e) => e.jwtOrgId, 'jwtOrgId', 'org-xyz-attacker'),
          ),
        );
      },
    );

    test(
      'throws SovereigntyViolationException when jwtOrgId is null (no session)',
      () {
        expect(
          () => TelegramBindingDialog.assertOrgIdMatch(
            widgetOrgId: 'org-abc',
            jwtOrgId: null,
          ),
          throwsA(
            isA<SovereigntyViolationException>().having(
              (e) => e.jwtOrgId,
              'jwtOrgId',
              'none',
            ),
          ),
        );
      },
    );

    test(
      'throws SovereigntyViolationException when widgetOrgId is empty (INV-1 fail-fast)',
      () {
        expect(
          () => TelegramBindingDialog.assertOrgIdMatch(
            widgetOrgId: '',
            jwtOrgId: 'org-abc',
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    test(
      'toString() on exception does NOT leak org_ids (INV-26 log sanitization)',
      () {
        late SovereigntyViolationException caught;
        try {
          TelegramBindingDialog.assertOrgIdMatch(
            widgetOrgId: 'org-secret-tenant',
            jwtOrgId: 'org-attacker',
          );
        } on SovereigntyViolationException catch (e) {
          caught = e;
        }
        final str = caught.toString();
        expect(str, isNot(contains('org-secret-tenant')));
        expect(str, isNot(contains('org-attacker')));
      },
    );
  });
}
