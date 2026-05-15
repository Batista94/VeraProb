import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/telemetry/telemetry_normalization_handler.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart' as domain_fact;
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/telemetry/raw_telemetry_batch.dart';
import 'package:veraprob/domain/sla_audit/telemetry/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/telemetry/spoofing_detected_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/sla_audit/spoofing_detector.dart';
import 'package:veraprob/domain/sla_audit/spoofing_risk_score.dart';

class MockFactQueue extends Mock implements FactQueue {}

class MockLedgerRepository extends Mock implements SlaLedgerRepository {}

class MockTenantValidator extends Mock implements TenantValidationService {}

class MockSpoofingDetector extends Mock implements SpoofingDetector {}

class FakeClock extends Fake implements IDateTimeProvider {
  final DateTime _now;
  FakeClock(this._now);
  @override
  DateTime nowUtc() => _now;
}

void main() {
  late TelemetryNormalizationHandler handler;
  late TelemetryNormalizer normalizer;
  late MockFactQueue mockFactQueue;
  late MockLedgerRepository mockLedger;
  late MockTenantValidator mockTenant;
  late MockSpoofingDetector mockSpoofingDetector;
  late FakeClock clock;

  final kEpoch = DateTime.utc(2026, 4, 14, 20, 0, 0);

  setUp(() {
    normalizer = TelemetryNormalizer();
    mockFactQueue = MockFactQueue();
    mockLedger = MockLedgerRepository();
    mockTenant = MockTenantValidator();
    mockSpoofingDetector = MockSpoofingDetector();
    clock = FakeClock(kEpoch);

    when(
      () => mockSpoofingDetector.analyze(any()),
    ).thenReturn(SpoofingRiskScore.zero());

    // INV-1: Tenant validation stub — any call matching 'org-test' passes
    when(
      () => mockTenant.assertTenantMatches(
        payloadOrgId: 'org-test',
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    handler = TelemetryNormalizationHandler(
      normalizer: normalizer,
      ledgerRepository: mockLedger,
      factQueue: mockFactQueue,
      clock: clock,
      tenantValidator: mockTenant,
      spoofingDetector: mockSpoofingDetector,
    );

    registerFallbackValue(
      CanonicalFact(
        deviceId: '',
        occurredAt: kEpoch,
        latitude: 0.0,
        longitude: 0.0,
        organizationId: '',
      ),
    );
    registerFallbackValue(
      domain_fact.CanonicalFact.reconstitute(
        id: '',
        organizationId: 'org-fallback',
        rawPayloadId: '',
        deviceId: '',
        sourceAdapter: '',
        receivedAtUtc: kEpoch,
        gpsTimestamp: kEpoch,
        lat: 0.0,
        lng: 0.0,
        integrityFlag: IngestionIntegrityFlag.ok,
      ),
    );
    registerFallbackValue(
      SlaLedgerEntry(
        organizationId: '',
        type: '',
        contractId: '',
        planVersion: 1,
        occurredAtUtc: kEpoch,
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

        // Override: zero-variance batch must be flagged as suspected
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 10000, signals: []));

        when(
          () => mockLedger.append(any()),
        ).thenAnswer((_) async => 'ledger-id-123');

        await expectLater(
          handler.normalize(syntheticBatch, sessionId: 'session-1'),
          throwsA(isA<SpoofingDetectedException>()),
        );

        verifyNever(() => mockFactQueue.enqueue(any()));

        final captured = verify(() => mockLedger.append(captureAny())).captured;
        expect(captured.length, 1);

        final ledgerEntry = captured.first as SlaLedgerEntry;
        expect(ledgerEntry.type, 'SPOOFING_DETECTED');
        expect(ledgerEntry.payload['callerUserId'], 'fraudster-user-123');
        expect(ledgerEntry.payload['deviceId'], 'device-fake-001');
        expect(ledgerEntry.payload['reason'], isNotEmpty);
      },
    );

    test('INV-1: Cross-tenant batch is rejected before processing', () async {
      when(
        () => mockTenant.assertTenantMatches(
          payloadOrgId: 'org-attacker',
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async => throw Exception('SovereigntyViolation'));

      final attackerBatch = RawTelemetryBatch(
        deviceId: 'device-attacker',
        organizationId: 'org-attacker',
        callerUserId: 'attacker-1',
        coordinates: [
          TelemetryCoordinate(
            latitude: -23.550520,
            longitude: -46.633308,
            occurredAt: kEpoch,
          ),
        ],
      );

      await expectLater(
        handler.normalize(attackerBatch, sessionId: 'session-1'),
        throwsException,
      );

      verifyNever(() => mockLedger.append(any()));
      verifyNever(() => mockFactQueue.enqueue(any()));
    });

    test(
      'INV-3: Ledger entry uses deterministic UTC from clock (not DateTime.now)',
      () async {
        when(
          () => mockTenant.assertTenantMatches(
            payloadOrgId: 'org-test',
            sessionId: any(named: 'sessionId'),
          ),
        ).thenAnswer((_) async {});

        // Override: zero-variance batch must be flagged as suspected
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 10000, signals: []));

        when(
          () => mockLedger.append(any()),
        ).thenAnswer((_) async => 'ledger-id-utc');

        final batch = RawTelemetryBatch(
          deviceId: 'device-utc-001',
          organizationId: 'org-test',
          callerUserId: 'utc-user',
          coordinates: [
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: kEpoch,
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: kEpoch.add(const Duration(seconds: 1)),
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: kEpoch.add(const Duration(seconds: 2)),
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: kEpoch.add(const Duration(seconds: 3)),
            ),
            TelemetryCoordinate(
              latitude: -23.550520,
              longitude: -46.633308,
              occurredAt: kEpoch.add(const Duration(seconds: 4)),
            ),
          ],
        );

        await expectLater(
          handler.normalize(batch, sessionId: 'session-1'),
          throwsA(isA<SpoofingDetectedException>()),
        );

        final captured = verify(() => mockLedger.append(captureAny())).captured;
        final ledgerEntry = captured.first as SlaLedgerEntry;

        // INV-3: occurredAtUtc MUST equal the fake clock's time
        expect(ledgerEntry.occurredAtUtc, equals(kEpoch));
        expect(ledgerEntry.occurredAtUtc.isUtc, isTrue);
      },
    );
  });
}
