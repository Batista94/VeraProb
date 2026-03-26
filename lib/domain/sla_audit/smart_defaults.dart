import '../shared/money.dart';
import 'sla_penalties.dart';
import 'transport_vertical.dart';

/// Provides pre-computed [SLAPenalties] defaults for each [TransportVertical].
///
/// All values are heuristic-based and baked into the domain layer.
/// No DB calls, no infrastructure dependencies (INV-18).
/// All monetary values use [Money] (BIGINT cents — INV-19).
abstract final class SmartDefaults {
  /// Returns recommended penalty defaults for the given [vertical].
  static SLAPenalties defaultsFor(TransportVertical vertical) {
    return switch (vertical) {
      TransportVertical.fretamento => SLAPenalties.create(
        noShowPenaltyMultiplier: 2.0,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: const Money(100),
        downgradePenaltyFlat: const Money(15000),
        noShowThresholdMinutes: 60,
        earlyArrivalToleranceMinutes: 5,
        dwellTimeMinutes: 3,
        gracePeriodMinutes: 0,
        baseTripValue: const Money(50000),
      ),
      TransportVertical.cargaSeca => SLAPenalties.create(
        noShowPenaltyMultiplier: 1.5,
        delayToleranceMinutes: 30,
        delayPenaltyPerMinute: const Money(50),
        downgradePenaltyFlat: const Money(5000),
        noShowThresholdMinutes: 90,
        earlyArrivalToleranceMinutes: 10,
        dwellTimeMinutes: 5,
        gracePeriodMinutes: 5,
        baseTripValue: const Money(80000),
      ),
      TransportVertical.cargaRefrigerada => SLAPenalties.create(
        noShowPenaltyMultiplier: 2.5,
        delayToleranceMinutes: 10,
        delayPenaltyPerMinute: const Money(200),
        downgradePenaltyFlat: const Money(20000),
        noShowThresholdMinutes: 45,
        earlyArrivalToleranceMinutes: 5,
        dwellTimeMinutes: 5,
        gracePeriodMinutes: 0,
        baseTripValue: const Money(120000),
      ),
      TransportVertical.transferenciaFuncionarios => SLAPenalties.create(
        noShowPenaltyMultiplier: 2.0,
        delayToleranceMinutes: 10,
        delayPenaltyPerMinute: const Money(150),
        downgradePenaltyFlat: const Money(10000),
        noShowThresholdMinutes: 30,
        earlyArrivalToleranceMinutes: 5,
        dwellTimeMinutes: 3,
        gracePeriodMinutes: 0,
        baseTripValue: const Money(40000),
      ),
      TransportVertical.escolar => SLAPenalties.create(
        noShowPenaltyMultiplier: 3.0,
        delayToleranceMinutes: 5,
        delayPenaltyPerMinute: const Money(200),
        downgradePenaltyFlat: const Money(15000),
        noShowThresholdMinutes: 20,
        earlyArrivalToleranceMinutes: 3,
        dwellTimeMinutes: 2,
        gracePeriodMinutes: 0,
        baseTripValue: const Money(35000),
      ),
      TransportVertical.custom => SLAPenalties.create(
        noShowPenaltyMultiplier: 1.5,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: const Money(50),
        downgradePenaltyFlat: const Money(5000),
        noShowThresholdMinutes: 60,
        earlyArrivalToleranceMinutes: 5,
        dwellTimeMinutes: 3,
        gracePeriodMinutes: 0,
        baseTripValue: const Money(0),
      ),
    };
  }
}
