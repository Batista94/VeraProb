import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/application/audit_event_category.dart';

void main() {
  group('AuditEventCategory', () {
    group('fromEventType — infrastructure', () {
      test('POOL_LIMIT maps to infrastructure', () {
        expect(
          AuditEventCategory.fromEventType('POOL_LIMIT_EXCEEDED'),
          AuditEventCategory.infrastructure,
        );
      });

      test('STORAGE_QUOTA maps to infrastructure', () {
        expect(
          AuditEventCategory.fromEventType('STORAGE_QUOTA_REACHED'),
          AuditEventCategory.infrastructure,
        );
      });

      test('SCHEMA maps to infrastructure', () {
        expect(
          AuditEventCategory.fromEventType('SCHEMA_MIGRATION_APPLIED'),
          AuditEventCategory.infrastructure,
        );
      });

      test('REPLICATION maps to infrastructure', () {
        expect(
          AuditEventCategory.fromEventType('REPLICATION_LAG_DETECTED'),
          AuditEventCategory.infrastructure,
        );
      });

      test('case insensitive matching', () {
        expect(
          AuditEventCategory.fromEventType('pool_limit_warning'),
          AuditEventCategory.infrastructure,
        );
        expect(
          AuditEventCategory.fromEventType('storage_quota_alert'),
          AuditEventCategory.infrastructure,
        );
      });
    });

    group('fromEventType — governance', () {
      test('PLAN_CHANGED maps to governance', () {
        expect(
          AuditEventCategory.fromEventType('PLAN_CHANGED'),
          AuditEventCategory.governance,
        );
      });

      test('QUOTA maps to governance', () {
        expect(
          AuditEventCategory.fromEventType('QUOTA_UPDATED'),
          AuditEventCategory.governance,
        );
      });

      test('ORG_CREATED maps to governance', () {
        expect(
          AuditEventCategory.fromEventType('ORG_CREATED'),
          AuditEventCategory.governance,
        );
      });

      test('ORG_ARCHIVED maps to governance', () {
        expect(
          AuditEventCategory.fromEventType('ORG_ARCHIVED'),
          AuditEventCategory.governance,
        );
      });

      test('ORG_UNARCHIVED maps to governance', () {
        expect(
          AuditEventCategory.fromEventType('ORG_UNARCHIVED'),
          AuditEventCategory.governance,
        );
      });
    });

    group('fromEventType — security', () {
      test('SECRET maps to security', () {
        expect(
          AuditEventCategory.fromEventType('SECRET_ROTATED'),
          AuditEventCategory.security,
        );
      });

      test('IMPERSONATION maps to security', () {
        expect(
          AuditEventCategory.fromEventType('IMPERSONATION_STARTED'),
          AuditEventCategory.security,
        );
      });

      test('MFA maps to security', () {
        expect(
          AuditEventCategory.fromEventType('MFA_ENROLLED'),
          AuditEventCategory.security,
        );
      });

      test('AUTH maps to security', () {
        expect(
          AuditEventCategory.fromEventType('AUTH_FAILED'),
          AuditEventCategory.security,
        );
      });
    });

    group('fromEventType — operational (fallback)', () {
      test('unknown event types fall back to operational', () {
        expect(
          AuditEventCategory.fromEventType('USER_LOGIN'),
          AuditEventCategory.operational,
        );
        expect(
          AuditEventCategory.fromEventType('REPORT_GENERATED'),
          AuditEventCategory.operational,
        );
        expect(
          AuditEventCategory.fromEventType('SOME_RANDOM_EVENT'),
          AuditEventCategory.operational,
        );
      });

      test('empty string falls back to operational', () {
        expect(
          AuditEventCategory.fromEventType(''),
          AuditEventCategory.operational,
        );
      });
    });

    group('fromEventType — priority: STORAGE_QUOTA before QUOTA', () {
      test('STORAGE_QUOTA maps to infrastructure, not governance', () {
        // STORAGE_QUOTA contains "QUOTA" but should match infrastructure
        // because STORAGE_QUOTA is checked first in the infrastructure block.
        expect(
          AuditEventCategory.fromEventType('STORAGE_QUOTA_EXCEEDED'),
          AuditEventCategory.infrastructure,
        );
      });
    });

    group('label', () {
      test('returns correct Portuguese labels', () {
        expect(AuditEventCategory.infrastructure.label, 'Infraestrutura');
        expect(AuditEventCategory.governance.label, 'Governança');
        expect(AuditEventCategory.security.label, 'Segurança');
        expect(AuditEventCategory.operational.label, 'Operacional');
      });
    });
  });
}
