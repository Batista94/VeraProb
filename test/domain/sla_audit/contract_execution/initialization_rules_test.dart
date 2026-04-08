import 'package:test/test.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import '_contract_execution_helpers.dart';

void main() {
  // ── Group 1: Manual SET Creation ─────────────────────────────────────
  group('Manual SET Creation (create)', () {
    test('creates successfully with minimum valid parameters', () {
      final execution = makeManualExecution();

      expect(execution.setId, isNotEmpty);
      expect(execution.setId.length, 64); // SHA-256 hex length
      expect(execution.scheduledStartTimeUtc, validStartTime);
      expect(execution.scheduledEndTimeUtc, validEndTime);
      expect(execution.startLatitude, validStartLat);
      expect(execution.startLongitude, validStartLng);
      expect(execution.startRadiusMeters, validRadius);
      expect(execution.endLatitude, validEndLat);
      expect(execution.endLongitude, validEndLng);
      expect(execution.endRadiusMeters, validRadius);
      expect(execution.plannedVehicleId, isNull);
      expect(execution.contractualValue.cents, 15000);
      expect(execution.noShowPenaltyBps, validNoShowBps);
      expect(execution.isProjected, isFalse);
    });

    test('creates successfully with optional plannedVehicleId', () {
      final execution = makeManualExecution(plannedVehicleId: 'vehicle-42');

      expect(execution.plannedVehicleId, 'vehicle-42');
      expect(execution.originZoneId, isNull);
      expect(execution.destinationZoneId, isNull);
      expect(execution.operationalDate, isNull);
      expect(execution.shiftPatternIndex, isNull);
      expect(execution.delayToleranceMinutes, isNull);
      expect(execution.delayPenaltyPerMinute, isNull);
      expect(execution.downgradePenaltyFlat, isNull);
    });

    test('SET id is deterministic for identical inputs', () {
      final id1 = makeManualExecution().setId;
      final id2 = makeManualExecution().setId;

      expect(id1, equals(id2));
    });

    test('SET id is unique for different contractId', () {
      final id1 = makeManualExecution(contractId: 'contract-A').setId;
      final id2 = makeManualExecution(contractId: 'contract-B').setId;

      expect(id1, isNot(equals(id2)));
    });

    test('SET id is unique for different startTime', () {
      final id1 = makeManualExecution(
        scheduledStartTimeUtc: DateTime.utc(2026, 3, 15, 8, 0),
      ).setId;
      final id2 = makeManualExecution(
        scheduledStartTimeUtc: DateTime.utc(2026, 3, 15, 8, 1),
      ).setId;

      expect(id1, isNot(equals(id2)));
    });

    test(
      'throws DomainException when scheduledEndTimeUtc == scheduledStartTimeUtc',
      () {
        expect(
          () => makeManualExecution(scheduledEndTimeUtc: validStartTime),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('scheduledEndTimeUtc must be after'),
            ),
          ),
        );
      },
    );

    test(
      'throws DomainException when scheduledEndTimeUtc < scheduledStartTimeUtc',
      () {
        expect(
          () => makeManualExecution(
            scheduledEndTimeUtc: DateTime.utc(2026, 3, 15, 7, 0),
          ),
          throwsA(isA<DomainException>()),
        );
      },
    );

    // Latitude boundary validation
    test('throws DomainException when startLatitude < -90', () {
      expect(
        () => makeManualExecution(startLatitude: -90.01),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('startLatitude must be between -90 and 90'),
          ),
        ),
      );
    });

    test('throws DomainException when startLatitude > 90', () {
      expect(
        () => makeManualExecution(startLatitude: 90.01),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('startLatitude must be between -90 and 90'),
          ),
        ),
      );
    });

    test('accepts startLatitude = -90.0 (lower boundary)', () {
      final execution = makeManualExecution(startLatitude: -90.0);
      expect(execution.startLatitude, -90.0);
    });

    test('accepts startLatitude = 90.0 (upper boundary)', () {
      final execution = makeManualExecution(startLatitude: 90.0);
      expect(execution.startLatitude, 90.0);
    });

    test('throws DomainException when endLatitude < -90', () {
      expect(
        () => makeManualExecution(endLatitude: -90.01),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when endLatitude > 90', () {
      expect(
        () => makeManualExecution(endLatitude: 90.01),
        throwsA(isA<DomainException>()),
      );
    });

    // ── Longitude boundary validation ───────────────────────
    test('throws DomainException when startLongitude < -180', () {
      expect(
        () => makeManualExecution(startLongitude: -180.01),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when startLongitude > 180', () {
      expect(
        () => makeManualExecution(startLongitude: 180.01),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts startLongitude = -180.0 (lower boundary)', () {
      final execution = makeManualExecution(startLongitude: -180.0);
      expect(execution.startLongitude, -180.0);
    });

    test('accepts startLongitude = 180.0 (upper boundary)', () {
      final execution = makeManualExecution(startLongitude: 180.0);
      expect(execution.startLongitude, 180.0);
    });

    test('throws DomainException when endLongitude < -180', () {
      expect(
        () => makeManualExecution(endLongitude: -180.01),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when endLongitude > 180', () {
      expect(
        () => makeManualExecution(endLongitude: 180.01),
        throwsA(isA<DomainException>()),
      );
    });

    // ── Radius boundary validation ──────────────────────────
    test('throws DomainException when startRadiusMeters = 0', () {
      expect(
        () => makeManualExecution(startRadiusMeters: 0),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('startRadiusMeters must be greater than 0'),
          ),
        ),
      );
    });

    test('throws DomainException when startRadiusMeters < 0', () {
      expect(
        () => makeManualExecution(startRadiusMeters: -1),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts startRadiusMeters = 1 (lower boundary)', () {
      final execution = makeManualExecution(startRadiusMeters: 1);
      expect(execution.startRadiusMeters, 1);
    });

    test('throws DomainException when endRadiusMeters = 0', () {
      expect(
        () => makeManualExecution(endRadiusMeters: 0),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when endRadiusMeters < 0', () {
      expect(
        () => makeManualExecution(endRadiusMeters: -1),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts endRadiusMeters = 1 (lower boundary)', () {
      final execution = makeManualExecution(endRadiusMeters: 1);
      expect(execution.endRadiusMeters, 1);
    });

    // ── Financial boundary validation ──────────────────────
    test('throws DomainException when contractualValue.cents = 0', () {
      expect(
        () => makeManualExecution(contractualValue: const Money(0)),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('contractualValue must be greater than 0'),
          ),
        ),
      );
    });

    test('accepts contractualValue.cents = 1 (lower boundary)', () {
      final execution = makeManualExecution(contractualValue: const Money(1));
      expect(execution.contractualValue.cents, 1);
    });

    test('throws DomainException when contractualValue.cents < 0', () {
      expect(
        () => makeManualExecution(contractualValue: const Money(-1)),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when noShowPenaltyBps = 9999', () {
      expect(
        () => makeManualExecution(noShowPenaltyBps: 9999),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('noShowPenaltyBps must be >= 10000'),
          ),
        ),
      );
    });

    test('throws DomainException when noShowPenaltyBps < 10000', () {
      expect(
        () => makeManualExecution(noShowPenaltyBps: 0),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts noShowPenaltyBps = 10000 (lower boundary)', () {
      final execution = makeManualExecution(noShowPenaltyBps: 10000);
      expect(execution.noShowPenaltyBps, 10000);
    });
  });

  // ── Group 2: Projected SET Creation ──────────────────────────────────
  group('Projected SET Creation (createProjected)', () {
    test('creates successfully with all valid parameters', () {
      final execution = makeProjectedExecution();

      expect(execution.setId, isNotEmpty);
      expect(execution.setId.length, 64);
      expect(execution.scheduledStartTimeUtc, validStartTime);
      expect(execution.scheduledEndTimeUtc, validEndTime);
      expect(execution.originZoneId, 'zone-origin');
      expect(execution.destinationZoneId, 'zone-dest');
      expect(execution.startLatitude, validStartLat);
      expect(execution.startLongitude, validStartLng);
      expect(execution.startRadiusMeters, validRadius);
      expect(execution.endLatitude, validEndLat);
      expect(execution.endLongitude, validEndLng);
      expect(execution.endRadiusMeters, validRadius);
      expect(execution.contractualValue.cents, 15000);
      expect(execution.noShowPenaltyBps, validNoShowBps);
      expect(execution.delayToleranceMinutes, 5);
      expect(execution.delayPenaltyPerMinute!.cents, 50);
      expect(execution.downgradePenaltyFlat!.cents, 5000);
      expect(execution.isProjected, isTrue);
    });

    test(
      'SET id is deterministic for same planDeclarationId + shiftPatternIndex + operationalDate',
      () {
        final id1 = makeProjectedExecution(
          planDeclarationId: 'plan-X',
          shiftPatternIndex: 2,
          operationalDate: DateTime.utc(2026, 4, 1),
        ).setId;
        final id2 = makeProjectedExecution(
          planDeclarationId: 'plan-X',
          shiftPatternIndex: 2,
          operationalDate: DateTime.utc(2026, 4, 1),
        ).setId;

        expect(id1, equals(id2));
      },
    );

    test('SET id changes when planDeclarationId differs', () {
      final id1 = makeProjectedExecution(planDeclarationId: 'plan-A').setId;
      final id2 = makeProjectedExecution(planDeclarationId: 'plan-B').setId;

      expect(id1, isNot(equals(id2)));
    });

    test('SET id changes when shiftPatternIndex differs', () {
      final id1 = makeProjectedExecution(shiftPatternIndex: 0).setId;
      final id2 = makeProjectedExecution(shiftPatternIndex: 1).setId;

      expect(id1, isNot(equals(id2)));
    });

    test('SET id changes when operationalDate differs by 1 day', () {
      final id1 = makeProjectedExecution(
        operationalDate: DateTime.utc(2026, 3, 15),
      ).setId;
      final id2 = makeProjectedExecution(
        operationalDate: DateTime.utc(2026, 3, 16),
      ).setId;

      expect(id1, isNot(equals(id2)));
    });

    test('shiftPatternIndex is preserved', () {
      final execution = makeProjectedExecution(shiftPatternIndex: 3);
      expect(execution.shiftPatternIndex, 3);
    });

    test('operationalDate is preserved as UTC', () {
      final opDate = DateTime.utc(2026, 4, 10);
      final execution = makeProjectedExecution(operationalDate: opDate);
      expect(execution.operationalDate, opDate);
      expect(execution.operationalDate!.isUtc, isTrue);
    });

    test('SLA penalty snapshot fields are preserved', () {
      final execution = makeProjectedExecution(
        delayToleranceMinutes: 10,
        delayPenaltyPerMinute: const Money(75),
        downgradePenaltyFlat: const Money(7500),
      );

      expect(execution.delayToleranceMinutes, 10);
      expect(execution.delayPenaltyPerMinute!.cents, 75);
      expect(execution.downgradePenaltyFlat!.cents, 7500);
    });

    test('plannedVehicleId is optional for projected SETs', () {
      final execution = makeProjectedExecution(plannedVehicleId: 'vehicle-99');
      expect(execution.plannedVehicleId, 'vehicle-99');
    });

    // ── Validation invariants (same as manual) ────────────
    test('throws when scheduledEndTimeUtc <= startTime', () {
      expect(
        () => makeProjectedExecution(scheduledEndTimeUtc: validStartTime),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when startLatitude out of range', () {
      expect(
        () => makeProjectedExecution(startLatitude: -91.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when endLatitude out of range', () {
      expect(
        () => makeProjectedExecution(endLatitude: 91.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when startLongitude out of range', () {
      expect(
        () => makeProjectedExecution(startLongitude: -181.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when endLongitude out of range', () {
      expect(
        () => makeProjectedExecution(endLongitude: 181.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when startRadiusMeters = 0', () {
      expect(
        () => makeProjectedExecution(startRadiusMeters: 0),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when endRadiusMeters = 0', () {
      expect(
        () => makeProjectedExecution(endRadiusMeters: 0),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when contractualValue.cents <= 0', () {
      expect(
        () => makeProjectedExecution(contractualValue: const Money(0)),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws when noShowPenaltyBps < 10000', () {
      expect(
        () => makeProjectedExecution(noShowPenaltyBps: 9999),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── Group 3: Reconstitution ───────────────────────────────────────────
  group('Reconstitution', () {
    test('reconstitutes manual SET preserving all fields', () {
      final original = makeManualExecution(plannedVehicleId: 'v-001');
      final reconstituted = ContractualServiceExecution.reconstitute(
        setId: original.setId,
        scheduledStartTimeUtc: original.scheduledStartTimeUtc,
        scheduledEndTimeUtc: original.scheduledEndTimeUtc,
        startLatitude: original.startLatitude,
        startLongitude: original.startLongitude,
        startRadiusMeters: original.startRadiusMeters,
        endLatitude: original.endLatitude,
        endLongitude: original.endLongitude,
        endRadiusMeters: original.endRadiusMeters,
        plannedVehicleId: original.plannedVehicleId,
        contractualValue: original.contractualValue,
        noShowPenaltyBps: original.noShowPenaltyBps,
      );

      expect(reconstituted.setId, original.setId);
      expect(
        reconstituted.scheduledStartTimeUtc,
        original.scheduledStartTimeUtc,
      );
      expect(reconstituted.scheduledEndTimeUtc, original.scheduledEndTimeUtc);
      expect(reconstituted.startLatitude, original.startLatitude);
      expect(reconstituted.startLongitude, original.startLongitude);
      expect(reconstituted.startRadiusMeters, original.startRadiusMeters);
      expect(reconstituted.endLatitude, original.endLatitude);
      expect(reconstituted.endLongitude, original.endLongitude);
      expect(reconstituted.endRadiusMeters, original.endRadiusMeters);
      expect(reconstituted.plannedVehicleId, original.plannedVehicleId);
      expect(
        reconstituted.contractualValue.cents,
        original.contractualValue.cents,
      );
      expect(reconstituted.noShowPenaltyBps, original.noShowPenaltyBps);
      expect(reconstituted.isProjected, isFalse);
    });

    test(
      'reconstitutes projected SET preserving all fields including SLA snapshot',
      () {
        const delayPenalty = Money(100);
        const downgradePenalty = Money(10000);
        final original = makeProjectedExecution(
          planDeclarationId: 'plan-recon',
          shiftPatternIndex: 5,
          operationalDate: DateTime.utc(2026, 5, 20),
          delayToleranceMinutes: 10,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
          plannedVehicleId: 'v-recon',
        );

        final reconstituted = ContractualServiceExecution.reconstitute(
          setId: original.setId,
          scheduledStartTimeUtc: original.scheduledStartTimeUtc,
          scheduledEndTimeUtc: original.scheduledEndTimeUtc,
          startLatitude: original.startLatitude,
          startLongitude: original.startLongitude,
          startRadiusMeters: original.startRadiusMeters,
          endLatitude: original.endLatitude,
          endLongitude: original.endLongitude,
          endRadiusMeters: original.endRadiusMeters,
          plannedVehicleId: original.plannedVehicleId,
          contractualValue: original.contractualValue,
          noShowPenaltyBps: original.noShowPenaltyBps,
          originZoneId: original.originZoneId,
          destinationZoneId: original.destinationZoneId,
          operationalDate: original.operationalDate,
          shiftPatternIndex: original.shiftPatternIndex,
          delayToleranceMinutes: original.delayToleranceMinutes,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
        );

        expect(reconstituted.setId, original.setId);
        expect(reconstituted.originZoneId, 'zone-origin');
        expect(reconstituted.destinationZoneId, 'zone-dest');
        expect(reconstituted.operationalDate, DateTime.utc(2026, 5, 20));
        expect(reconstituted.shiftPatternIndex, 5);
        expect(reconstituted.delayToleranceMinutes, 10);
        expect(reconstituted.delayPenaltyPerMinute, isNotNull);
        expect(reconstituted.delayPenaltyPerMinute!.cents, 100);
        expect(reconstituted.downgradePenaltyFlat!.cents, 10000);
        expect(reconstituted.isProjected, isTrue);
      },
    );

    test('reconstitution does NOT regenerate SET id — uses provided setId', () {
      const customId = 'custom-persisted-set-id-12345';
      final reconstituted = ContractualServiceExecution.reconstitute(
        setId: customId,
        scheduledStartTimeUtc: validStartTime,
        scheduledEndTimeUtc: validEndTime,
        startLatitude: validStartLat,
        startLongitude: validStartLng,
        startRadiusMeters: validRadius,
        endLatitude: validEndLat,
        endLongitude: validEndLng,
        endRadiusMeters: validRadius,
        contractualValue: validContractualValue,
        noShowPenaltyBps: validNoShowBps,
      );

      expect(reconstituted.setId, customId);
    });

    test('reconstitution handles all nullable fields as null', () {
      final reconstituted = ContractualServiceExecution.reconstitute(
        setId: 'recon-null-fields',
        scheduledStartTimeUtc: validStartTime,
        scheduledEndTimeUtc: validEndTime,
        startLatitude: validStartLat,
        startLongitude: validStartLng,
        startRadiusMeters: validRadius,
        endLatitude: validEndLat,
        endLongitude: validEndLng,
        endRadiusMeters: validRadius,
        contractualValue: validContractualValue,
        noShowPenaltyBps: validNoShowBps,
      );

      expect(reconstituted.plannedVehicleId, isNull);
      expect(reconstituted.originZoneId, isNull);
      expect(reconstituted.destinationZoneId, isNull);
      expect(reconstituted.operationalDate, isNull);
      expect(reconstituted.shiftPatternIndex, isNull);
      expect(reconstituted.delayToleranceMinutes, isNull);
      expect(reconstituted.delayPenaltyPerMinute, isNull);
      expect(reconstituted.downgradePenaltyFlat, isNull);
    });

    test('reconstitution preserves non-null nullable fields', () {
      final reconstituted = ContractualServiceExecution.reconstitute(
        setId: 'recon-non-null',
        scheduledStartTimeUtc: validStartTime,
        scheduledEndTimeUtc: validEndTime,
        startLatitude: validStartLat,
        startLongitude: validStartLng,
        startRadiusMeters: validRadius,
        endLatitude: validEndLat,
        endLongitude: validEndLng,
        endRadiusMeters: validRadius,
        contractualValue: validContractualValue,
        noShowPenaltyBps: validNoShowBps,
        originZoneId: 'zone-A',
        destinationZoneId: 'zone-B',
        operationalDate: DateTime.utc(2026, 5, 1),
        shiftPatternIndex: 7,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: const Money(200),
        downgradePenaltyFlat: const Money(20000),
      );

      expect(reconstituted.originZoneId, 'zone-A');
      expect(reconstituted.destinationZoneId, 'zone-B');
      expect(reconstituted.operationalDate, DateTime.utc(2026, 5, 1));
      expect(reconstituted.shiftPatternIndex, 7);
      expect(reconstituted.delayToleranceMinutes, 15);
      expect(reconstituted.delayPenaltyPerMinute!.cents, 200);
      expect(reconstituted.downgradePenaltyFlat!.cents, 20000);
    });
  });
}
