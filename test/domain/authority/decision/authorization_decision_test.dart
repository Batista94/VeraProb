import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/decision/authorization_obligation.dart';

void main() {
  group('AuthorizationDecision — INV-7 Forensic Audit Trail', () {
    // Fixtures with real IDs as required by INV-7
    const actorId = ActorId('user-789');
    const roleId = RoleId('operator');
    const actionType = OperationalActionType('action:delete_contract');
    const targetRef = TargetRef('contract', 'contract-456');
    const policyVersion = 'policy-v2.1';
    final occurredAt = DateTime.utc(2026, 4, 15, 10, 30, 0);
    final contextSnapshot = {
      'actor_id': 'user-789',
      'role_id': 'operator',
      'organization_id': 'org-123',
      'scopes': ['read', 'write'],
      'captured_at': '2026-04-15T10:30:00.000Z',
    };

    AuthorizationDecision makeDecision({
      String decisionId = 'decision-001',
      required DecisionResult result,
      String? reason,
      List<AuthorizationObligation> obligations = const [],
      Map<String, dynamic>? contextSnapshot,
    }) {
      final snapshot =
          contextSnapshot ??
          {
            'actor_id': 'user-789',
            'role_id': 'operator',
            'organization_id': 'org-123',
            'scopes': ['read', 'write'],
            'captured_at': '2026-04-15T10:30:00.000Z',
          };
      return AuthorizationDecision(
        decisionId: decisionId,
        actorId: actorId,
        roleId: roleId,
        actionType: actionType,
        targetRef: targetRef,
        policyVersion: policyVersion,
        result: result,
        reason: reason,
        occurredAt: occurredAt,
        contextSnapshot: snapshot,
        obligations: obligations,
      );
    }

    group('1. Integridade do Rastro', () {
      test(
        'armazena actorId, orgId via contextSnapshot, actionType, targetRef, result e reason',
        () {
          final decision = makeDecision(
            result: DecisionResult.denied,
            reason: 'Missing required scope: admin',
          );

          expect(decision.actorId.value, equals('user-789'));
          expect(
            decision.contextSnapshot['organization_id'],
            equals('org-123'),
          );
          expect(decision.actionType.key, equals('action:delete_contract'));
          expect(
            decision.targetRef.urn,
            equals('urn:veraprob:contract:contract-456'),
          );
          expect(decision.result, equals(DecisionResult.denied));
          expect(decision.reason, equals('Missing required scope: admin'));
        },
      );

      test('isApproved retorna true apenas para DecisionResult.approved', () {
        final approved = makeDecision(result: DecisionResult.approved);
        final denied = makeDecision(
          result: DecisionResult.denied,
          reason: 'Missing required scope: admin',
        );

        expect(approved.isApproved, isTrue);
        expect(denied.isApproved, isFalse);
      });
    });

    group('6. Explicabilidade', () {
      test('denied sem reason lança AssertionError', () {
        expect(
          () => makeDecision(result: DecisionResult.denied, reason: null),
          throwsA(isA<AssertionError>()),
        );
      });

      test('denied com reason vazio lança AssertionError', () {
        expect(
          () => makeDecision(result: DecisionResult.denied, reason: ''),
          throwsA(isA<AssertionError>()),
        );
      });

      test('approved sem reason é válido', () {
        expect(
          () => makeDecision(result: DecisionResult.approved, reason: null),
          returnsNormally,
        );
      });

      test('approved com obligations é válido', () {
        const obligation = AuthorizationObligation(
          type: 'log_access',
          metadata: {'level': 'info'},
        );
        expect(
          () => makeDecision(
            result: DecisionResult.approved,
            obligations: [obligation],
          ),
          returnsNormally,
        );
      });
    });

    group('2. Imutabilidade de Auditoria', () {
      test('Equatable: dois objetos idênticos são iguais', () {
        final d1 = makeDecision(result: DecisionResult.approved);
        final d2 = makeDecision(result: DecisionResult.approved);

        expect(d1, equals(d2));
        expect(d1.hashCode, equals(d2.hashCode));
      });

      test('Equatable: diferença em qualquer campo quebra igualdade', () {
        final base = makeDecision(result: DecisionResult.approved);

        expect(
          base,
          isNot(
            equals(
              makeDecision(
                decisionId: 'different-id',
                result: DecisionResult.approved,
              ),
            ),
          ),
        );
        expect(
          base,
          isNot(
            equals(
              makeDecision(
                result: DecisionResult.denied,
                reason: 'Unauthorized',
              ),
            ),
          ),
        );
        expect(
          base,
          isNot(
            equals(
              makeDecision(
                reason: 'different reason',
                result: DecisionResult.approved,
              ),
            ),
          ),
        );
      });

      test('toJson() produz cópia independente do contextSnapshot', () {
        final mutableSnapshot = Map<String, dynamic>.from(contextSnapshot);
        final decision = makeDecision(
          result: DecisionResult.approved,
          contextSnapshot: mutableSnapshot,
        );

        // Mutate the original map AFTER construction
        mutableSnapshot['organization_id'] = 'TAMPERED';
        mutableSnapshot['actor_id'] = 'HACKED';

        // toJson() must reflect the original values, not the mutated ones
        final json = decision.toJson();
        expect(json['context_snapshot']['organization_id'], equals('org-123'));
        expect(json['context_snapshot']['actor_id'], equals('user-789'));
      });
    });

    group('3. Serialização para Ledger', () {
      test('toJson() contém todas as chaves obrigatórias de auditoria', () {
        final decision = makeDecision(result: DecisionResult.approved);

        final json = decision.toJson();

        expect(json, hasLength(11));
        expect(json.containsKey('decision_id'), isTrue);
        expect(json.containsKey('actor_id'), isTrue);
        expect(json.containsKey('role_id'), isTrue);
        expect(json.containsKey('action_type'), isTrue);
        expect(json.containsKey('target_ref'), isTrue);
        expect(json.containsKey('policy_version'), isTrue);
        expect(json.containsKey('result'), isTrue);
        expect(json.containsKey('reason'), isTrue);
        expect(json.containsKey('occurred_at'), isTrue);
        expect(json.containsKey('context_snapshot'), isTrue);
        expect(json.containsKey('obligations'), isTrue);
      });

      test('toJson() serializa result como string "approved"/"denied"', () {
        final approved = makeDecision(result: DecisionResult.approved);
        final denied = makeDecision(
          result: DecisionResult.denied,
          reason: 'Unauthorized action',
        );

        expect(approved.toJson()['result'], equals('approved'));
        expect(denied.toJson()['result'], equals('denied'));
      });

      test('toJson() serializa occurredAt como ISO8601', () {
        final decision = makeDecision(result: DecisionResult.approved);

        expect(
          decision.toJson()['occurred_at'],
          equals('2026-04-15T10:30:00.000Z'),
        );
      });

      test(
        'toJson() inclui reason mesmo quando null (chave presente, valor null)',
        () {
          final decision = makeDecision(
            result: DecisionResult.approved,
            reason: null,
          );

          final json = decision.toJson();
          expect(json['reason'], isNull);
        },
      );

      test('toJson() de Allow e Deny produzem JSONs distintos', () {
        final approved = makeDecision(result: DecisionResult.approved);
        final denied = makeDecision(
          result: DecisionResult.denied,
          reason: 'Unauthorized action',
        );

        expect(approved.toJson()['result'], equals('approved'));
        expect(denied.toJson()['result'], equals('denied'));
      });

      test('toJson() serializa contextSnapshot completo', () {
        final decision = makeDecision(result: DecisionResult.approved);

        final json = decision.toJson();
        final ctx = json['context_snapshot'];

        expect(ctx['actor_id'], equals('user-789'));
        expect(ctx['role_id'], equals('operator'));
        expect(ctx['organization_id'], equals('org-123'));
        expect(ctx['scopes'], equals(['read', 'write']));
        expect(ctx['captured_at'], equals('2026-04-15T10:30:00.000Z'));
      });
    });

    group('4. Composição com Obligations', () {
      test('decisão approved pode carregar obligations', () {
        const obligation = AuthorizationObligation(
          type: 'log_geolocation',
          metadata: {
            'precision': 'high',
            'timestamp': '2026-04-15T10:30:00.000Z',
          },
        );
        final decision = makeDecision(
          result: DecisionResult.approved,
          obligations: [obligation],
        );

        expect(decision.obligations.length, equals(1));
        expect(decision.obligations.first.type, equals('log_geolocation'));
      });

      test('obligations aparecem no toJson() com type e metadata', () {
        const obligation = AuthorizationObligation(
          type: 'notify_security',
          metadata: {'level': 'medium'},
        );
        final decision = makeDecision(
          result: DecisionResult.approved,
          obligations: [obligation],
        );

        final json = decision.toJson();
        final obligationsJson = json['obligations'];

        expect(obligationsJson, isA<List>());
        expect(obligationsJson.length, equals(1));
        expect(obligationsJson[0]['type'], equals('notify_security'));
        expect(obligationsJson[0]['metadata'], equals({'level': 'medium'}));
      });

      test('decisão sem obligations tem lista vazia no toJson()', () {
        final decision = makeDecision(result: DecisionResult.approved);

        final json = decision.toJson();
        expect(json['obligations'], equals([]));
      });

      test('AuthorizationObligation toJson() produz estrutura correta', () {
        const obligation = AuthorizationObligation(
          type: 'archive_evidence',
          metadata: {'format': 'json', 'retention_days': 365},
        );

        final json = obligation.toJson();

        expect(json['type'], equals('archive_evidence'));
        expect(
          json['metadata'],
          equals({'format': 'json', 'retention_days': 365}),
        );
      });
    });
  });
}
