import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_template_audit_entry.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

void main() {
  final clock = FakeDateTimeProvider(DateTime.utc(2026, 7, 28, 9, 0));

  SlaTemplateAuditEntry build({
    String organizationId = 'org-1',
    String action = 'CREATED',
  }) {
    return SlaTemplateAuditEntry.create(
      organizationId: organizationId,
      templateId: 'tmpl-1',
      actorSessionId: 'sess-1',
      action: action,
      templateSnapshot: const {'name': 'X'},
      clock: clock,
    );
  }

  group('SlaTemplateAuditEntry', () {
    test('stamps occurredAtUtc from the clock (INV-6)', () {
      expect(build().occurredAtUtc, clock.nowUtc());
    });

    test('accepts CREATED and UPDATED', () {
      expect(build(action: 'CREATED').action, 'CREATED');
      expect(build(action: 'UPDATED').action, 'UPDATED');
    });

    test('rejects unknown action with IntegrityException (INV-10)', () {
      expect(
        () => build(action: 'DELETED'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('rejects empty organizationId with IntegrityException (INV-1)', () {
      expect(
        () => build(organizationId: ''),
        throwsA(isA<IntegrityException>()),
      );
    });
  });
}
