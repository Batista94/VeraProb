import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/domain/super_admin/system_audit_log_entry.dart';

void main() {
  group('SystemAuditLogView', () {
    group('fromDomain', () {
      test('propagates all fields including impersonatorId', () {
        const entry = SystemAuditLogEntry(
          severity: 'warning',
          eventType: 'IMPERSONATION_START',
          occurredAt: '2026-04-29T10:00:00Z',
          organizationId: 'org-123',
          source: 'rpc',
          actorType: 'IMPERSONATOR',
          reason: 'Investigacao de incidente',
          impersonatorId: 'super-admin-456',
          payload: {'target_org': 'org-123'},
        );

        final view = SystemAuditLogView.fromDomain(entry);

        expect(view.severity, 'warning');
        expect(view.eventType, 'IMPERSONATION_START');
        expect(view.occurredAt, '2026-04-29T10:00:00Z');
        expect(view.organizationId, 'org-123');
        expect(view.source, 'rpc');
        expect(view.actorType, 'IMPERSONATOR');
        expect(view.reason, 'Investigacao de incidente');
        expect(view.impersonatorId, 'super-admin-456');
        expect(view.payload, isNotNull);
      });

      test('null impersonatorId propagates as null', () {
        const entry = SystemAuditLogEntry(
          severity: 'info',
          eventType: 'QUOTA_CHANGE',
          occurredAt: '2026-04-29T10:00:00Z',
          actorType: 'HUMAN',
        );

        final view = SystemAuditLogView.fromDomain(entry);

        expect(view.impersonatorId, isNull);
        expect(view.actorType, 'HUMAN');
      });
    });

    group('fromJson', () {
      test('maps impersonator_id from JSON', () {
        final view = SystemAuditLogView.fromJson(const <String, Object?>{
          'severity': 'warning',
          'event_type': 'IMPERSONATION_START',
          'occurred_at': '2026-04-29T10:00:00Z',
          'organization_id': 'org-123',
          'source': 'rpc',
          'actor_type': 'IMPERSONATOR',
          'reason': 'Investigacao',
          'impersonator_id': 'super-admin-789',
        });

        expect(view.impersonatorId, 'super-admin-789');
        expect(view.actorType, 'IMPERSONATOR');
      });

      test('missing impersonator_id defaults to null', () {
        final view = SystemAuditLogView.fromJson(const <String, Object?>{
          'severity': 'info',
          'event_type': 'QUOTA_CHANGE',
          'occurred_at': '2026-04-29T10:00:00Z',
        });

        expect(view.impersonatorId, isNull);
      });
    });
  });

  group('SystemAuditLogEntry', () {
    group('fromJson', () {
      test('maps impersonator_id', () {
        final entry = SystemAuditLogEntry.fromJson(const {
          'severity': 'warning',
          'event_type': 'IMPERSONATION_START',
          'occurred_at': '2026-04-29T10:00:00Z',
          'impersonator_id': 'super-admin-456',
          'actor_type': 'IMPERSONATOR',
        });

        expect(entry.impersonatorId, 'super-admin-456');
      });

      test('missing impersonator_id defaults to null', () {
        final entry = SystemAuditLogEntry.fromJson(const {
          'severity': 'info',
          'event_type': 'QUOTA_CHANGE',
          'occurred_at': '2026-04-29T10:00:00Z',
        });

        expect(entry.impersonatorId, isNull);
      });
    });
  });
}
