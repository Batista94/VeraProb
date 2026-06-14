import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_acknowledgement.dart';

void main() {
  final ack = DateTime.utc(2026, 6, 13, 12);
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('SanctionAcknowledgement.validated', () {
    test('builds a valid PORTAL_TOKEN acknowledgement', () {
      final a = SanctionAcknowledgement.validated(
        id: 'a1',
        organizationId: 'o1',
        queueEntryId: 'q1',
        snapshotHashAcknowledged: hash,
        method: AcknowledgementMethod.portalToken,
        acknowledgedViaTokenId: 't1',
        acknowledgedByUserId: null,
        notes: null,
        acknowledgedAtUtc: ack,
      );
      expect(a.method, AcknowledgementMethod.portalToken);
      expect(a.snapshotHashAcknowledged, hash);
    });

    test('builds a valid INTERNAL_RECORD acknowledgement', () {
      final a = SanctionAcknowledgement.validated(
        id: 'a2',
        organizationId: 'o1',
        queueEntryId: 'q1',
        snapshotHashAcknowledged: null,
        method: AcknowledgementMethod.internalRecord,
        acknowledgedViaTokenId: null,
        acknowledgedByUserId: 'u1',
        notes: 'phone',
        acknowledgedAtUtc: ack,
      );
      expect(a.method, AcknowledgementMethod.internalRecord);
      expect(a.acknowledgedByUserId, 'u1');
    });

    test('PORTAL_TOKEN without hash throws IntegrityException', () {
      expect(
        () => SanctionAcknowledgement.validated(
          id: 'a',
          organizationId: 'o',
          queueEntryId: 'q',
          snapshotHashAcknowledged: null,
          method: AcknowledgementMethod.portalToken,
          acknowledgedViaTokenId: 't',
          acknowledgedByUserId: null,
          notes: null,
          acknowledgedAtUtc: ack,
        ),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('INTERNAL_RECORD without user throws IntegrityException', () {
      expect(
        () => SanctionAcknowledgement.validated(
          id: 'a',
          organizationId: 'o',
          queueEntryId: 'q',
          snapshotHashAcknowledged: null,
          method: AcknowledgementMethod.internalRecord,
          acknowledgedViaTokenId: null,
          acknowledgedByUserId: null,
          notes: null,
          acknowledgedAtUtc: ack,
        ),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('malformed snapshot hash throws IntegrityException', () {
      expect(
        () => SanctionAcknowledgement.validated(
          id: 'a',
          organizationId: 'o',
          queueEntryId: 'q',
          snapshotHashAcknowledged: 'NOTAHASH',
          method: AcknowledgementMethod.portalToken,
          acknowledgedViaTokenId: 't',
          acknowledgedByUserId: null,
          notes: null,
          acknowledgedAtUtc: ack,
        ),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('non-UTC timestamp throws IntegrityException', () {
      expect(
        () => SanctionAcknowledgement.validated(
          id: 'a',
          organizationId: 'o',
          queueEntryId: 'q',
          snapshotHashAcknowledged: hash,
          method: AcknowledgementMethod.portalToken,
          acknowledgedViaTokenId: 't',
          acknowledgedByUserId: null,
          notes: null,
          acknowledgedAtUtc: DateTime(2026, 6, 13),
        ),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  group('AcknowledgementMethodDb', () {
    test('round-trips PORTAL_TOKEN', () {
      expect(AcknowledgementMethod.portalToken.dbValue, 'PORTAL_TOKEN');
      expect(
        AcknowledgementMethodDb.fromDbValue('PORTAL_TOKEN'),
        AcknowledgementMethod.portalToken,
      );
    });

    test('round-trips INTERNAL_RECORD', () {
      expect(AcknowledgementMethod.internalRecord.dbValue, 'INTERNAL_RECORD');
      expect(
        AcknowledgementMethodDb.fromDbValue('INTERNAL_RECORD'),
        AcknowledgementMethod.internalRecord,
      );
    });

    test('unknown db value throws IntegrityException', () {
      expect(
        () => AcknowledgementMethodDb.fromDbValue('BOGUS'),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  test('equality covers structural fields (no hash-swap aliasing)', () {
    SanctionAcknowledgement make(String h) => SanctionAcknowledgement.validated(
      id: 'a1',
      organizationId: 'o1',
      queueEntryId: 'q1',
      snapshotHashAcknowledged: h,
      method: AcknowledgementMethod.portalToken,
      acknowledgedViaTokenId: 't1',
      acknowledgedByUserId: null,
      notes: null,
      acknowledgedAtUtc: ack,
    );
    expect(make(hash), equals(make(hash)));
    expect(make(hash), isNot(equals(make('b' * 64))));
  });
}
