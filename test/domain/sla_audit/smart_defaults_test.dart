import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/smart_defaults.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';

void main() {
  group('SmartDefaults', () {
    test('retorna SLAPenalties válido para todas as verticals', () {
      for (final vertical in TransportVertical.values) {
        final penalties = SmartDefaults.defaultsFor(vertical);

        expect(penalties.noShowPenaltyBps, greaterThanOrEqualTo(10000));
        expect(penalties.delayToleranceMinutes, greaterThanOrEqualTo(0));
        expect(penalties.delayPenaltyPerMinute.cents, greaterThan(0));
        expect(penalties.downgradePenaltyFlat.cents, greaterThan(0));
        expect(penalties.noShowThresholdMinutes, greaterThan(0));
        expect(penalties.earlyArrivalToleranceMinutes, greaterThanOrEqualTo(0));
        expect(penalties.dwellTimeMinutes, greaterThanOrEqualTo(0));
        expect(penalties.gracePeriodMinutes, greaterThanOrEqualTo(0));
        expect(penalties.baseTripValue.cents, greaterThanOrEqualTo(0));
      }
    });

    test('fretamento tem tolerância de 15min e multiplier 2.0', () {
      final p = SmartDefaults.defaultsFor(TransportVertical.fretamento);

      expect(p.delayToleranceMinutes, 15);
      expect(p.noShowPenaltyBps, 20000);
    });

    test('cargaSeca tem tolerância de 30min e multiplier 1.5', () {
      final p = SmartDefaults.defaultsFor(TransportVertical.cargaSeca);

      expect(p.delayToleranceMinutes, 30);
      expect(p.noShowPenaltyBps, 15000);
    });

    test('cargaRefrigerada tem multiplier alto (2.5) e tolerância curta', () {
      final p = SmartDefaults.defaultsFor(TransportVertical.cargaRefrigerada);

      expect(p.noShowPenaltyBps, 25000);
      expect(p.delayToleranceMinutes, 10);
    });

    test('escolar tem multiplier mais severo (3.0)', () {
      final p = SmartDefaults.defaultsFor(TransportVertical.escolar);

      expect(p.noShowPenaltyBps, 30000);
      expect(p.delayToleranceMinutes, 5);
    });

    test('transferenciaFuncionarios tem noShowThreshold de 30min', () {
      final p = SmartDefaults.defaultsFor(
        TransportVertical.transferenciaFuncionarios,
      );

      expect(p.noShowThresholdMinutes, 30);
    });

    test('custom tem baseTripValue zero (operador deve preencher)', () {
      final p = SmartDefaults.defaultsFor(TransportVertical.custom);

      expect(p.baseTripValue.cents, 0);
    });

    test('cada vertical retorna instância distinta', () {
      final a = SmartDefaults.defaultsFor(TransportVertical.fretamento);
      final b = SmartDefaults.defaultsFor(TransportVertical.cargaSeca);

      expect(a, isNot(equals(b)));
    });
  });
}
