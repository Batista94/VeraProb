import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/dto/sla_ledger_entry_dto.dart';

void main() {
  group('SlaLedgerEntryDto Mapping', () {
    final now = DateTime.now().toUtc();

    test('1. Forces negative values to throw FormatException during mapping', () {
      final entry = SlaLedgerEntry(
        organizationId: 'org-123',
        type: 'TEST_EVENT',
        operatorId: 'operator-xyz',
        contractId: 'contract-x',
        planVersion: -1, // Invalid planVersion
        occurredAtUtc: now,
        payload: const {'test': true},
      );

      expect(
        () => SlaLedgerEntryDto.fromDomain(entry),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('negative'),
          ),
        ),
        reason:
            'Garanta que um mapeamento falho lance uma exceção antes de tentar persistir',
      );
    });

    test('1. Forces giant strings to throw FormatException during mapping', () {
      final String giantString = 'A' * 600;

      final entry = SlaLedgerEntry(
        organizationId: 'org-123',
        type: giantString, // Invalid large string
        operatorId: 'operator-xyz',
        contractId: 'contract-x',
        planVersion: 1,
        occurredAtUtc: now,
        payload: const {'test': true},
      );

      expect(
        () => SlaLedgerEntryDto.fromDomain(entry),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('limit exceeded'),
          ),
        ),
        reason: 'Strings gigantes devem falhar o mapeamento',
      );
    });

    test('2. Ensures int (centavos) is NEVER converted to double', () {
      // payload with double for cents
      final entry = SlaLedgerEntry(
        organizationId: 'org-123',
        type: 'FINANCIAL_EVENT',
        operatorId: 'operator-xyz',
        contractId: 'contract-x',
        planVersion: 1,
        occurredAtUtc: now,
        payload: const {
          'fine_cents': 1500.0,
        }, // Malformed: should NEVER be double
      );

      expect(
        () => SlaLedgerEntryDto.fromDomain(entry),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('must be an int, found double'),
          ),
        ),
        reason:
            'Cents metrics mapped as double should fail parsing immediately',
      );

      final validEntry = SlaLedgerEntry(
        organizationId: 'org-123',
        type: 'FINANCIAL_EVENT',
        operatorId: 'operator-xyz',
        contractId: 'contract-x',
        planVersion: 1,
        occurredAtUtc: now,
        payload: const {'fine_cents': 1500, 'other_centavos': 0},
      );

      // Must NOT throw
      final dto = SlaLedgerEntryDto.fromDomain(validEntry);

      expect(dto.toJson()['payload']['fine_cents'], 1500);
      expect(dto.toJson()['payload']['fine_cents'], isA<int>());
    });

    test(
      '3. Mapping from Json fails gracefully before trying to persist or use',
      () {
        final invalidJsonMap = <String, dynamic>{
          'organization_id': 'org-123',
          'type': 'TEST_EVENT',
          'occurred_at_utc': now.toIso8601String(),
          'payload': {
            'fine_cents': 1500.5, // DB mapped as float/double
          },
        };

        expect(
          () => SlaLedgerEntryDto.fromJson(invalidJsonMap),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('must be an int, found double'),
            ),
          ),
          reason:
              'Json extraction with malformed financial fields must throw FormatException',
        );
      },
    );

    test('Valid mapping passes correctly', () {
      final validEntry = SlaLedgerEntry(
        eventId: 'event-uuid',
        organizationId: 'org-123',
        type: 'FINANCIAL_EVENT',
        operatorId: 'operator-xyz',
        setId: 'set-id',
        contractId: 'contract-x',
        planVersion: 0,
        occurredAtUtc: now,
        payload: const {'fine_cents': 1500, 'null_val': null},
      );

      final dto = SlaLedgerEntryDto.fromDomain(validEntry);
      final generatedJson = dto.toJson();

      expect(generatedJson['organization_id'], 'org-123');
      expect(generatedJson['payload']['fine_cents'], 1500);

      // And it can be mapped back
      final reversedDto = SlaLedgerEntryDto.fromJson({
        'id': 'event-uuid',
        ...generatedJson,
      });

      final finalDomain = reversedDto.toDomain('event-uuid');
      expect(finalDomain.eventId, 'event-uuid');
      expect(finalDomain.type, 'FINANCIAL_EVENT');
      expect(finalDomain.payload['fine_cents'], 1500);
    });
  });
}
