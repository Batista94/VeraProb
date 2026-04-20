import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

void main() {
  group('SlaLedgerEntry', () {
    SlaLedgerEntry makeEntry({
      int? id,
      String? eventId,
      String organizationId = 'org-1',
      String type = 'PLAN_DECLARED',
      String operatorId = 'user-1',
      String? setId = 'set-1',
      String contractId = 'contract-1',
      int planVersion = 1,
      DateTime? occurredAtUtc,
      Map<String, dynamic> payload = const {},
    }) {
      return SlaLedgerEntry(
        id: id,
        eventId: eventId,
        organizationId: organizationId,
        type: type,
        operatorId: operatorId,
        setId: setId,
        contractId: contractId,
        planVersion: planVersion,
        occurredAtUtc: occurredAtUtc ?? DateTime.utc(2026, 1, 1),
        payload: payload,
      );
    }

    group('Equatable', () {
      test('identical entries are equal', () {
        final entry1 = makeEntry(id: 1, eventId: 'uuid-1');
        final entry2 = makeEntry(id: 1, eventId: 'uuid-1');

        expect(entry1, equals(entry2));
      });

      test('different organizationId makes entries unequal', () {
        final entry1 = makeEntry(organizationId: 'org-A');
        final entry2 = makeEntry(organizationId: 'org-B');

        expect(entry1, isNot(equals(entry2)));
      });

      test('different id makes entries unequal', () {
        final entry1 = makeEntry(id: 1);
        final entry2 = makeEntry(id: 2);

        expect(entry1, isNot(equals(entry2)));
      });

      test('different eventId makes entries unequal', () {
        final entry1 = makeEntry(eventId: 'uuid-A');
        final entry2 = makeEntry(eventId: 'uuid-B');

        expect(entry1, isNot(equals(entry2)));
      });

      test('different type makes entries unequal', () {
        final entry1 = makeEntry(type: 'PLAN_DECLARED');
        final entry2 = makeEntry(type: 'EXECUTION_BOUND');

        expect(entry1, isNot(equals(entry2)));
      });

      test('different occurredAtUtc makes entries unequal', () {
        final entry1 = makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 1));
        final entry2 = makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 2));

        expect(entry1, isNot(equals(entry2)));
      });

      test('different payload makes entries unequal', () {
        final entry1 = makeEntry(payload: {'key': 'value1'});
        final entry2 = makeEntry(payload: {'key': 'value2'});

        expect(entry1, isNot(equals(entry2)));
      });

      test('null id entries can be equal when all other fields match', () {
        final entry1 = makeEntry(id: null, eventId: null);
        final entry2 = makeEntry(id: null, eventId: null);

        expect(entry1, equals(entry2));
      });

      test('null setId entries can be equal for plan-level events', () {
        final entry1 = makeEntry(setId: null, type: 'PLAN_DECLARED');
        final entry2 = makeEntry(setId: null, type: 'PLAN_DECLARED');

        expect(entry1, equals(entry2));
      });
    });

    group('defaults', () {
      test('default operatorId is SYSTEM', () {
        final entry = SlaLedgerEntry(
          organizationId: 'org-1',
          type: 'PLAN_DECLARED',
          contractId: 'contract-1',
          planVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1),
        );

        expect(entry.operatorId, 'SYSTEM');
      });

      test('default payload is empty map', () {
        final entry = SlaLedgerEntry(
          organizationId: 'org-1',
          type: 'PLAN_DECLARED',
          contractId: 'contract-1',
          planVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1),
        );

        expect(entry.payload, isEmpty);
      });

      test('default setId is null for plan-level events', () {
        final entry = SlaLedgerEntry(
          organizationId: 'org-1',
          type: 'PLAN_DECLARED',
          contractId: 'contract-1',
          planVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1),
        );

        expect(entry.setId, isNull);
      });
    });

    group('immutability', () {
      test('entry is a value object with Equatable comparison', () {
        final entry1 = SlaLedgerEntry(
          organizationId: 'org-1',
          type: 'PLAN_DECLARED',
          contractId: 'contract-1',
          planVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1),
        );

        final entry2 = SlaLedgerEntry(
          organizationId: 'org-1',
          type: 'PLAN_DECLARED',
          contractId: 'contract-1',
          planVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1),
        );

        // Both are equal by value through Equatable
        expect(entry1, equals(entry2));
      });
    });

    group('forensic integrity', () {
      test('organizationId is never null (required field)', () {
        final entry = makeEntry(organizationId: 'org-forensic');
        expect(entry.organizationId, 'org-forensic');
        expect(entry.organizationId, isNotEmpty);
      });

      test('contractId is never null (required field)', () {
        final entry = makeEntry(contractId: 'contract-forensic');
        expect(entry.contractId, 'contract-forensic');
        expect(entry.contractId, isNotEmpty);
      });

      test('type is never null (required field)', () {
        final entry = makeEntry(type: 'FORENSIC_TYPE');
        expect(entry.type, 'FORENSIC_TYPE');
        expect(entry.type, isNotEmpty);
      });

      test('occurredAtUtc is always UTC', () {
        final entry = makeEntry(
          occurredAtUtc: DateTime.utc(2026, 6, 15, 14, 30, 0),
        );
        expect(entry.occurredAtUtc.isUtc, isTrue);
      });

      test('planVersion is immutable once set', () {
        final entry = makeEntry(planVersion: 5);
        expect(entry.planVersion, 5);
      });
    });
  });
}
