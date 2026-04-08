import 'package:test/test.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import '_contract_execution_helpers.dart';

void main() {
  // ── Group 4: ID Integrity & Collision Resistance ──────────────────────
  group('ID Integrity & Collision Resistance', () {
    test('identical inputs produce identical SET id (determinism)', () {
      final id1 = makeManualExecution(contractId: 'determinism-test').setId;
      final id2 = makeManualExecution(contractId: 'determinism-test').setId;

      expect(id1, equals(id2));
    });

    test('changing time by 1 second produces completely different hash', () {
      final id1 = makeManualExecution(
        scheduledStartTimeUtc: DateTime.utc(2026, 3, 15, 8, 0, 0),
      ).setId;
      final id2 = makeManualExecution(
        scheduledStartTimeUtc: DateTime.utc(2026, 3, 15, 8, 0, 1),
      ).setId;

      expect(id1, isNot(equals(id2)));
      // SHA-256 avalanche: even small changes produce vastly different hashes
      expect(id1.substring(0, 4), isNot(equals(id2.substring(0, 4))));
    });

    test('changing contractId + radius by 1 meter produces different hash', () {
      final id1 = makeManualExecution().setId;
      final id2 = makeManualExecution(
        contractId: 'contract-different',
        startRadiusMeters: 101,
      ).setId;

      expect(id1, isNot(equals(id2)));
    });

    test('changing coordinate by 0.000001 is preserved in entity', () {
      final exec1 = makeManualExecution(startLatitude: -23.550500);
      final exec2 = makeManualExecution(startLatitude: -23.550501);

      expect(exec1.startLatitude, isNot(equals(exec2.startLatitude)));
    });

    test('changing contractId produces completely different SET id', () {
      final id1 = makeManualExecution(contractId: 'contract-A').setId;
      final id2 = makeManualExecution(contractId: 'contract-B').setId;

      expect(id1, isNot(equals(id2)));
      // Confirm avalanche effect
      expect(id1.substring(0, 8), isNot(equals(id2.substring(0, 8))));
    });

    test('projected SET id format is SHA-256 hex (64 characters)', () {
      final execution = makeProjectedExecution();
      expect(execution.setId.length, 64);
      // Hex characters only
      expect(execution.setId, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('manual SET id format is SHA-256 hex (64 characters)', () {
      final execution = makeManualExecution();
      expect(execution.setId.length, 64);
      expect(execution.setId, matches(RegExp(r'^[a-f0-9]{64}$')));
    });
  });

  // ── Group 5: Financial Integrity (INV-2, INV-19) ──────────────────────
  group('Financial Integrity (INV-2 & INV-19)', () {
    test('contractualValue uses integer cents — no floating-point', () {
      final execution = makeManualExecution(
        contractualValue: const Money(15000),
      );

      expect(execution.contractualValue.cents, isA<int>());
      expect(execution.contractualValue.cents, equals(15000));
    });

    test('contractualValue.cents = 1 is accepted (minimum positive)', () {
      final execution = makeManualExecution(contractualValue: const Money(1));
      expect(execution.contractualValue.cents, 1);
    });

    test('contractualValue.cents = 0 is rejected', () {
      expect(
        () => makeManualExecution(contractualValue: const Money(0)),
        throwsA(isA<DomainException>()),
      );
    });

    test('contractualValue.cents = -1 is rejected', () {
      expect(
        () => makeManualExecution(contractualValue: const Money(-1)),
        throwsA(isA<DomainException>()),
      );
    });

    test('noShowPenaltyBps is stored as integer (basis points)', () {
      final execution = makeManualExecution(noShowPenaltyBps: 15000);
      expect(execution.noShowPenaltyBps, isA<int>());
      expect(execution.noShowPenaltyBps, 15000);
    });

    test('noShowPenaltyBps boundary: 10000 = 1.0x multiplier', () {
      final execution = makeManualExecution(noShowPenaltyBps: 10000);
      expect(execution.noShowPenaltyBps, 10000);
    });

    test('noShowPenaltyBps boundary: 9999 is rejected', () {
      expect(
        () => makeManualExecution(noShowPenaltyBps: 9999),
        throwsA(isA<DomainException>()),
      );
    });

    test('projected SET: delayPenaltyPerMinute.cents is integer', () {
      final execution = makeProjectedExecution(
        delayPenaltyPerMinute: const Money(125),
      );

      expect(execution.delayPenaltyPerMinute, isNotNull);
      expect(execution.delayPenaltyPerMinute!.cents, isA<int>());
      expect(execution.delayPenaltyPerMinute!.cents, 125);
    });

    test('projected SET: downgradePenaltyFlat.cents is integer', () {
      final execution = makeProjectedExecution(
        downgradePenaltyFlat: const Money(7500),
      );

      expect(execution.downgradePenaltyFlat, isNotNull);
      expect(execution.downgradePenaltyFlat!.cents, isA<int>());
      expect(execution.downgradePenaltyFlat!.cents, 7500);
    });

    test('reconstituted SET preserves integer cents for all Money fields', () {
      const delayPenalty = Money(300);
      const downgradePenalty = Money(15000);
      final reconstituted = ContractualServiceExecution.reconstitute(
        setId: 'recon-financial',
        scheduledStartTimeUtc: validStartTime,
        scheduledEndTimeUtc: validEndTime,
        startLatitude: validStartLat,
        startLongitude: validStartLng,
        startRadiusMeters: validRadius,
        endLatitude: validEndLat,
        endLongitude: validEndLng,
        endRadiusMeters: validRadius,
        contractualValue: const Money(25000),
        noShowPenaltyBps: 20000,
        delayPenaltyPerMinute: delayPenalty,
        downgradePenaltyFlat: downgradePenalty,
      );

      expect(reconstituted.contractualValue.cents, 25000);
      expect(reconstituted.contractualValue.cents, isA<int>());
      expect(reconstituted.delayPenaltyPerMinute, isNotNull);
      expect(reconstituted.delayPenaltyPerMinute!.cents, 300);
      expect(reconstituted.downgradePenaltyFlat!.cents, 15000);
      expect(reconstituted.downgradePenaltyFlat!.cents, isA<int>());
    });

    test('no floating-point rounding errors in Money values', () {
      // Verify that Money values are stored and retrieved exactly
      const exactCents = 99999;
      const exactMultiplier = 12345;

      final execution = makeManualExecution(
        contractualValue: const Money(exactCents),
        noShowPenaltyBps: exactMultiplier,
      );

      // Exact integer comparison — no epsilon, no tolerance
      expect(execution.contractualValue.cents, equals(exactCents));
      expect(execution.noShowPenaltyBps, equals(exactMultiplier));
    });
  });

  // ── Group 6: UTC Compliance (INV-9) ───────────────────────────────────
  group('UTC Compliance (INV-9)', () {
    test('scheduledStartTimeUtc is strictly UTC', () {
      final utcTime = DateTime.utc(2026, 3, 15, 8, 0, 0);
      final execution = makeManualExecution(scheduledStartTimeUtc: utcTime);

      expect(execution.scheduledStartTimeUtc.isUtc, isTrue);
      expect(execution.scheduledStartTimeUtc, equals(utcTime));
    });

    test('scheduledEndTimeUtc is strictly UTC', () {
      final utcTime = DateTime.utc(2026, 3, 15, 9, 0, 0);
      final execution = makeManualExecution(scheduledEndTimeUtc: utcTime);

      expect(execution.scheduledEndTimeUtc.isUtc, isTrue);
      expect(execution.scheduledEndTimeUtc, equals(utcTime));
    });

    test('projected SET: operationalDate preserves UTC designation', () {
      final utcDate = DateTime.utc(2026, 6, 1);
      final execution = makeProjectedExecution(operationalDate: utcDate);

      expect(execution.operationalDate, isNotNull);
      expect(execution.operationalDate!.isUtc, isTrue);
    });

    test('reconstituted SET preserves UTC timestamps', () {
      final startTime = DateTime.utc(2026, 3, 15, 8, 0);
      final endTime = DateTime.utc(2026, 3, 15, 9, 0);
      final reconstituted = ContractualServiceExecution.reconstitute(
        setId: 'utc-recon',
        scheduledStartTimeUtc: startTime,
        scheduledEndTimeUtc: endTime,
        startLatitude: validStartLat,
        startLongitude: validStartLng,
        startRadiusMeters: validRadius,
        endLatitude: validEndLat,
        endLongitude: validEndLng,
        endRadiusMeters: validRadius,
        contractualValue: validContractualValue,
        noShowPenaltyBps: validNoShowBps,
      );

      expect(reconstituted.scheduledStartTimeUtc.isUtc, isTrue);
      expect(reconstituted.scheduledEndTimeUtc.isUtc, isTrue);
    });
  });
}
