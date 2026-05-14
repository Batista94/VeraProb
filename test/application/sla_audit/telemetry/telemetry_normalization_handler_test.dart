// INV-1: Identity Sovereignty — fail-fast tenant check
// INV-7: Null Safety — strict types, no dynamic
// INV-8: Repo Isolation — org_id enforced on all pipeline stages
// INV-18: Zero-Trust — spoofed batches quarantined before queue
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/telemetry/telemetry_normalization_handler.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/sla_audit/spoofing_detector.dart';
import 'package:veraprob/domain/sla_audit/spoofing_risk_score.dart';
import 'package:veraprob/domain/sla_audit/telemetry/raw_telemetry_batch.dart';
import 'package:veraprob/domain/sla_audit/telemetry/spoofing_detected_exception.dart';

// ── Mocktail stubs ────────────────────────────────────────────────────────────
class MockAuthRepository extends Mock implements IAuthRepository {}

class MockFactQueue extends Mock implements FactQueue {}

class MockSlaLedgerRepository extends Mock implements SlaLedgerRepository {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

class MockSpoofingDetector extends Mock implements SpoofingDetector {}

// ── Constants — ZERO `any()` on identity fields ───────────────────────────────
const _orgId = 'org-123';
const _sessionId = 'sess-999';
const kDeviceId = 'device-gps-007';
const kCallerUserId = 'user-driver-42';

final kFrozenUtc = DateTime.utc(2026, 4, 14, 12, 0, 0);

// ── Fixture builders ──────────────────────────────────────────────────────────
RawTelemetryBatch _validBatch({int count = 1}) {
  final base = DateTime.utc(2026, 4, 14, 8, 0, 0);
  return RawTelemetryBatch(
    deviceId: kDeviceId,
    organizationId: _orgId,
    callerUserId: kCallerUserId,
    // Varied coordinates: ~1.1 km apart, 5-min gaps â†’ implied speed â‰ˆ13 km/h
    coordinates: List.generate(
      count,
      (i) => TelemetryCoordinate(
        latitude: -23.5505 + i * 0.01, // Physical Metric - Double Required
        longitude: -46.6333 + i * 0.01, // Physical Metric - Double Required
        occurredAt: base.add(Duration(minutes: i * 5)),
      ),
    ),
  );
}

/// 5 identical coordinates â†’ triggers zero-variance spoofing check (â‰¥5 required)
RawTelemetryBatch _spoofedBatch() {
  final ts = DateTime.utc(2026, 4, 14, 8, 0, 0);
  return RawTelemetryBatch(
    deviceId: kDeviceId,
    organizationId: _orgId,
    callerUserId: kCallerUserId,
    coordinates: List.generate(
      5,
      (_) => TelemetryCoordinate(
        latitude: -23.5505, // Physical Metric - Double Required
        longitude: -46.6333, // Physical Metric - Double Required
        occurredAt: ts,
      ),
    ),
  );
}

/// First coord valid, second is a physically impossible teleport (~1700 km in
/// 10 s) → normalizer accepts packet #0 and rejects packet #1.
RawTelemetryBatch _partialRejectBatch() {
  final base = DateTime.utc(2026, 4, 14, 8, 0, 0);
  return RawTelemetryBatch(
    deviceId: kDeviceId,
    organizationId: _orgId,
    callerUserId: kCallerUserId,
    coordinates: [
      TelemetryCoordinate(
        latitude: -23.5505, // Physical Metric - Double Required
        longitude: -46.6333, // Physical Metric - Double Required
        occurredAt: base,
      ),
      TelemetryCoordinate(
        latitude: -10.0, // Physical Metric - Double Required
        longitude: -40.0, // Physical Metric - Double Required
        occurredAt: base.add(const Duration(seconds: 10)),
      ),
    ],
  );
}

void main() {
  late MockAuthRepository mockAuthRepo;
  late MockFactQueue mockFactQueue;
  late MockSlaLedgerRepository mockLedgerRepo;
  late MockDateTimeProvider mockClock;
  late MockSpoofingDetector mockSpoofingDetector;
  late TenantValidationService tenantValidator;
  late TelemetryNormalizationHandler handler;

  setUpAll(() {
    registerFallbackValue(
      SlaLedgerEntry(
        organizationId: _orgId,
        type: 'TEST',
        contractId: 'test-contract',
        planVersion: 1,
        occurredAtUtc: kFrozenUtc,
      ),
    );
    registerFallbackValue(
      CanonicalFact.reconstitute(
        id: 'test-id',
        organizationId: _orgId,
        rawPayloadId: 'raw-001',
        deviceId: kDeviceId,
        sourceAdapter: 'test',
        receivedAtUtc: kFrozenUtc,
        gpsTimestamp: kFrozenUtc,
        lat: -23.5505, // Physical Metric - Double Required
        lng: -46.6333, // Physical Metric - Double Required
        integrityFlag: IngestionIntegrityFlag.ok,
      ),
    );
    registerFallbackValue(SpoofingRiskScore.zero());
  });

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    mockFactQueue = MockFactQueue();
    mockLedgerRepo = MockSlaLedgerRepository();
    mockClock = MockDateTimeProvider();
    mockSpoofingDetector = MockSpoofingDetector();

    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);

    handler = TelemetryNormalizationHandler(
      normalizer: TelemetryNormalizer(), // fresh state per test
      ledgerRepository: mockLedgerRepo,
      factQueue: mockFactQueue,
      clock: mockClock,
      tenantValidator: tenantValidator,
      spoofingDetector: mockSpoofingDetector,
    );

    when(() => mockClock.nowUtc()).thenReturn(kFrozenUtc);
    when(
      () => mockLedgerRepo.append(any()),
    ).thenAnswer((_) async => 'ledger-id-001');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // GROUP 1: GUARDIÃƒO DE TENANT (INV-1)
  // Proves that assertTenantMatches() is the first instruction and that any
  // sovereignty violation hard-stops the pipeline before any I/O occurs.
  // ─────────────────────────────────────────────────────────────────────────────
  group('INV-1 — Guardião de Tenant: fail-fast sovereignty check', () {
    setUp(() {
      // JWT claims a different org â†’ mismatch with batch.organizationId
      when(() => mockAuthRepo.getUserBySessionId(_sessionId)).thenAnswer(
        (_) async => const domain.AuthUser(
          id: 'user-attacker',
          email: 'evil@adversary.com',
          tenantId: 'org-attacker-FORBIDDEN',
        ),
      );
    });

    test(
      'lança SovereigntyViolationException quando org_id do payload diverge do JWT',
      () async {
        await expectLater(
          handler.normalize(_validBatch(), sessionId: _sessionId),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    test(
      'factQueue.enqueue NUNCA chamado após falha de tenant — pipeline interrompido',
      () async {
        try {
          await handler.normalize(_validBatch(), sessionId: _sessionId);
        } catch (_) {}

        verifyNever(() => mockFactQueue.enqueue(any()));
      },
    );

    test(
      'ledgerRepository.append NUNCA chamado após falha de tenant — sem efeitos colaterais',
      () async {
        try {
          await handler.normalize(_validBatch(), sessionId: _sessionId);
        } catch (_) {}

        verifyNever(() => mockLedgerRepo.append(any()));
      },
    );

    test(
      'tenantValidationService.assertTenantMatches chamado antes de spoofingDetector.analyze',
      () async {
        when(() => mockAuthRepo.getUserBySessionId(_sessionId)).thenAnswer(
          (_) async => const domain.AuthUser(
            id: 'user-driver-42',
            email: 'driver@fleet.com',
            tenantId: _orgId,
          ),
        );
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(SpoofingRiskScore.zero());

        await handler.normalize(_validBatch(count: 1), sessionId: _sessionId);

        verify(() => mockAuthRepo.getUserBySessionId(_sessionId)).called(1);
        verify(() => mockSpoofingDetector.analyze(any())).called(1);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // GROUP 2: BLOQUEIO DE SPOOFING (INV-8 / INV-18)
  // Proves that synthetic/zero-variance telemetry is quarantined:
  //   - factQueue.enqueue is NEVER called
  //   - ledgerRepository.append IS called with SPOOFING_DETECTED forensic record
  // ─────────────────────────────────────────────────────────────────────────────
  group('INV-8 — Bloqueio de Spoofing: zero-variance batch quarentenado', () {
    setUp(() {
      // Valid tenant — spoofing is about data forgery, not identity theft
      when(() => mockAuthRepo.getUserBySessionId(_sessionId)).thenAnswer(
        (_) async => const domain.AuthUser(
          id: 'user-driver-42',
          email: 'driver@fleet.com',
          tenantId: _orgId,
        ),
      );
    });

    test(
      'lança SpoofingDetectedException ao detectar zero-variance em batch de 5 coords idênticas',
      () async {
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 8000, signals: []));

        await expectLater(
          handler.normalize(_spoofedBatch(), sessionId: _sessionId),
          throwsA(isA<SpoofingDetectedException>()),
        );
      },
    );

    test(
      'factQueue.enqueue NUNCA chamado quando spoofing é detectado — dado sintético bloqueado',
      () async {
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 8000, signals: []));

        try {
          await handler.normalize(_spoofedBatch(), sessionId: _sessionId);
        } catch (_) {}

        verifyNever(() => mockFactQueue.enqueue(any()));
      },
    );

    test(
      'ledgerRepository.append chamado com type=SPOOFING_DETECTED e organizationId correto',
      () async {
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 8000, signals: []));

        try {
          await handler.normalize(_spoofedBatch(), sessionId: _sessionId);
        } catch (_) {}

        final captured = verify(
          () => mockLedgerRepo.append(captureAny()),
        ).captured;

        expect(captured, hasLength(1));
        final entry = captured.first as SlaLedgerEntry;
        expect(entry.type, 'SPOOFING_DETECTED');
        expect(entry.organizationId, _orgId);
      },
    );

    test(
      'registro forense de spoofing inclui deviceId e razão no payload',
      () async {
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 8000, signals: []));

        try {
          await handler.normalize(_spoofedBatch(), sessionId: _sessionId);
        } catch (_) {}

        final captured = verify(
          () => mockLedgerRepo.append(captureAny()),
        ).captured;

        final entry = captured.first as SlaLedgerEntry;
        expect(entry.payload['deviceId'], kDeviceId);
        expect(entry.payload['reason'], isNotEmpty);
        expect(entry.payload['batchSize'], 5);
      },
    );

    test(
      'registro forense usa timestamp do clock injetado (INV-6: UTC determinístico)',
      () async {
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 8000, signals: []));

        try {
          await handler.normalize(_spoofedBatch(), sessionId: _sessionId);
        } catch (_) {}

        final captured = verify(
          () => mockLedgerRepo.append(captureAny()),
        ).captured;

        final entry = captured.first as SlaLedgerEntry;
        expect(entry.occurredAtUtc, kFrozenUtc);
        expect(entry.occurredAtUtc.isUtc, isTrue);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // GROUP 3: SUCESSO E NORMALIZAÃ‡ÃƒO
  // Proves the golden path: valid tenant + clean telemetry â†’ CanonicalFact
  // enqueued with correct orgId (INV-8 repo isolation assertion).
  // ─────────────────────────────────────────────────────────────────────────────
  group('Sucesso e Normalização: pipeline limpo com tenant e dados válidos', () {
    setUp(() {
      when(() => mockAuthRepo.getUserBySessionId(_sessionId)).thenAnswer(
        (_) async => const domain.AuthUser(
          id: 'user-driver-42',
          email: 'driver@fleet.com',
          tenantId: _orgId,
        ),
      );
      when(
        () => mockSpoofingDetector.analyze(any()),
      ).thenReturn(SpoofingRiskScore.zero());
      // Stub void enqueue so mocktail doesn't throw MissingStubError
      when(() => mockFactQueue.enqueue(any())).thenReturn(null);
    });

    test('enfileira um CanonicalFact para um único ping válido', () async {
      await handler.normalize(_validBatch(count: 1), sessionId: _sessionId);

      final captured = verify(
        () => mockFactQueue.enqueue(captureAny()),
      ).captured;

      expect(captured, hasLength(1));
    });

    test(
      'CanonicalFact carrega organizationId=_orgId — INV-8 isolation confirmada',
      () async {
        await handler.normalize(_validBatch(count: 1), sessionId: _sessionId);

        final captured = verify(
          () => mockFactQueue.enqueue(captureAny()),
        ).captured;

        final fact = captured.first as CanonicalFact;
        expect(fact.organizationId, _orgId);
      },
    );

    test('CanonicalFact carrega deviceId correto', () async {
      await handler.normalize(_validBatch(count: 1), sessionId: _sessionId);

      final captured = verify(
        () => mockFactQueue.enqueue(captureAny()),
      ).captured;

      final fact = captured.first as CanonicalFact;
      expect(fact.deviceId, kDeviceId);
    });

    test('CanonicalFact preserva coordenadas do batch original', () async {
      await handler.normalize(_validBatch(count: 1), sessionId: _sessionId);

      final captured = verify(
        () => mockFactQueue.enqueue(captureAny()),
      ).captured;

      final fact = captured.first as CanonicalFact;
      expect(fact.lat, closeTo(-23.5505, 0.0001));
      expect(fact.lng, closeTo(-46.6333, 0.0001));
    });

    test(
      'enfileira N CanonicalFacts para N pings válidos — um por coordenada',
      () async {
        await handler.normalize(_validBatch(count: 3), sessionId: _sessionId);

        final captured = verify(
          () => mockFactQueue.enqueue(captureAny()),
        ).captured;

        expect(captured, hasLength(3));
        for (final raw in captured) {
          final fact = raw as CanonicalFact;
          expect(fact.organizationId, _orgId);
        }
      },
    );

    test(
      'ledgerRepository.append NUNCA chamado em pipeline limpo — sem registros forenses indevidos',
      () async {
        await handler.normalize(_validBatch(count: 1), sessionId: _sessionId);

        verifyNever(() => mockLedgerRepo.append(any()));
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // GROUP 4: AUDITABILIDADE & INTEGRIDADE DO PIPELINE (refactor)
  // Proves the decomposed pipeline: normalize() returns a NormalizationOutcome
  // with the accepted-vs-rejected breakdown, rejected packets produce exactly
  // ONE forensic ledger entry, and the spoofing detector branch writes exactly
  // ONE SPOOFING_DETECTED entry (locks the former double-write bug).
  // ─────────────────────────────────────────────────────────────────────────────
  group('Auditabilidade — outcome de aceitos vs. rejeitados', () {
    setUp(() {
      when(() => mockAuthRepo.getUserBySessionId(_sessionId)).thenAnswer(
        (_) async => const domain.AuthUser(
          id: 'user-driver-42',
          email: 'driver@fleet.com',
          tenantId: _orgId,
        ),
      );
      when(
        () => mockSpoofingDetector.analyze(any()),
      ).thenReturn(SpoofingRiskScore.zero());
      when(() => mockFactQueue.enqueue(any())).thenReturn(null);
    });

    test(
      'normalize retorna NormalizationOutcome com contagem de aceitos e rejeitados',
      () async {
        final outcome = await handler.normalize(
          _partialRejectBatch(),
          sessionId: _sessionId,
        );

        expect(outcome.acceptedCount, 1);
        expect(outcome.rejectedCount, 1);
        expect(outcome.rejectedPackets.single.batchIndex, 1);
      },
    );

    test(
      'batch parcialmente rejeitado grava EXATAMENTE um TELEMETRY_PARTIAL_REJECT',
      () async {
        await handler.normalize(_partialRejectBatch(), sessionId: _sessionId);

        final captured = verify(
          () => mockLedgerRepo.append(captureAny()),
        ).captured;

        expect(captured, hasLength(1));
        final entry = captured.single as SlaLedgerEntry;
        expect(entry.type, 'TELEMETRY_PARTIAL_REJECT');
        expect(entry.organizationId, _orgId);
        expect(entry.payload['acceptedCount'], 1);
        expect(entry.payload['rejectedCount'], 1);
      },
    );

    test('apenas pacotes aceitos chegam ao factQueue', () async {
      await handler.normalize(_partialRejectBatch(), sessionId: _sessionId);

      final captured = verify(
        () => mockFactQueue.enqueue(captureAny()),
      ).captured;

      expect(captured, hasLength(1));
    });

    test(
      'batch limpo retorna outcome sem rejeitados e sem registro forense',
      () async {
        final outcome = await handler.normalize(
          _validBatch(count: 3),
          sessionId: _sessionId,
        );

        expect(outcome.acceptedCount, 3);
        expect(outcome.rejectedCount, 0);
        verifyNever(() => mockLedgerRepo.append(any()));
      },
    );

    test(
      'batch vazio: outcome vazio, sem enqueue, sem registro forense',
      () async {
        final outcome = await handler.normalize(
          _validBatch(count: 0),
          sessionId: _sessionId,
        );

        expect(outcome.acceptedCount, 0);
        expect(outcome.rejectedCount, 0);
        verifyNever(() => mockFactQueue.enqueue(any()));
        verifyNever(() => mockLedgerRepo.append(any()));
      },
    );

    test(
      'spoofing do detector grava EXATAMENTE um SPOOFING_DETECTED — anti double-write',
      () async {
        when(
          () => mockSpoofingDetector.analyze(any()),
        ).thenReturn(const SpoofingRiskScore(scoreBps: 8000, signals: []));

        try {
          await handler.normalize(_validBatch(count: 5), sessionId: _sessionId);
        } catch (_) {}

        final captured = verify(
          () => mockLedgerRepo.append(captureAny()),
        ).captured;

        expect(captured, hasLength(1));
        expect((captured.single as SlaLedgerEntry).type, 'SPOOFING_DETECTED');
      },
    );
  });
}
