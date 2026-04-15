import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/application/sla_audit/telemetry/telemetry_normalization_handler.dart';
import 'package:veraprob/domain/sla_audit/telemetry/raw_telemetry_batch.dart';
import 'package:veraprob/domain/sla_audit/telemetry/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/telemetry/spoofing_detected_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

class MockFactQueue extends Mock implements FactQueue {}

class MockLedgerRepository extends Mock implements SlaLedgerRepository {}

void main() {
  late TelemetryNormalizationHandler handler;
  late TelemetryNormalizer normalizer;
  late MockFactQueue mockFactQueue;
  late MockLedgerRepository mockLedger;

  setUp(() {
    normalizer = TelemetryNormalizer();
    mockFactQueue = MockFactQueue();
    mockLedger = MockLedgerRepository();
    handler = TelemetryNormalizationHandler(
      normalizer: normalizer,
      ledgerRepository: mockLedger,
      factQueue: mockFactQueue,
    );

    registerFallbackValue(
      CanonicalFact(
        deviceId: '',
        occurredAt: DateTime.now().toUtc(),
        latitude: 0.0,
        longitude: 0.0,
        organizationId: '',
      ),
    );
    registerFallbackValue(
      SlaLedgerEntry(
        organizationId: '',
        type: '',
        contractId: '',
        planVersion: 1,
        occurredAtUtc: DateTime.now().toUtc(),
        operatorId: 'SYSTEM',
      ),
    );
  });

  group('EDGE-GPS: Spoofing Detection', () {
    test(
      'Rejeita lote de coordenadas sintéticas (variação zero) apontando para Fake GPS',
      () async {
        final baseTime = DateTime.utc(2026, 4, 14, 20, 0, 0);
        final syntheticBatch = RawTelemetryBatch(
          deviceId: 'device-fake-001',
          organizationId: 'org-test',
          callerUserId: 'fraudster-user-123',
          coordinates: [
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: baseTime,
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: baseTime.add(const Duration(seconds: 1)),
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: baseTime.add(const Duration(seconds: 2)),
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: baseTime.add(const Duration(seconds: 3)),
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: baseTime.add(const Duration(seconds: 4)),
            ),
          ],
        );

        when(
          () => mockLedger.append(any()),
        ).thenAnswer((_) async => 'ledger-id-123');

        await expectLater(
          handler.normalize(syntheticBatch),
          throwsA(isA<SpoofingDetectedException>()),
        );

        verifyNever(() => mockFactQueue.enqueue(any()));

        final captured = verify(() => mockLedger.append(captureAny())).captured;
        expect(captured.length, 1);

        final ledgerEntry = captured.first as SlaLedgerEntry;
        expect(ledgerEntry.type, 'SPOOFING_DETECTED');
        expect(ledgerEntry.payload['callerUserId'], 'fraudster-user-123');
        expect(ledgerEntry.payload['deviceId'], 'device-fake-001');
        expect(ledgerEntry.payload['reason'], contains('zero variance'));
      },
    );
  });
}
