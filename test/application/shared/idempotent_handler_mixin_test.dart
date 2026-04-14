import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/idempotent_handler_mixin.dart';
import 'package:veraprob/domain/shared/idempotency_key.dart';
import 'package:veraprob/domain/shared/idempotency_registration_result.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import '../../mocks/fake_date_time_provider.dart';

// ─────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────

class _Handler with IdempotentHandlerMixin {}

class _MockStore extends Mock implements IIdempotencyStore {}

class _FakeIdempotencyKey extends Fake implements IdempotencyKey {}

/// Minimal domain entity used as the generic type [T] throughout tests.
class _Entity {
  const _Entity(this.id, this.version);
  final String id;
  final int version;
}

// ─────────────────────────────────────────────────────────────
// Shared fixtures
// ─────────────────────────────────────────────────────────────

const _keyId = 'idem-key-1';
const _userId = 'user-1';
const _commandPath = 'create_thing';
const _orgId = 'org-1';
final _fixedNow = DateTime.utc(2026, 4, 14, 10, 0);

IdempotencyKey _processingKey() => IdempotencyKey.processing(
  id: _keyId,
  userId: _userId,
  commandPath: _commandPath,
  organizationId: _orgId,
  nowUtc: _fixedNow,
);

IdempotencyKey _completedKey({Map<String, dynamic>? body}) => IdempotencyKey(
  id: _keyId,
  userId: _userId,
  commandPath: _commandPath,
  organizationId: _orgId,
  status: 'completed',
  responseCode: 200,
  responseBody: body ?? {'id': 'entity-1', 'version': 1},
  createdAtUtc: _fixedNow,
  completedAtUtc: _fixedNow.add(const Duration(seconds: 5)),
);

/// Completed key with a null body — simulates a pre-migration / corrupt row.
IdempotencyKey _completedKeyNullBody() => IdempotencyKey(
  id: _keyId,
  userId: _userId,
  commandPath: _commandPath,
  organizationId: _orgId,
  status: 'completed',
  responseCode: 200,
  responseBody: null,
  createdAtUtc: _fixedNow,
);

IdempotencyKey _errorKey({int code = 400, Map<String, dynamic>? body}) =>
    IdempotencyKey(
      id: _keyId,
      userId: _userId,
      commandPath: _commandPath,
      organizationId: _orgId,
      status: 'error',
      responseCode: code,
      responseBody: body,
      createdAtUtc: _fixedNow,
    );

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

void main() {
  late _Handler handler;
  late _MockStore store;
  late FakeDateTimeProvider clock;

  setUpAll(() {
    registerFallbackValue(_FakeIdempotencyKey());
  });

  setUp(() {
    handler = _Handler();
    store = _MockStore();
    clock = FakeDateTimeProvider(_fixedNow);

    // Default catch-all stubs — overridden per-test when stricter matching needed.
    when(
      () => store.markCompleted(
        id: any(named: 'id'),
        userId: any(named: 'userId'),
        responseCode: any(named: 'responseCode'),
        responseBody: any(named: 'responseBody'),
        nowUtc: any(named: 'nowUtc'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => store.markError(
        id: any(named: 'id'),
        userId: any(named: 'userId'),
        responseCode: any(named: 'responseCode'),
        nowUtc: any(named: 'nowUtc'),
        responseBody: any(named: 'responseBody'),
      ),
    ).thenAnswer((_) async {});
  });

  /// Convenience wrapper: only pass what varies.
  Future<_Entity> execute({
    required Future<_Entity> Function() businessLogic,
    Future<_Entity?> Function()? recoverIfAlreadyCompleted,
    Future<_Entity?> Function(Map<String, dynamic>)? reloadEntity,
  }) {
    return handler.executeWithIdempotency<_Entity>(
      idempotencyStore: store,
      idempotencyKey: _keyId,
      userId: _userId,
      commandPath: _commandPath,
      organizationId: _orgId,
      businessLogic: businessLogic,
      toIdempotencyDto: (e) => {'id': e.id, 'version': e.version},
      reloadEntity:
          reloadEntity ??
          (body) async =>
              _Entity(body['id'] as String, (body['version'] as num).toInt()),
      recoverIfAlreadyCompleted: recoverIfAlreadyCompleted,
      clock: clock,
    );
  }

  // ─────────────────────────────────────────────────────────
  // Group A — lock acquired (fresh execution)
  // ─────────────────────────────────────────────────────────

  group('ACQUIRED=true — business logic branch', () {
    setUp(() {
      when(
        () => store.tryRegister(
          any(),
          staleThresholdMinutes: any(named: 'staleThresholdMinutes'),
        ),
      ).thenAnswer(
        (_) async => IdempotencyRegistrationResult(
          acquired: true,
          key: _processingKey(),
        ),
      );
    });

    // ── Cenário 1: Sucesso puro ──────────────────────────────
    test(
      'Cenário 1 — sucesso puro: markCompleted(200) chamado, entity retornada',
      () async {
        const entity = _Entity('entity-1', 1);

        final result = await execute(businessLogic: () async => entity);

        expect(result, same(entity));
        verify(
          () => store.markCompleted(
            id: _keyId,
            userId: _userId,
            responseCode: 200,
            responseBody: any(named: 'responseBody'),
            nowUtc: any(named: 'nowUtc'),
          ),
        ).called(1);
        verifyNever(
          () => store.markError(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            nowUtc: any(named: 'nowUtc'),
            responseBody: any(named: 'responseBody'),
          ),
        );
      },
    );

    // ── Cenário 2: Dual-Write Self-Heal ──────────────────────
    test(
      'Cenário 2 — Self-Heal: DomainException + recovery retorna entity → markCompleted(200)',
      () async {
        const recovered = _Entity('entity-1', 1);

        final result = await execute(
          businessLogic: () async =>
              throw const DomainException('DB unique violation'),
          recoverIfAlreadyCompleted: () async => recovered,
        );

        expect(result, same(recovered));
        verify(
          () => store.markCompleted(
            id: _keyId,
            userId: _userId,
            responseCode: 200,
            responseBody: any(named: 'responseBody'),
            nowUtc: any(named: 'nowUtc'),
          ),
        ).called(1);
        verifyNever(
          () => store.markError(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            nowUtc: any(named: 'nowUtc'),
            responseBody: any(named: 'responseBody'),
          ),
        );
      },
    );

    // ── Cenário 2b: Self-Heal falha (recovery retorna null) ──
    test(
      'Cenário 2b — Self-Heal falha: DomainException + recovery retorna null → markError(400) + rethrow',
      () async {
        const domainErr = DomainException('business rule violated');

        await expectLater(
          execute(
            businessLogic: () async => throw domainErr,
            recoverIfAlreadyCompleted: () async => null,
          ),
          throwsA(isA<DomainException>()),
        );

        verify(
          () => store.markError(
            id: _keyId,
            userId: _userId,
            responseCode: 400,
            nowUtc: any(named: 'nowUtc'),
            responseBody: {'errorMessage': domainErr.message},
          ),
        ).called(1);
        verifyNever(
          () => store.markCompleted(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            responseBody: any(named: 'responseBody'),
            nowUtc: any(named: 'nowUtc'),
          ),
        );
      },
    );

    // ── Cenário 2c: DomainException sem callback ─────────────
    test(
      'Cenário 2c — DomainException sem recovery callback → markError(400) com errorMessage',
      () async {
        const domainErr = DomainException('missing required field');

        await expectLater(
          execute(businessLogic: () async => throw domainErr),
          throwsA(isA<DomainException>()),
        );

        verify(
          () => store.markError(
            id: _keyId,
            userId: _userId,
            responseCode: 400,
            nowUtc: any(named: 'nowUtc'),
            responseBody: {'errorMessage': domainErr.message},
          ),
        ).called(1);
        verifyNever(
          () => store.markCompleted(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            responseBody: any(named: 'responseBody'),
            nowUtc: any(named: 'nowUtc'),
          ),
        );
      },
    );

    // ── Cenário 3: Conflict Guard ─────────────────────────────
    test(
      'Cenário 3 — Conflict Guard: ConflictException → markError(409) SEM responseBody, rethrow',
      () async {
        const conflict = ConflictException.staleVersion(
          resourceType: 'thing',
          resourceId: 'entity-1',
          clientVersion: 1,
          currentVersion: 2,
        );

        await expectLater(
          execute(businessLogic: () async => throw conflict),
          throwsA(isA<ConflictException>()),
        );

        // 409 is the recorded code — NO cached message (INV-33 Conflict Guard)
        verify(
          () => store.markError(
            id: _keyId,
            userId: _userId,
            responseCode: 409,
            nowUtc: any(named: 'nowUtc'),
          ),
        ).called(1);
        verifyNever(
          () => store.markCompleted(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            responseBody: any(named: 'responseBody'),
            nowUtc: any(named: 'nowUtc'),
          ),
        );
      },
    );

    // ── Cenário 4: Erro de infraestrutura (genérico) ─────────
    test(
      'Cenário 4 — Erro de infraestrutura: markError(500) + rethrow',
      () async {
        await expectLater(
          execute(
            businessLogic: () async => throw StateError('DB connection lost'),
          ),
          throwsStateError,
        );

        verify(
          () => store.markError(
            id: _keyId,
            userId: _userId,
            responseCode: 500,
            nowUtc: any(named: 'nowUtc'),
          ),
        ).called(1);
        verifyNever(
          () => store.markCompleted(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            responseBody: any(named: 'responseBody'),
            nowUtc: any(named: 'nowUtc'),
          ),
        );
      },
    );
  });

  // ─────────────────────────────────────────────────────────
  // Group B — cache replay (acquired = false)
  // ─────────────────────────────────────────────────────────

  group('ACQUIRED=false — cache replay branch', () {
    // ── Cenário 5: Cache hit completed ───────────────────────
    test(
      'Cenário 5 — Cache hit completed: businessLogic NUNCA chamado, entity recarregada',
      () async {
        when(
          () => store.tryRegister(
            any(),
            staleThresholdMinutes: any(named: 'staleThresholdMinutes'),
          ),
        ).thenAnswer(
          (_) async => IdempotencyRegistrationResult(
            acquired: false,
            key: _completedKey(),
          ),
        );

        var businessCalled = false;
        final result = await execute(
          businessLogic: () async {
            businessCalled = true;
            return const _Entity('entity-1', 1);
          },
        );

        expect(
          businessCalled,
          isFalse,
          reason: 'businessLogic não deve ser chamado em cache hit',
        );
        expect(result.id, 'entity-1');
        expect(result.version, 1);
        verifyNever(
          () => store.markCompleted(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            responseBody: any(named: 'responseBody'),
            nowUtc: any(named: 'nowUtc'),
          ),
        );
        verifyNever(
          () => store.markError(
            id: any(named: 'id'),
            userId: any(named: 'userId'),
            responseCode: any(named: 'responseCode'),
            nowUtc: any(named: 'nowUtc'),
            responseBody: any(named: 'responseBody'),
          ),
        );
      },
    );

    // ── Cenário 5b: Cache hit completed mas entity deletada ──
    test(
      'Cenário 5b — Cache hit completed + entity deletada → ConflictException.deleted',
      () async {
        when(
          () => store.tryRegister(
            any(),
            staleThresholdMinutes: any(named: 'staleThresholdMinutes'),
          ),
        ).thenAnswer(
          (_) async => IdempotencyRegistrationResult(
            acquired: false,
            key: _completedKey(),
          ),
        );

        await expectLater(
          execute(
            businessLogic: () async => const _Entity('entity-1', 1),
            reloadEntity: (_) async => null, // hard-deleted
          ),
          throwsA(
            isA<ConflictException>().having(
              (e) => e.isDeleted,
              'isDeleted',
              isTrue,
            ),
          ),
        );
      },
    );

    // ── Cenário 5c: Cache hit completed + responseBody nulo ──
    test(
      'Cenário 5c — Cache hit completed com responseBody nulo → StateError (guardrail forense)',
      () async {
        when(
          () => store.tryRegister(
            any(),
            staleThresholdMinutes: any(named: 'staleThresholdMinutes'),
          ),
        ).thenAnswer(
          (_) async => IdempotencyRegistrationResult(
            acquired: false,
            key: _completedKeyNullBody(),
          ),
        );

        await expectLater(
          execute(businessLogic: () async => const _Entity('entity-1', 1)),
          throwsStateError,
        );
      },
    );

    // ── Cenário 6: Cache hit error 4xx ───────────────────────
    test(
      'Cenário 6 — Cache hit error 4xx: DomainException replay com errorMessage do cache',
      () async {
        when(
          () => store.tryRegister(
            any(),
            staleThresholdMinutes: any(named: 'staleThresholdMinutes'),
          ),
        ).thenAnswer(
          (_) async => IdempotencyRegistrationResult(
            acquired: false,
            key: _errorKey(
              code: 400,
              body: {'errorMessage': 'contrato já encerrado'},
            ),
          ),
        );

        await expectLater(
          execute(businessLogic: () async => const _Entity('entity-1', 1)),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              'contrato já encerrado',
            ),
          ),
        );
      },
    );

    // ── Cenário 7: Cache hit error 5xx ───────────────────────
    test(
      'Cenário 7 — Cache hit error 5xx: IdempotencyProcessingException (sinal de retry)',
      () async {
        when(
          () => store.tryRegister(
            any(),
            staleThresholdMinutes: any(named: 'staleThresholdMinutes'),
          ),
        ).thenAnswer(
          (_) async => IdempotencyRegistrationResult(
            acquired: false,
            key: _errorKey(code: 500),
          ),
        );

        await expectLater(
          execute(businessLogic: () async => const _Entity('entity-1', 1)),
          throwsA(isA<IdempotencyProcessingException>()),
        );
      },
    );

    // ── Cenário 8: Still processing ──────────────────────────
    test(
      'Cenário 8 — Still processing: IdempotencyProcessingException (outra thread está processando)',
      () async {
        when(
          () => store.tryRegister(
            any(),
            staleThresholdMinutes: any(named: 'staleThresholdMinutes'),
          ),
        ).thenAnswer(
          (_) async => IdempotencyRegistrationResult(
            acquired: false,
            key: _processingKey(),
          ),
        );

        await expectLater(
          execute(businessLogic: () async => const _Entity('entity-1', 1)),
          throwsA(isA<IdempotencyProcessingException>()),
        );
      },
    );
  });
}
