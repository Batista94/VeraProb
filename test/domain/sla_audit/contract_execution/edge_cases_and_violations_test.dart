import 'package:test/test.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/shared/money.dart';
import '_contract_execution_helpers.dart';

void main() {
  // ── Group 7: Equality & Identity ──────────────────────────────────────
  group('Equality & Identity', () {
    test('two instances with same setId are equal', () {
      const setId = 'shared-set-id';
      final a = ContractualServiceExecution.reconstitute(
        setId: setId,
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

  // ── Group 8: isProjected Behavior ─────────────────────────────────────
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
        shiftPatternIndex: 0,
      );
      expect(execution.isProjected, isTrue);
    });

    test('returns false when shiftPatternIndex is null', () {
      final execution = ContractualServiceExecution.reconstitute(
        setId: 'manual-recon',
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
        shiftPatternIndex: null,
      );
      expect(execution.isProjected, isFalse);
    });
  });
}
