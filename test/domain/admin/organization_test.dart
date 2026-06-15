import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';

Organization _org({OrgStatus status = OrgStatus.active}) => Organization(
  id: 'org-1',
  name: 'Acme',
  timezone: 'America/Sao_Paulo',
  currencyCode: 'BRL',
  status: status,
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('Organization', () {
    test('defaults match the documented onboarding posture', () {
      final o = _org();
      expect(o.capabilities, OrgCapabilities.defaults);
      expect(o.dwellTimeSeconds, 300);
      expect(o.allowedDomains, isEmpty);
      expect(o.evidenceStorageEnabled, isFalse);
    });

    test('isActive only when status is active', () {
      expect(_org(status: OrgStatus.active).isActive, isTrue);
      expect(_org(status: OrgStatus.trial).isActive, isFalse);
      expect(_org(status: OrgStatus.archived).isActive, isFalse);
    });

    test('isOperational mirrors OrgStatus.isOperational (active + trial)', () {
      expect(_org(status: OrgStatus.active).isOperational, isTrue);
      expect(_org(status: OrgStatus.trial).isOperational, isTrue);
      expect(_org(status: OrgStatus.suspended).isOperational, isFalse);
      expect(_org(status: OrgStatus.deleted).isOperational, isFalse);
    });

    test(
      'copyWith changes only the named field; id + createdAt are pinned',
      () {
        final o = _org();
        final updated = o.copyWith(
          name: 'Beta',
          evidenceStorageEnabled: true,
          status: OrgStatus.suspended,
        );
        expect(updated.id, o.id);
        expect(updated.createdAt, o.createdAt);
        expect(updated.name, 'Beta');
        expect(updated.evidenceStorageEnabled, isTrue);
        expect(updated.status, OrgStatus.suspended);
        // Untouched fields preserved.
        expect(updated.timezone, o.timezone);
        expect(updated.currencyCode, o.currencyCode);
      },
    );

    test('value equality via Equatable props', () {
      expect(_org(), _org());
      expect(_org(), isNot(_org(status: OrgStatus.trial)));
    });
  });
}
