import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/dto/sla_ledger_entry_dto.dart';

void main() {
  group('SlaLedgerEntryDto', () {
    group('fromDomain', () {
      SlaLedgerEntry makeEntry({
        String organizationId = 'org-1',
        String type = 'PLAN_DECLARED',
        String operatorId = 'user-123',
        String? setId = 'set-1',
        String contractId = 'contract-1',
        int planVersion = 1,
        DateTime? occurredAtUtc,
        Map<String, dynamic> payload = const {},
      }) {
        return SlaLedgerEntry(
          organizationId: organizationId,
          type: type,
          operatorId: operatorId,
          setId: setId,
          contractId: contractId,
          planVersion: planVersion,
          occurredAtUtc: occurredAtUtc ?? DateTime.utc(2026, 4, 7, 21, 0, 0),
          payload: payload,
        );
      }

      test('valid entry produces correct JSON mapping', () {
        final entry = makeEntry();
        final dto = SlaLedgerEntryDto.fromDomain(entry);
        final json = dto.toJson();

        expect(json['organization_id'], 'org-1');
        expect(json['type'], 'PLAN_DECLARED');
        expect(json['operator_id'], 'user-123');
        expect(json['set_id'], 'set-1');
        expect(json['contract_id'], 'contract-1');
        expect(json['plan_version'], 1);
        expect(json['occurred_at_utc'], isA<String>());
      });

      test('null setId is preserved for plan-level events', () {
        final entry = makeEntry(setId: null);
        final dto = SlaLedgerEntryDto.fromDomain(entry);
        final json = dto.toJson();

        expect(json['set_id'], isNull);
      });

      test('payload is correctly mapped to JSON', () {
        final entry = makeEntry(
          payload: {'sanction_value_cents': 5000, 'reason': 'No-show'},
        );
        final dto = SlaLedgerEntryDto.fromDomain(entry);
        final json = dto.toJson();
        final mappedPayload = json['payload'] as Map<String, dynamic>;

        expect(mappedPayload['sanction_value_cents'], 5000);
        expect(mappedPayload['reason'], 'No-show');
      });

      test('empty organizationId throws IntegrityException', () {
        final entry = makeEntry(organizationId: '');
        expect(
          () => SlaLedgerEntryDto.fromDomain(entry),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('organizationId cannot be empty'),
            ),
          ),
        );
      });

      test('type exceeding 255 characters throws IntegrityException', () {
        final longType = 'A' * 256;
        final entry = makeEntry(type: longType);
        expect(
          () => SlaLedgerEntryDto.fromDomain(entry),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('type string limit exceeded'),
            ),
          ),
        );
      });

      test('type at exactly 255 characters is valid', () {
        final exactType = 'A' * 255;
        final entry = makeEntry(type: exactType);
        final dto = SlaLedgerEntryDto.fromDomain(entry);
        expect(dto.toJson()['type'], exactType);
      });

      test('operatorId exceeding 255 characters throws IntegrityException', () {
        final longOperatorId = 'A' * 256;
        final entry = makeEntry(operatorId: longOperatorId);
        expect(
          () => SlaLedgerEntryDto.fromDomain(entry),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('operatorId string limit exceeded'),
            ),
          ),
        );
      });

      test('negative planVersion throws IntegrityException', () {
        final entry = makeEntry(planVersion: -1);
        expect(
          () => SlaLedgerEntryDto.fromDomain(entry),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('planVersion cannot be negative'),
            ),
          ),
        );
      });

      test('zero planVersion is valid', () {
        final entry = makeEntry(planVersion: 0);
        final dto = SlaLedgerEntryDto.fromDomain(entry);
        expect(dto.toJson()['plan_version'], 0);
      });

      test('payload with double cents throws IntegrityException', () {
        final entry = makeEntry(payload: {'sanction_value_cents': 5000.50});
        expect(
          () => SlaLedgerEntryDto.fromDomain(entry),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('must be an int, found double'),
            ),
          ),
        );
      });

      test('payload with nested double cents throws IntegrityException', () {
        final entry = makeEntry(
          payload: {
            'financial': {'centavos': 123.45},
          },
        );
        expect(
          () => SlaLedgerEntryDto.fromDomain(entry),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('must be an int, found double'),
            ),
          ),
        );
      });

      test('payload with int cents passes validation', () {
        final entry = makeEntry(
          payload: {
            'sanction_value_cents': 5000,
            'financial': {'centavos': 12345},
          },
        );
        final dto = SlaLedgerEntryDto.fromDomain(entry);
        expect(dto.toJson()['payload']['sanction_value_cents'], 5000);
      });

      test('payload without cents fields with double values passes', () {
        final entry = makeEntry(
          payload: {'multiplier': 1.5, 'percentage': 0.75},
        );
        final dto = SlaLedgerEntryDto.fromDomain(entry);
        final payload = dto.toJson()['payload'] as Map<String, dynamic>;
        expect(payload['multiplier'], 1.5);
        expect(payload['percentage'], 0.75);
      });
    });

    group('fromJson', () {
      test('valid JSON is accepted', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'operator_id': 'user-123',
          'set_id': 'set-1',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
          'payload': {'key': 'value'},
        };

        final dto = SlaLedgerEntryDto.fromJson(json);
        expect(dto.toJson(), json);
      });

      test('missing organization_id throws IntegrityException', () {
        final json = {
          'type': 'PLAN_DECLARED',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Missing organization_id'),
            ),
          ),
        );
      });

      test('null organization_id throws IntegrityException', () {
        final json = {
          'organization_id': null,
          'type': 'PLAN_DECLARED',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Missing organization_id'),
            ),
          ),
        );
      });

      test('missing type throws IntegrityException', () {
        final json = {
          'organization_id': 'org-1',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Missing type'),
            ),
          ),
        );
      });

      test('null type throws IntegrityException', () {
        final json = {
          'organization_id': 'org-1',
          'type': null,
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Missing type'),
            ),
          ),
        );
      });

      test('missing occurred_at_utc throws IntegrityException', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'contract_id': 'contract-1',
          'plan_version': 1,
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Missing occurred_at_utc'),
            ),
          ),
        );
      });

      test('null occurred_at_utc throws IntegrityException', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': null,
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Missing occurred_at_utc'),
            ),
          ),
        );
      });

      test('null payload defaults to empty map in toDomain', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
          'payload': null,
        };

        final dto = SlaLedgerEntryDto.fromJson(json);
        final entry = dto.toDomain('db-id');
        expect(entry.payload, isEmpty);
      });

      test('missing payload key defaults to empty map via toDomain', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
        };

        final dto = SlaLedgerEntryDto.fromJson(json);
        final entry = dto.toDomain('test-id');
        expect(entry.payload, isEmpty);
      });

      test('payload with double cents throws IntegrityException', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
          'payload': {'sanction_value_cents': 5000.50},
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(json),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('must be an int, found double'),
            ),
          ),
        );
      });
    });

    group('toDomain', () {
      test('all fields are correctly mapped from DTO to domain', () {
        final json = {
          'organization_id': 'org-42',
          'type': 'EXECUTION_BOUND',
          'operator_id': 'driver-7',
          'set_id': 'trip-99',
          'contract_id': 'contract-10',
          'plan_version': 3,
          'occurred_at_utc': '2026-04-07T18:30:00.000Z',
          'payload': {'status': 'bound'},
        };

        final dto = SlaLedgerEntryDto.fromJson(json);
        final entry = dto.toDomain('uuid-abc-123');

        expect(entry.eventId, 'uuid-abc-123');
        expect(entry.organizationId, 'org-42');
        expect(entry.type, 'EXECUTION_BOUND');
        expect(entry.operatorId, 'driver-7');
        expect(entry.setId, 'trip-99');
        expect(entry.contractId, 'contract-10');
        expect(entry.planVersion, 3);
        expect(entry.occurredAtUtc, DateTime.utc(2026, 4, 7, 18, 30, 0));
        expect(entry.payload, {'status': 'bound'});
      });

      test('null operatorId defaults to SYSTEM', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'set_id': null,
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
          'operator_id': null,
          'payload': <String, dynamic>{},
        };

        final dto = SlaLedgerEntryDto.fromJson(json);
        final entry = dto.toDomain('db-id-1');

        expect(entry.operatorId, 'SYSTEM');
      });

      test('null setId is preserved for plan-level domain events', () {
        final json = {
          'organization_id': 'org-1',
          'type': 'PLAN_DECLARED',
          'set_id': null,
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-07T21:00:00.000Z',
          'payload': <String, dynamic>{},
        };

        final dto = SlaLedgerEntryDto.fromJson(json);
        final entry = dto.toDomain('db-id-2');

        expect(entry.setId, isNull);
      });

      test('round-trip: domain to DTO JSON to domain preserves values', () {
        final original = SlaLedgerEntry(
          organizationId: 'org-roundtrip',
          type: 'SANCTION_APPLIED',
          operatorId: 'system-audit',
          setId: 'set-rt-1',
          contractId: 'contract-rt',
          planVersion: 2,
          occurredAtUtc: DateTime.utc(2026, 6, 15, 10, 0, 0),
          payload: {'penalty_cents': 15000, 'reason': 'SLA breach'},
        );

        final dto = SlaLedgerEntryDto.fromDomain(original);
        final json = dto.toJson();

        final reconstituted = SlaLedgerEntryDto.fromJson(
          json,
        ).toDomain('generated-uuid');

        expect(reconstituted.organizationId, original.organizationId);
        expect(reconstituted.type, original.type);
        expect(reconstituted.operatorId, original.operatorId);
        expect(reconstituted.setId, original.setId);
        expect(reconstituted.contractId, original.contractId);
        expect(reconstituted.planVersion, original.planVersion);
        expect(
          reconstituted.occurredAtUtc.toIso8601String(),
          original.occurredAtUtc.toIso8601String(),
        );
        expect(reconstituted.payload['penalty_cents'], 15000);
        expect(reconstituted.payload['reason'], 'SLA breach');
      });
    });
  });
}
