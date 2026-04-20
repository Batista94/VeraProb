// ignore_for_file: avoid_implementing_value_types

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/authority_policy_evaluator.dart';

// ---------------------------------------------------------------------------
// TEST DOUBLES
// ---------------------------------------------------------------------------

/// Simulates the RBAC layer (the "RbacService" dependency).
///
/// Returns a pre-baked decision so tests can inject any RBAC outcome
/// without depending on the real [RbacPolicyEvaluator] internals.
class _FakeRbacService implements AuthorityPolicyEvaluator {
  final DecisionResult _result;
  final String? _reason;

  const _FakeRbacService({
    DecisionResult result = DecisionResult.approved,
    String? reason,
  }) : _result = result,
       _reason = reason;

  @override
  Future<AuthorizationDecision> evaluate({
    required OperationalActionType actionType,
    required AuthorizationContext context,
    required TargetRef targetRef,
    required DateTime nowUtc,
  }) async {
    return AuthorizationDecision(
      decisionId: 'fake-rbac-decision-id',
      actorId: context.actorId,
      roleId: context.roleId,
      actionType: actionType,
      targetRef: targetRef,
      policyVersion: 'fake_rbac_v1',
      result: _result,
      reason: _reason,
      occurredAt: nowUtc,
      contextSnapshot: context.toJson(),
    );
  }
}

/// Composed evaluator under test.
///
/// Implements the [AuthorityPolicyEvaluator] contract with three sequential
/// gates on top of the injected RBAC service:
///   1. RBAC pre-filter (fail-fast)
///   2. Scope gate — actor must carry [_scopeCanApproveSanctions]
///   3. SuperAdmin Lock — sanctions >= [_superAdminLockCents] are vetoed
///
/// TargetRef encoding: entityId = '{sanction-uuid}:{org-id}:{amount-cents}'
class _SanctionAuthorityEvaluator implements AuthorityPolicyEvaluator {
  static const int _superAdminLockCents =
      10_000_000; // R$ 100,000 — Physical Metric - Double Required not applicable (int cents, INV-4)
  static const String _scopeCanApproveSanctions = 'canApproveSanctions';
  static const String _policyVersion = 'sanction_authority_v1.0';

  final AuthorityPolicyEvaluator _rbacService;

  const _SanctionAuthorityEvaluator(this._rbacService);

  @override
  Future<AuthorizationDecision> evaluate({
    required OperationalActionType actionType,
    required AuthorizationContext context,
    required TargetRef targetRef,
    required DateTime nowUtc,
  }) async {
    // Gate 1: RBAC pre-filter — short-circuit on denial.
    final rbacDecision = await _rbacService.evaluate(
      actionType: actionType,
      context: context,
      targetRef: targetRef,
      nowUtc: nowUtc,
    );
    if (!rbacDecision.isApproved) return rbacDecision;

    // Gate 2: Scope gate.
    if (!context.scopes.contains(_scopeCanApproveSanctions)) {
      return _buildDecision(
        context: context,
        actionType: actionType,
        targetRef: targetRef,
        nowUtc: nowUtc,
        result: DecisionResult.denied,
        reason:
            'SCOPE_MISSING: Actor não possui escopo canApproveSanctions. '
            'Apenas atores com o escopo explícito podem aprovar sanções.',
      );
    }

    // Gate 3: SuperAdmin Lock — extreme sanction amount veto.
    final amountCents = _extractAmountCents(targetRef);
    if (amountCents >= _superAdminLockCents) {
      return _buildDecision(
        context: context,
        actionType: actionType,
        targetRef: targetRef,
        nowUtc: nowUtc,
        result: DecisionResult.denied,
        reason:
            'SUPER_ADMIN_LOCK: Sanção de $amountCents centavos '
            '(>= $_superAdminLockCents centavos) exige aprovação exclusiva do '
            'Super Administrador. Trava de segurança máxima ativada. '
            'Acesso negado para ${context.roleId.value}.',
      );
    }

    // All gates passed — approved.
    return _buildDecision(
      context: context,
      actionType: actionType,
      targetRef: targetRef,
      nowUtc: nowUtc,
      result: DecisionResult.approved,
      reason: null,
    );
  }

  /// Extracts the sanction amount in cents from the TargetRef.
  ///
  /// Expected entityId format: '{uuid}:{org-id}:{amount-cents}'
  /// Returns 0 if the format is invalid (safe default — does not trigger lock).
  int _extractAmountCents(TargetRef targetRef) {
    final parts = targetRef.entityId.split(':');
    if (parts.length < 3) return 0;
    return int.tryParse(parts[2]) ?? 0;
  }

  AuthorizationDecision _buildDecision({
    required AuthorizationContext context,
    required OperationalActionType actionType,
    required TargetRef targetRef,
    required DateTime nowUtc,
    required DecisionResult result,
    required String? reason,
  }) {
    return AuthorizationDecision(
      decisionId:
          'sanction-decision-${context.actorId.value}-${actionType.key}',
      actorId: context.actorId,
      roleId: context.roleId,
      actionType: actionType,
      targetRef: targetRef,
      policyVersion: _policyVersion,
      result: result,
      reason: reason,
      occurredAt: nowUtc,
      contextSnapshot: context.toJson(),
    );
  }
}

// ---------------------------------------------------------------------------
// TEST FIXTURES
// ---------------------------------------------------------------------------

/// Deterministic, UTC-compliant timestamp for all tests (INV-6).
final _testNowUtc = DateTime.utc(2026, 4, 14, 12, 0, 0);

AuthorizationContext _makeContext({
  String actorId = 'actor-001',
  String roleId = 'auditor',
  String organizationId = 'org-forensic',
  List<String> scopes = const [],
}) {
  return AuthorizationContext(
    actorId: ActorId(actorId),
    roleId: RoleId(roleId),
    organizationId: organizationId,
    capturedAt: DateTime.utc(2026, 4, 14, 11, 55, 0),
    scopes: scopes,
  );
}

/// Standard sanction — below SuperAdmin Lock threshold.
/// Amount: R$ 5,000 = 500_000 cents.
const _standardSanctionRef = TargetRef(
  'sanction',
  'san-001:org-forensic:500000',
);

/// Boundary sanction — 1 cent below the lock threshold.
/// Amount: R$ 99,999.99 = 9_999_999 cents.
const _borderlineSanctionRef = TargetRef(
  'sanction',
  'san-002:org-forensic:9999999',
);

/// Lock-trigger sanction — exactly at threshold.
/// Amount: R$ 100,000.00 = 10_000_000 cents.
const _lockTriggerSanctionRef = TargetRef(
  'sanction',
  'san-003:org-forensic:10000000',
);

/// Extreme sanction — far above threshold.
/// Amount: R$ 500,000.00 = 50_000_000 cents.
const _extremeSanctionRef = TargetRef(
  'sanction',
  'san-004:org-forensic:50000000',
);

const _approveSanctionAction = OperationalActionType('approve_sanction');

// ---------------------------------------------------------------------------
// TESTS
// ---------------------------------------------------------------------------

void main() {
  // Evaluator backed by a RBAC fake that always approves (nominal path).
  late _SanctionAuthorityEvaluator evaluatorWithRbacApproved;

  // Evaluator backed by a RBAC fake that always denies (RBAC pre-filter path).
  late _SanctionAuthorityEvaluator evaluatorWithRbacDenied;

  setUp(() {
    evaluatorWithRbacApproved = const _SanctionAuthorityEvaluator(
      _FakeRbacService(result: DecisionResult.approved),
    );
    evaluatorWithRbacDenied = const _SanctionAuthorityEvaluator(
      _FakeRbacService(
        result: DecisionResult.denied,
        reason: 'RBAC: papel sem permissão para approve_sanction.',
      ),
    );
  });

  // -------------------------------------------------------------------------
  // GROUP 1: NOMINAL APPROVAL — STANDARD SANCTION
  // -------------------------------------------------------------------------
  group('AuthorityPolicyEvaluator — 1. Nominal Approval (Standard Sanction)', () {
    test(
      'Auditor com canApproveSanctions aprova sanção padrão de 500_000 cents',
      () async {
        final context = _makeContext(
          actorId: 'auditor-audit-001',
          roleId: 'auditor',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.approved);
        expect(decision.isApproved, isTrue);
        expect(decision.reason, isNull);
      },
    );

    test(
      'Admin com canApproveSanctions aprova sanção de 9_999_999 cents (1 cent abaixo do teto)',
      () async {
        final context = _makeContext(
          actorId: 'admin-admin-002',
          roleId: 'admin',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _borderlineSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.approved);
        expect(decision.isApproved, isTrue);
        expect(decision.reason, isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // GROUP 2: SUPER-ADMIN LOCK — VETO CRÍTICO
  // -------------------------------------------------------------------------
  group('AuthorityPolicyEvaluator — 2. SuperAdmin Lock (Veto Crítico — INV-6)', () {
    test(
      'Auditor (passou no teste 1) é BLOQUEADO na sanção de 10_000_000 cents — trava ativada',
      () async {
        final context = _makeContext(
          actorId: 'auditor-audit-001',
          roleId: 'auditor',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _lockTriggerSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.denied);
        expect(decision.isApproved, isFalse);
        expect(decision.reason, isNotNull);
        expect(decision.reason, isNotEmpty);
        expect(decision.reason, contains('SUPER_ADMIN_LOCK'));
        expect(decision.reason, contains('Super Administrador'));
      },
    );

    test(
      'Admin (passou no teste 1) é BLOQUEADO na sanção extrema de 50_000_000 cents — regra de negócio sobrepõe RBAC',
      () async {
        final context = _makeContext(
          actorId: 'admin-admin-002',
          roleId: 'admin',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _extremeSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.denied);
        expect(decision.isApproved, isFalse);
        expect(decision.reason, isNotNull);
        expect(decision.reason, contains('SUPER_ADMIN_LOCK'));
      },
    );

    test(
      'Motivo do veto referencia o roleId do ator bloqueado (rastreabilidade forense)',
      () async {
        final context = _makeContext(
          actorId: 'auditor-audit-003',
          roleId: 'auditor',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _lockTriggerSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.reason, contains('auditor'));
      },
    );

    test(
      'Motivo menciona o valor exato da sanção em centavos (evidência forense)',
      () async {
        final context = _makeContext(
          actorId: 'admin-admin-004',
          roleId: 'admin',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _lockTriggerSanctionRef, // 10_000_000 cents
          nowUtc: _testNowUtc,
        );

        // Reason must include the exact threshold and sanction value.
        expect(decision.reason, contains('10000000'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // GROUP 3: FAIL-CLOSED — SCOPE GATE
  // -------------------------------------------------------------------------
  group('AuthorityPolicyEvaluator — 3. Fail-Closed (Scope Gate)', () {
    test(
      'Operador SEM canApproveSanctions é bloqueado em sanção padrão — RBAC aprovado não é suficiente',
      () async {
        final context = _makeContext(
          actorId: 'operator-ops-001',
          roleId: 'operator',
          organizationId: 'org-forensic',
          scopes: [], // Deliberately empty — no canApproveSanctions.
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.denied);
        expect(decision.isApproved, isFalse);
        expect(decision.reason, isNotNull);
        expect(decision.reason, contains('SCOPE_MISSING'));
      },
    );

    test(
      'ContractorViewer sem escopos é bloqueado sumariamente — escopo vazio = deny',
      () async {
        final context = _makeContext(
          actorId: 'contractor-cv-001',
          roleId: 'contractor_viewer',
          organizationId: 'org-forensic',
          scopes: [],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.denied);
        expect(decision.isApproved, isFalse);
        expect(decision.reason, contains('SCOPE_MISSING'));
      },
    );

    test(
      'Actor com escopo irrelevante (canViewReports) mas sem canApproveSanctions é bloqueado',
      () async {
        final context = _makeContext(
          actorId: 'auditor-audit-005',
          roleId: 'auditor',
          organizationId: 'org-forensic',
          scopes: [
            'canViewReports',
            'canExportLedger',
          ], // No canApproveSanctions.
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.denied);
        expect(decision.reason, contains('SCOPE_MISSING'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // GROUP 4: RBAC PRE-FILTER
  // -------------------------------------------------------------------------
  group('AuthorityPolicyEvaluator — 4. RBAC Pre-Filter (Fail-Fast)', () {
    test(
      'RBAC denied short-circuits antes de checar escopo — actor com canApproveSanctions ainda é bloqueado',
      () async {
        final context = _makeContext(
          actorId: 'operator-ops-002',
          roleId: 'operator',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'], // Has scope, but RBAC says no.
        );

        final decision = await evaluatorWithRbacDenied.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.denied);
        expect(decision.isApproved, isFalse);
      },
    );

    test(
      'Motivo do RBAC denial é preservado verbatim na decisão final (rastreabilidade)',
      () async {
        const expectedRbacReason =
            'RBAC: papel sem permissão para approve_sanction.';
        final context = _makeContext(
          actorId: 'operator-ops-003',
          roleId: 'operator',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacDenied.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.reason, equals(expectedRbacReason));
      },
    );

    test(
      'RBAC denied bloqueia mesmo sanção de valor zero — pré-filtro é absoluto',
      () async {
        const zeroValueRef = TargetRef('sanction', 'san-zero:org-forensic:0');
        final context = _makeContext(
          actorId: 'admin-admin-006',
          roleId: 'admin',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacDenied.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: zeroValueRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.result, DecisionResult.denied);
      },
    );
  });

  // -------------------------------------------------------------------------
  // GROUP 5: FORENSIC DECISION INTEGRITY
  // -------------------------------------------------------------------------
  group('AuthorityPolicyEvaluator — 5. Forensic Decision Integrity', () {
    test('decisionId é não-vazio em decisão aprovada', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-007',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.decisionId, isNotEmpty);
    });

    test('decisionId é não-vazio em decisão negada', () async {
      final context = _makeContext(
        actorId: 'operator-ops-004',
        roleId: 'operator',
        organizationId: 'org-forensic',
        scopes: [],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.decisionId, isNotEmpty);
    });

    test('occurredAt é UTC (INV-6)', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-008',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.occurredAt.isUtc, isTrue);
    });

    test(
      'occurredAt corresponde ao nowUtc fornecido — sem clock drift',
      () async {
        final context = _makeContext(
          actorId: 'auditor-audit-009',
          roleId: 'auditor',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );
        final explicitNowUtc = DateTime.utc(2026, 4, 14, 8, 30, 0);

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: explicitNowUtc,
        );

        expect(decision.occurredAt, equals(explicitNowUtc));
      },
    );

    test('actionType preservado da entrada', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-010',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.actionType, equals(_approveSanctionAction));
    });

    test('actorId preservado do contexto', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-011',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.actorId.value, 'auditor-audit-011');
    });

    test(
      'contextSnapshot corresponde a context.toJson() (snapshot imutável)',
      () async {
        final context = _makeContext(
          actorId: 'auditor-audit-012',
          roleId: 'auditor',
          organizationId: 'org-forensic',
          scopes: ['canApproveSanctions'],
        );

        final decision = await evaluatorWithRbacApproved.evaluate(
          actionType: _approveSanctionAction,
          context: context,
          targetRef: _standardSanctionRef,
          nowUtc: _testNowUtc,
        );

        expect(decision.contextSnapshot, equals(context.toJson()));
        expect(decision.contextSnapshot['actor_id'], 'auditor-audit-012');
        expect(decision.contextSnapshot['organization_id'], 'org-forensic');
      },
    );

    test('decisão aprovada tem reason == null', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-013',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.reason, isNull);
    });

    test('decisão negada tem reason não-nulo e não-vazio (INV-10)', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-014',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _lockTriggerSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.reason, isNotNull);
      expect(decision.reason, isNotEmpty);
    });

    test('policyVersion identifica a política aplicada', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-015',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.policyVersion, 'sanction_authority_v1.0');
    });

    test('targetRef preservado da entrada (rastreabilidade do alvo)', () async {
      final context = _makeContext(
        actorId: 'auditor-audit-016',
        roleId: 'auditor',
        organizationId: 'org-forensic',
        scopes: ['canApproveSanctions'],
      );

      final decision = await evaluatorWithRbacApproved.evaluate(
        actionType: _approveSanctionAction,
        context: context,
        targetRef: _standardSanctionRef,
        nowUtc: _testNowUtc,
      );

      expect(decision.targetRef, equals(_standardSanctionRef));
    });
  });
}
