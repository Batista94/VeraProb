import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/execution/execution_domain_exception.dart';
import 'package:veraprob/domain/execution/execution_event.dart';

void main() {
  ExecutionEvent makeEvent({
    String requestId = 'req-001',
    String decisionId = 'dec-001',
    String? idempotencyKey,
    String executorId = 'worker-1',
    DateTime? startedAt,
    DateTime? completedAt,
    ExecutionOutcome status = ExecutionOutcome.success,
    String? errorMessage,
    Map<String, dynamic>? outputSnapshot,
    int schemaVersion = 1,
    Map<String, dynamic>? metadata,
  }) {
    final start = startedAt ?? DateTime.utc(2026, 4, 15, 10, 0, 0);
    final end = completedAt ?? start.add(const Duration(seconds: 5));
    final idemKey = idempotencyKey ?? ('a' * 64);
    return ExecutionEvent(
      requestId: requestId,
      decisionId: decisionId,
      idempotencyKey: idemKey,
      executorId: executorId,
      startedAt: start,
      completedAt: end,
      status: status,
      errorMessage: errorMessage,
      outputSnapshot: outputSnapshot ?? {},
      schemaVersion: schemaVersion,
      metadata: metadata ?? {},
    );
  }

  group('Grupo 1 — Identidade e Versão', () {
    test('armazena requestId, decisionId, idempotencyKey, executorId', () {
      final event = makeEvent(
        requestId: 'req-abc',
        decisionId: 'dec-xyz',
        idempotencyKey: 'b' * 64,
        executorId: 'worker-5',
      );

      expect(event.requestId, equals('req-abc'));
      expect(event.decisionId, equals('dec-xyz'));
      expect(event.idempotencyKey, equals('b' * 64));
      expect(event.executorId, equals('worker-5'));
    });

    test('schemaVersion default é 1', () {
      final event = makeEvent();
      expect(event.schemaVersion, equals(1));
    });

    test('metadata default é Map vazio', () {
      final event = makeEvent();
      expect(event.metadata, equals({}));
    });

    test('toJson() contém schema_version', () {
      final event = makeEvent(schemaVersion: 2);
      final json = event.toJson();
      expect(json['schema_version'], equals(2));
    });

    test('CORRELAÇÃO: event.decisionId vincula com AuthorizationDecision', () {
      const decisionId = 'dec-abc';
      final decision = AuthorizationDecision(
        decisionId: decisionId,
        actorId: const ActorId('user-1'),
        roleId: const RoleId('operator'),
        actionType: const OperationalActionType('test_action'),
        targetRef: const TargetRef('test', 'target-1'),
        policyVersion: 'v1',
        result: DecisionResult.approved,
        occurredAt: DateTime.utc(2026, 4, 15, 10, 0, 0),
        contextSnapshot: {},
      );

      final event = makeEvent(decisionId: decisionId);

      expect(event.toJson()['decision_id'], equals(decision.decisionId));
    });
  });

  group('Grupo 2 — Física e Tempo', () {
    test('duration retorna completedAt.difference(startedAt)', () {
      final start = DateTime.utc(2026, 4, 15, 10, 0, 0);
      final end = DateTime.utc(2026, 4, 15, 10, 0, 5);
      final event = makeEvent(startedAt: start, completedAt: end);

      expect(event.duration, equals(const Duration(seconds: 5)));
    });

    test('startedAt == completedAt → duration == Duration.zero', () {
      final instant = DateTime.utc(2026, 4, 15, 10, 0, 0);
      final event = makeEvent(startedAt: instant, completedAt: instant);

      expect(event.duration, equals(Duration.zero));
    });

    test('CRONOLOGIA: completedAt antes de startedAt lança exceção', () {
      final start = DateTime.utc(2026, 4, 15, 10, 0, 0);
      final end = DateTime.utc(2026, 4, 15, 9, 59, 59);

      expect(
        () => makeEvent(startedAt: start, completedAt: end),
        throwsA(
          isA<ExecutionDomainException>()
              .having((e) => e.message, 'message', contains('INV-25'))
              .having(
                (e) => e.message,
                'message',
                contains('temporal integrity'),
              ),
        ),
      );
    });

    test('toJson() contém duration_ms correto', () {
      final start = DateTime.utc(2026, 4, 15, 10, 0, 0);
      final end = DateTime.utc(2026, 4, 15, 10, 0, 5);
      final event = makeEvent(startedAt: start, completedAt: end);

      expect(event.toJson()['duration_ms'], equals(5000));
    });

    test('toJson() serializa started_at e completed_at como ISO8601', () {
      final start = DateTime.utc(2026, 4, 15, 10, 0, 0);
      final end = DateTime.utc(2026, 4, 15, 10, 0, 5);
      final event = makeEvent(startedAt: start, completedAt: end);
      final json = event.toJson();

      expect(json['started_at'], equals('2026-04-15T10:00:00.000Z'));
      expect(json['completed_at'], equals('2026-04-15T10:00:05.000Z'));
    });
  });

  group('Grupo 3 — Explicabilidade de Falha', () {
    test('status=success com errorMessage=null é válido', () {
      expect(
        () => makeEvent(status: ExecutionOutcome.success, errorMessage: null),
        returnsNormally,
      );
    });

    test('status=failed com errorMessage não-vazio é válido', () {
      expect(
        () => makeEvent(
          status: ExecutionOutcome.failed,
          errorMessage: 'Connection timeout',
        ),
        returnsNormally,
      );
    });

    test(
      'EXPLICABILIDADE: status=failed com errorMessage=null lança exceção',
      () {
        expect(
          () => makeEvent(status: ExecutionOutcome.failed, errorMessage: null),
          throwsA(
            isA<ExecutionDomainException>()
                .having((e) => e.message, 'message', contains('INV-25'))
                .having((e) => e.message, 'message', contains('errorMessage')),
          ),
        );
      },
    );

    test(
      'EXPLICABILIDADE: status=failed com errorMessage vazio lança exceção',
      () {
        expect(
          () => makeEvent(status: ExecutionOutcome.failed, errorMessage: ''),
          throwsA(isA<ExecutionDomainException>()),
        );
      },
    );

    test('toJson() serializa status como string', () {
      final success = makeEvent(status: ExecutionOutcome.success);
      final failed = makeEvent(
        status: ExecutionOutcome.failed,
        errorMessage: 'Error',
      );
      final partial = makeEvent(status: ExecutionOutcome.partial);

      expect(success.toJson()['status'], equals('success'));
      expect(failed.toJson()['status'], equals('failed'));
      expect(partial.toJson()['status'], equals('partial'));
    });
  });

  group('Grupo 4 — Serialização Forense', () {
    test('toJson() contém todas as 12 chaves obrigatórias', () {
      final event = makeEvent();
      final json = event.toJson();

      expect(json, hasLength(12));
      expect(json.containsKey('request_id'), isTrue);
      expect(json.containsKey('decision_id'), isTrue);
      expect(json.containsKey('idempotency_key'), isTrue);
      expect(json.containsKey('executor_id'), isTrue);
      expect(json.containsKey('started_at'), isTrue);
      expect(json.containsKey('completed_at'), isTrue);
      expect(json.containsKey('duration_ms'), isTrue);
      expect(json.containsKey('status'), isTrue);
      expect(json.containsKey('error_message'), isTrue);
      expect(json.containsKey('output_snapshot'), isTrue);
      expect(json.containsKey('schema_version'), isTrue);
      expect(json.containsKey('metadata'), isTrue);
    });

    test('outputSnapshot vazio aparece como {}', () {
      final event = makeEvent(outputSnapshot: {});
      expect(event.toJson()['output_snapshot'], equals({}));
    });

    test('metadata vazio aparece como {}', () {
      final event = makeEvent(metadata: {});
      expect(event.toJson()['metadata'], equals({}));
    });

    test('DEEP COPY (outputSnapshot): mutação não corrompe JSON', () {
      final mutableSnapshot = {
        'result': 'ok',
        'nested': {'value': 42},
      };
      final event = makeEvent(outputSnapshot: mutableSnapshot);

      mutableSnapshot['result'] = 'TAMPERED';
      (mutableSnapshot['nested'] as Map)['value'] = 999;

      final json = event.toJson();
      expect(json['output_snapshot']['result'], equals('ok'));
      expect(json['output_snapshot']['nested']['value'], equals(42));
    });

    test('DEEP COPY (metadata): mutação não corrompe JSON', () {
      final mutableMetadata = {
        'source': 'worker-1',
        'config': {'timeout': 30},
      };
      final event = makeEvent(metadata: mutableMetadata);

      mutableMetadata['source'] = 'HACKED';
      (mutableMetadata['config'] as Map)['timeout'] = 9999;

      final json = event.toJson();
      expect(json['metadata']['source'], equals('worker-1'));
      expect(json['metadata']['config']['timeout'], equals(30));
    });
  });

  group('Grupo 5 — Imutabilidade', () {
    test('Equatable: dois eventos idênticos são iguais', () {
      final e1 = makeEvent();
      final e2 = makeEvent();

      expect(e1, equals(e2));
      expect(e1.hashCode, equals(e2.hashCode));
    });

    test('diferença em schemaVersion quebra igualdade', () {
      final e1 = makeEvent(schemaVersion: 1);
      final e2 = makeEvent(schemaVersion: 2);

      expect(e1, isNot(equals(e2)));
    });

    test('diferença em metadata quebra igualdade', () {
      final e1 = makeEvent(metadata: {'key': 'value1'});
      final e2 = makeEvent(metadata: {'key': 'value2'});

      expect(e1, isNot(equals(e2)));
    });

    test(
      'ISOLAMENTO: mutação de outputSnapshot não afeta JSONs subsequentes',
      () {
        final mutableSnapshot = {'data': 'original'};
        final event = makeEvent(outputSnapshot: mutableSnapshot);

        final json1 = event.toJson();
        mutableSnapshot['data'] = 'MUTATED';
        final json2 = event.toJson();

        expect(json1['output_snapshot']['data'], equals('original'));
        expect(json2['output_snapshot']['data'], equals('original'));
      },
    );
  });
}
