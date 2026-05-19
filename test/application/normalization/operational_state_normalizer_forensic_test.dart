// ignore_for_file: lines_longer_than_80_chars
// =============================================================================
// SUÍTE 7: Forensic Integrity & Idempotência
//
// Valida:
//   - stateChangedAt == ping.timestamp do 1º ping em 10 pings Moving seguidos
//   - stateChangedAt não avança quando motionState não muda
//   - Ping stale é descartado sem corromper estado
// =============================================================================

import 'package:test/test.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/operational_state_normalizer.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

// Constante top-level para uso em contextos const
final _kEpoch = DateTime.utc(2026, 4, 7, 12, 0, 0);

void main() {
  final kEpoch = _kEpoch;
  const kLat = -23.5612;
  const kLng = -46.6560;

  OperationalStateNormalizer makeNormalizer(FakeDateTimeProvider clock) =>
      OperationalStateNormalizer(
        debounceDuration: const Duration(seconds: 5),
        clock: clock,
      );

  VehiclePosition makePing(DateTime ts, {double speed = 20.0}) =>
      VehiclePosition(
        tripId: 'trip-1',
        latitude: kLat,
        longitude: kLng,
        speed: speed,
        timestamp: ts,
        source: 'test',
        vehiclePlate: 'TEST-001',
      );

  group('SUÍTE 7: Forensic Integrity & Idempotência', () {
    test(
      '7.1: 10 pings Moving (2s apart) → stateChangedAt == timestamp do 1º ping em todos',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock);

        // 10 pings com intervalo 2s (< debounce 5s) — 9 serão descartados pelo debounce
        final pings = List.generate(
          10,
          (i) => makePing(kEpoch.add(Duration(seconds: i * 2))),
        );

        final results = normalizer.normalize(
          pings,
          now: kEpoch.add(const Duration(seconds: 20)),
        );

        expect(results, hasLength(10));

        final expectedStateChangedAt = pings.first.timestamp;
        for (int i = 0; i < results.length; i++) {
          expect(
            results[i].stateChangedAt,
            expectedStateChangedAt,
            reason:
                'stateChangedAt no resultado $i deve ser igual ao timestamp do 1º ping',
          );
        }
      },
    );

    test(
      '7.2: Mudança de motionState avança stateChangedAt para ping.timestamp (não effectiveNow)',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock);

        // Ping 1: Moving
        final ping1 = makePing(kEpoch, speed: 20.0);
        final r1 = normalizer.normalize([
          ping1,
        ], now: kEpoch.add(const Duration(seconds: 1)));
        expect(r1.first.stateChangedAt, ping1.timestamp);

        // Ping 2: ainda Moving (6s depois, fora do debounce, mesmo motionState)
        clock.advance(const Duration(seconds: 6));
        final ping2 = makePing(clock.nowUtc(), speed: 20.0);
        final r2 = normalizer.normalize([ping2], now: clock.nowUtc());

        // stateChangedAt deve permanecer igual ao ping1.timestamp
        expect(
          r2.first.stateChangedAt,
          ping1.timestamp,
          reason: 'stateChangedAt não deve avançar se motionState não mudou',
        );
      },
    );

    test(
      '7.4: Igualdade Lógica — stateA(ts:10:00) == stateB(ts:10:05) quando motionState idêntico',
      () {
        // Constrói dois estados idênticos exceto por stateChangedAt
        final base = VehicleOperationalState(
          vehicleId: 'TEST-001',
          tripId: 'trip-1',
          latitude: kLat,
          longitude: kLng,
          smoothedSpeed: 20.0,
          rawSpeed: 20.0, // Physical Metric - Double Required
          motionState: MotionState.moving,
          connectivityState: ConnectivityState.healthy,
          lastRawPingAt: _kEpoch,
          stateChangedAt: _kEpoch,
          confidence: 1.0,
          source: 'test',
        );

        final stateA = base;
        final stateB = base.copyWith(
          stateChangedAt: _kEpoch.add(const Duration(minutes: 5)),
        );

        // stateChangedAt foi removido de props → não afeta ==
        expect(
          stateA,
          equals(stateB),
          reason:
              'stateChangedAt excluído de props: estados logicamente iguais',
        );
        expect(stateA == stateB, isTrue);
      },
    );

    test(
      '7.3: REJECTED_STALE_EVENT — ping com timestamp anterior ao último processado é descartado',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock);

        // Estabelecer estado com ping em T+10s
        final ping1 = makePing(kEpoch.add(const Duration(seconds: 10)));
        normalizer.normalize([
          ping1,
        ], now: kEpoch.add(const Duration(seconds: 11)));

        // Enviar ping stale (T+5s < T+10s)
        final stalePing = makePing(kEpoch.add(const Duration(seconds: 5)));
        final results = normalizer.normalize([
          stalePing,
        ], now: kEpoch.add(const Duration(seconds: 12)));

        expect(results, hasLength(1));
        expect(
          results.first.lastRawPingAt,
          ping1.timestamp,
          reason: 'Ping stale não deve substituir lastRawPingAt',
        );
      },
    );
  });
}
