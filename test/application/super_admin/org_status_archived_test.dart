import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  group('OrgStatus.archived (INV-10)', () {
    test('fromString ARCHIVED returns OrgStatus.archived', () {
      expect(OrgStatus.fromString('ARCHIVED'), OrgStatus.archived);
    });

    test('fromString archived (lowercase) returns OrgStatus.archived', () {
      expect(OrgStatus.fromString('archived'), OrgStatus.archived);
    });

    test('archived.isOperational is false', () {
      expect(OrgStatus.archived.isOperational, isFalse);
    });

    test('archived.isVisible is true', () {
      expect(OrgStatus.archived.isVisible, isTrue);
    });

    test('archived.dbValue is ARCHIVED', () {
      expect(OrgStatus.archived.dbValue, 'ARCHIVED');
    });

    test('archived.label is Arquivado', () {
      expect(OrgStatus.archived.label, 'Arquivado');
    });

    test('fromString DELETED still returns deleted (no regression)', () {
      expect(OrgStatus.fromString('DELETED'), OrgStatus.deleted);
    });

    test('deleted.isVisible is false (no regression)', () {
      expect(OrgStatus.deleted.isVisible, isFalse);
    });

    test('fromString invalid value throws IntegrityException', () {
      expect(
        () => OrgStatus.fromString('UNKNOWN_STATUS'),
        throwsA(isA<IntegrityException>()),
      );
    });
  });
}
