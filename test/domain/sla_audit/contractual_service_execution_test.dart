import 'package:test/test.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/money.dart';

// ── Test Helpers ──────────────────────────────────────────────────────────

/// Valid constants for test fixtures.
const _validContractId = 'contract-001';
final _validStartTime = DateTime.utc(2026, 3, 15, 8, 0);
final _validEndTime = DateTime.utc(2026, 3, 15, 9, 0);
const _validStartLat = -23.5505;
const _validStartLng = -46.6333;
const _validEndLat = -23.5600;
const _validEndLng = -46.6400;
const _validRadius = 100;
const _validContractualValue = Money(15000);
const _validNoShowBps = 15000;

ContractualServiceExecution makeManualExecution({
  String contractId = _validContractId,
  DateTime? scheduledStartTimeUtc,
  DateTime? scheduledEndTimeUtc,
  double startLatitude = _validStartLat,
  double startLongitude = _validStartLng,
  int startRadiusMeters = _validRadius,
  double endLatitude = _validEndLat,
  double endLongitude = _validEndLng,
  int endRadiusMeters = _validRadius,
  String? plannedVehicleId,
  Money? contractualValue,
  int noShowPenaltyBps = _validNoShowBps,
}) {
  return ContractualServiceExecution.create(
    contractId: contractId,
    scheduledStartTimeUtc: scheduledStartTimeUtc ?? _validStartTime,
    scheduledEndTimeUtc: scheduledEndTimeUtc ?? _validEndTime,
    startLatitude: startLatitude,
    startLongitude: startLongitude,
    startRadiusMeters: startRadiusMeters,
    endLatitude: endLatitude,
    endLongitude: endLongitude,
    endRadiusMeters: endRadiusMeters,
    plannedVehicleId: plannedVehicleId,
    contractualValue: contractualValue ?? _validContractualValue,
    noShowPenaltyBps: noShowPenaltyBps,
  );
}

ContractualServiceExecution makeProjectedExecution({
  String planDeclarationId = 'plan-001',
  int shiftPatternIndex = 0,
  DateTime? operationalDate,
  DateTime? scheduledStartTimeUtc,
  DateTime? scheduledEndTimeUtc,
  String originZoneId = 'zone-origin',
  double startLatitude = _validStartLat,
  double startLongitude = _validStartLng,
  int startRadiusMeters = _validRadius,
  String destinationZoneId = 'zone-dest',
  double endLatitude = _validEndLat,
  double endLongitude = _validEndLng,
  int endRadiusMeters = _validRadius,
  Money? contractualValue,
  int noShowPenaltyBps = _validNoShowBps,
  int delayToleranceMinutes = 5,
  Money delayPenaltyPerMinute = const Money(50),
  Money downgradePenaltyFlat = const Money(5000),
  String? plannedVehicleId,
}) {
  return ContractualServiceExecution.createProjected(
    planDeclarationId: planDeclarationId,
    shiftPatternIndex: shiftPatternIndex,
    operationalDate: operationalDate ?? DateTime.utc(2026, 3, 15),
    scheduledStartTimeUtc: scheduledStartTimeUtc ?? _validStartTime,
    scheduledEndTimeUtc: scheduledEndTimeUtc ?? _validEndTime,
    originZoneId: originZoneId,
    startLatitude: startLatitude,
    startLongitude: startLongitude,
    startRadiusMeters: startRadiusMeters,
    destinationZoneId: destinationZoneId,
    endLatitude: endLatitude,
    endLongitude: endLongitude,
    endRadiusMeters: endRadiusMeters,
    contractualValue: contractualValue ?? _validContractualValue,
    noShowPenaltyBps: noShowPenaltyBps,
    delayToleranceMinutes: delayToleranceMinutes,
    delayPenaltyPerMinute: delayPenaltyPerMinute,
    downgradePenaltyFlat: downgradePenaltyFlat,
    plannedVehicleId: plannedVehicleId,
  );
}

// ── Test Suites ───────────────────────────────────────────────────────────

void main() {
  group('ContractualServiceExecution', () {
    // ── Group 1: Manual SET Creation ───────────────────────────────────
    group('Manual SET Creation (create)', () {
      test('creates successfully with minimum valid parameters', () {
        final execution = makeManualExecution();

        expect(execution.setId, isNotEmpty);
        expect(execution.setId.length, 64); // SHA-256 hex length
        expect(execution.scheduledStartTimeUtc, _validStartTime);
        expect(execution.scheduledEndTimeUtc, _validEndTime);
        expect(execution.startLatitude, _validStartLat);
        expect(execution.startLongitude, _validStartLng);
        expect(execution.startRadiusMeters, _validRadius);
        expect(execution.endLatitude, _validEndLat);
        expect(execution.endLongitude, _validEndLng);
        expect(execution.endRadiusMeters, _validRadius);
        expect(execution.plannedVehicleId, isNull);
        expect(execution.contractualValue.cents, 15000);
        expect(execution.noShowPenaltyBps, _validNoShowBps);
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
            () => makeManualExecution(scheduledEndTimeUtc: _validStartTime),
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

    // ── Group 2: Projected SET Creation ────────────────────────────────
    group('Projected SET Creation (createProjected)', () {
      test('creates successfully with all valid parameters', () {
        final execution = makeProjectedExecution();

        expect(execution.setId, isNotEmpty);
        expect(execution.setId.length, 64);
        expect(execution.scheduledStartTimeUtc, _validStartTime);
        expect(execution.scheduledEndTimeUtc, _validEndTime);
        expect(execution.originZoneId, 'zone-origin');
        expect(execution.destinationZoneId, 'zone-dest');
        expect(execution.startLatitude, _validStartLat);
        expect(execution.startLongitude, _validStartLng);
        expect(execution.startRadiusMeters, _validRadius);
        expect(execution.endLatitude, _validEndLat);
        expect(execution.endLongitude, _validEndLng);
        expect(execution.endRadiusMeters, _validRadius);
        expect(execution.contractualValue.cents, 15000);
        expect(execution.noShowPenaltyBps, _validNoShowBps);
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
        final execution = makeProjectedExecution(
          plannedVehicleId: 'vehicle-99',
        );
        expect(execution.plannedVehicleId, 'vehicle-99');
      });

      // ── Validation invariants (same as manual) ────────────
      test('throws when scheduledEndTimeUtc <= startTime', () {
        expect(
          () => makeProjectedExecution(scheduledEndTimeUtc: _validStartTime),
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

    // ── Group 3: Reconstitution ────────────────────────────────────────
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

      test(
        'reconstitution does NOT regenerate SET id — uses provided setId',
        () {
          const customId = 'custom-persisted-set-id-12345';
          final reconstituted = ContractualServiceExecution.reconstitute(
            setId: customId,
            scheduledStartTimeUtc: _validStartTime,
            scheduledEndTimeUtc: _validEndTime,
            startLatitude: _validStartLat,
            startLongitude: _validStartLng,
            startRadiusMeters: _validRadius,
            endLatitude: _validEndLat,
            endLongitude: _validEndLng,
            endRadiusMeters: _validRadius,
            contractualValue: _validContractualValue,
            noShowPenaltyBps: _validNoShowBps,
          );

          expect(reconstituted.setId, customId);
        },
      );

      test('reconstitution handles all nullable fields as null', () {
        final reconstituted = ContractualServiceExecution.reconstitute(
          setId: 'recon-null-fields',
          scheduledStartTimeUtc: _validStartTime,
          scheduledEndTimeUtc: _validEndTime,
          startLatitude: _validStartLat,
          startLongitude: _validStartLng,
          startRadiusMeters: _validRadius,
          endLatitude: _validEndLat,
          endLongitude: _validEndLng,
          endRadiusMeters: _validRadius,
          contractualValue: _validContractualValue,
          noShowPenaltyBps: _validNoShowBps,
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
          scheduledStartTimeUtc: _validStartTime,
          scheduledEndTimeUtc: _validEndTime,
          startLatitude: _validStartLat,
          startLongitude: _validStartLng,
          startRadiusMeters: _validRadius,
          endLatitude: _validEndLat,
          endLongitude: _validEndLng,
          endRadiusMeters: _validRadius,
          contractualValue: _validContractualValue,
          noShowPenaltyBps: _validNoShowBps,
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

    // ── Group 4: ID Integrity & Collision Resistance ────────────────────
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

      test(
        'changing contractId + radius by 1 meter produces different hash',
        () {
          final id1 = makeManualExecution().setId;
          final id2 = makeManualExecution(
            contractId: 'contract-different',
            startRadiusMeters: 101,
          ).setId;

          expect(id1, isNot(equals(id2)));
        },
      );

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

    // ── Group 5: Financial Integrity (INV-2, INV-19) ───────────────────
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

      test(
        'reconstituted SET preserves integer cents for all Money fields',
        () {
          const delayPenalty = Money(300);
          const downgradePenalty = Money(15000);
          final reconstituted = ContractualServiceExecution.reconstitute(
            setId: 'recon-financial',
            scheduledStartTimeUtc: _validStartTime,
            scheduledEndTimeUtc: _validEndTime,
            startLatitude: _validStartLat,
            startLongitude: _validStartLng,
            startRadiusMeters: _validRadius,
            endLatitude: _validEndLat,
            endLongitude: _validEndLng,
            endRadiusMeters: _validRadius,
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
        },
      );

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

    // ── Group 6: UTC Compliance (INV-9) ────────────────────────────────
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
          startLatitude: _validStartLat,
          startLongitude: _validStartLng,
          startRadiusMeters: _validRadius,
          endLatitude: _validEndLat,
          endLongitude: _validEndLng,
          endRadiusMeters: _validRadius,
          contractualValue: _validContractualValue,
          noShowPenaltyBps: _validNoShowBps,
        );

        expect(reconstituted.scheduledStartTimeUtc.isUtc, isTrue);
        expect(reconstituted.scheduledEndTimeUtc.isUtc, isTrue);
      });
    });

    // ── Group 7: Equality & Identity ───────────────────────────────────
    group('Equality & Identity', () {
      test('two instances with same setId are equal', () {
        const setId = 'shared-set-id';
        final a = ContractualServiceExecution.reconstitute(
          setId: setId,
          scheduledStartTimeUtc: _validStartTime,
          scheduledEndTimeUtc: _validEndTime,
          startLatitude: _validStartLat,
          startLongitude: _validStartLng,
          startRadiusMeters: _validRadius,
          endLatitude: _validEndLat,
          endLongitude: _validEndLng,
          endRadiusMeters: _validRadius,
          contractualValue: _validContractualValue,
          noShowPenaltyBps: _validNoShowBps,
        );
        final b = ContractualServiceExecution.reconstitute(
          setId: setId,
          scheduledStartTimeUtc: DateTime.utc(2027, 1, 1),
          scheduledEndTimeUtc: DateTime.utc(2027, 1, 2),
          startLatitude: 0.0,
          startLongitude: 0.0,
          startRadiusMeters: 50,
          endLatitude: 1.0,
          endLongitude: 1.0,
          endRadiusMeters: 50,
          contractualValue: const Money(1),
          noShowPenaltyBps: 10000,
        );

        // Equality based exclusively on setId (Equatable)
        expect(a == b, isTrue);
        expect(a.props, equals(b.props));
      });

      test('two instances with different setId are not equal', () {
        final a = makeManualExecution(contractId: 'contract-A');
        final b = makeManualExecution(contractId: 'contract-B');

        expect(a == b, isFalse);
        expect(a.props, isNot(equals(b.props)));
      });

      test('same instance equals itself', () {
        final a = makeManualExecution();
        expect(a == a, isTrue);
      });

      test('hashCode is consistent for equal instances', () {
        const setId = 'hash-test-id';
        final a = ContractualServiceExecution.reconstitute(
          setId: setId,
          scheduledStartTimeUtc: _validStartTime,
          scheduledEndTimeUtc: _validEndTime,
          startLatitude: _validStartLat,
          startLongitude: _validStartLng,
          startRadiusMeters: _validRadius,
          endLatitude: _validEndLat,
          endLongitude: _validEndLng,
          endRadiusMeters: _validRadius,
          contractualValue: _validContractualValue,
          noShowPenaltyBps: _validNoShowBps,
        );
        final b = ContractualServiceExecution.reconstitute(
          setId: setId,
          scheduledStartTimeUtc: DateTime.utc(2099, 12, 31),
          scheduledEndTimeUtc: DateTime.utc(2100, 1, 1),
          startLatitude: 45.0,
          startLongitude: 45.0,
          startRadiusMeters: 200,
          endLatitude: -45.0,
          endLongitude: -45.0,
          endRadiusMeters: 200,
          contractualValue: const Money(99999),
          noShowPenaltyBps: 50000,
        );

        expect(a.hashCode, equals(b.hashCode));
      });

      test('hashCode differs for different setId', () {
        final a = makeManualExecution(contractId: 'contract-X');
        final b = makeManualExecution(contractId: 'contract-Y');

        expect(a.hashCode, isNot(equals(b.hashCode)));
      });

      test('props list contains only setId', () {
        final execution = makeManualExecution();
        expect(execution.props, equals([execution.setId]));
      });
    });

    // ── Group 8: isProjected Behavior ──────────────────────────────────
    group('isProjected Behavior', () {
      test('returns false for manually-created SET', () {
        final execution = makeManualExecution();
        expect(execution.isProjected, isFalse);
      });

      test('returns true for projected SET', () {
        final execution = makeProjectedExecution(shiftPatternIndex: 0);
        expect(execution.isProjected, isTrue);
      });

      test('returns true for any non-null shiftPatternIndex', () {
        final execution = ContractualServiceExecution.reconstitute(
          setId: 'projected-recon',
          scheduledStartTimeUtc: _validStartTime,
          scheduledEndTimeUtc: _validEndTime,
          startLatitude: _validStartLat,
          startLongitude: _validStartLng,
          startRadiusMeters: _validRadius,
          endLatitude: _validEndLat,
          endLongitude: _validEndLng,
          endRadiusMeters: _validRadius,
          contractualValue: _validContractualValue,
          noShowPenaltyBps: _validNoShowBps,
          shiftPatternIndex: 0,
        );
        expect(execution.isProjected, isTrue);
      });

      test('returns false when shiftPatternIndex is null', () {
        final execution = ContractualServiceExecution.reconstitute(
          setId: 'manual-recon',
          scheduledStartTimeUtc: _validStartTime,
          scheduledEndTimeUtc: _validEndTime,
          startLatitude: _validStartLat,
          startLongitude: _validStartLng,
          startRadiusMeters: _validRadius,
          endLatitude: _validEndLat,
          endLongitude: _validEndLng,
          endRadiusMeters: _validRadius,
          contractualValue: _validContractualValue,
          noShowPenaltyBps: _validNoShowBps,
          shiftPatternIndex: null,
        );
        expect(execution.isProjected, isFalse);
      });
    });
  });
}
