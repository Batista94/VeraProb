import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/rbac_policy_evaluator.dart';

void main() {
  late RbacPolicyEvaluator evaluator;

  // Test helpers
  AuthorizationContext makeContext({
    String actorId = 'user-123',
    String roleId = 'operator',
    String? organizationId = 'org-001',
    String? tenantId,
    List<String> scopes = const [],
    DateTime? capturedAt,
  }) {
    return AuthorizationContext(
      actorId: ActorId(actorId),
      roleId: RoleId(roleId),
      organizationId: organizationId,
      tenantId: tenantId,
      scopes: scopes,
      capturedAt: capturedAt ?? DateTime.utc(2026, 4, 7, 12, 0, 0),
    );
  }

  final testNowUtc = DateTime.utc(2026, 4, 8, 12, 0, 0);

  TargetRef makeTargetRef({
    String entityType = 'trip',
    String entityId = 'trip-uuid:org-001',
  }) {
    return TargetRef(entityType, entityId);
  }

  setUp(() {
    evaluator = RbacPolicyEvaluator();
  });

  group('RbacPolicyEvaluator - RBAC Integrity', () {
    test('operator cannot perform admin_only action', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'operator'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('Operador'));
      expect(decision.reason, contains('ações administrativas'));
    });

    test('auditor cannot perform admin_only action', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'auditor'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('Auditor'));
    });

    test('contractorViewer cannot perform admin_only action', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'contractor_viewer'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('Visualizador Contratante'));
    });

    test('admin can perform admin_only action', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'admin'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });

    test('superAdmin can perform admin_only action', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'super_admin'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });
  });

  group('RbacPolicyEvaluator - Contextual Decisions (Trip Approval)', () {
    test('operator can approve trip within own organization', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(roleId: 'operator', organizationId: 'org-001'),
        targetRef: makeTargetRef(entityId: 'trip-001:org-001'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });

    test('admin can approve trip within own organization', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(roleId: 'admin', organizationId: 'org-001'),
        targetRef: makeTargetRef(entityId: 'trip-001:org-001'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });

    test('operator can reject trip within own organization', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.rejectTrip,
        context: makeContext(roleId: 'operator', organizationId: 'org-001'),
        targetRef: makeTargetRef(entityId: 'trip-001:org-001'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });

    test('operator cannot approve trip from different organization', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(roleId: 'operator', organizationId: 'org-001'),
        targetRef: makeTargetRef(entityId: 'trip-001:org-002'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('org-001'));
      expect(decision.reason, contains('org-002'));
    });

    test('auditor cannot approve trip even within own organization', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(roleId: 'auditor', organizationId: 'org-001'),
        targetRef: makeTargetRef(entityId: 'trip-001:org-001'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('Auditor'));
    });

    test('contractorViewer cannot approve trip', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(
          roleId: 'contractor_viewer',
          organizationId: 'org-001',
        ),
        targetRef: makeTargetRef(entityId: 'trip-001:org-001'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('Visualizador Contratante'));
    });

    test('trip action denied when target has no organization info', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(roleId: 'operator', organizationId: 'org-001'),
        targetRef: makeTargetRef(entityId: 'trip-001'), // No org suffix
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('organização do alvo'));
    });
  });

  group('RbacPolicyEvaluator - SuperAdmin Bypass', () {
    test('superAdmin bypasses organization block for approveTrip', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(roleId: 'super_admin', organizationId: null),
        targetRef: makeTargetRef(entityId: 'trip-001:org-999'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });

    test('superAdmin bypasses organization block for rejectTrip', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.rejectTrip,
        context: makeContext(roleId: 'super_admin', organizationId: null),
        targetRef: makeTargetRef(entityId: 'trip-001:org-999'),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });

    test('superAdmin bypasses admin_only restriction', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'super_admin', organizationId: null),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
      expect(decision.reason, isNull);
    });

    test('superAdmin bypasses all standard actions', () async {
      final actions = [
        OperationalActionType.resolveAlert,
        OperationalActionType.acknowledgeAlert,
        OperationalActionType.overrideTripStatus,
        OperationalActionType.reassignVehicle,
        OperationalActionType.assignDriver,
      ];

      for (final action in actions) {
        final decision = await evaluator.evaluate(
          actionType: action,
          context: makeContext(roleId: 'super_admin', organizationId: null),
          targetRef: makeTargetRef(),
          nowUtc: testNowUtc,
        );

        expect(
          decision.result,
          DecisionResult.approved,
          reason: 'superAdmin should approve ${action.key}',
        );
      }
    });
  });

  group('RbacPolicyEvaluator - Edge Cases', () {
    test('empty roleId defaults to denied', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: '', organizationId: 'org-001'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('RoleId vazio'));
    });

    test('null organizationId defaults to denied', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'operator', organizationId: null),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('OrganizationId vazio'));
    });

    test('empty organizationId defaults to denied', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'operator', organizationId: ''),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
      expect(decision.reason, contains('OrganizationId vazio'));
    });

    test('unknown roleId defaults to most restrictive role', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'unknown_role', organizationId: 'org-001'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      // Unknown role maps to contractorViewer which cannot do admin_only
      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
    });

    test('unknown roleId can perform standard actions', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'unknown_role', organizationId: 'org-001'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      // Unknown role maps to contractorViewer which can do standard actions
      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
    });

    test('unknown roleId cannot approve trips', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.approveTrip,
        context: makeContext(roleId: 'unknown_role', organizationId: 'org-001'),
        targetRef: makeTargetRef(entityId: 'trip-001:org-001'),
        nowUtc: testNowUtc,
      );

      // Unknown role maps to contractorViewer which cannot approve trips
      expect(decision.result, DecisionResult.denied);
      expect(decision.isApproved, isFalse);
    });
  });

  group('RbacPolicyEvaluator - Decision Integrity', () {
    test('decisionId is non-empty', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.decisionId, isNotEmpty);
    });

    test('actorId preserved from context', () async {
      final context = makeContext(actorId: 'actor-456');
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: context,
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.actorId, context.actorId);
      expect(decision.actorId.value, 'actor-456');
    });

    test('roleId preserved from context', () async {
      final context = makeContext(roleId: 'admin');
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: context,
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.roleId, context.roleId);
      expect(decision.roleId.value, 'admin');
    });

    test('targetRef preserved from input', () async {
      final targetRef = makeTargetRef(
        entityType: 'vehicle',
        entityId: 'veh-001:org-001',
      );
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.reassignVehicle,
        context: makeContext(),
        targetRef: targetRef,
        nowUtc: testNowUtc,
      );

      expect(decision.targetRef, targetRef);
    });

    test('actionType preserved from input', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.overrideRouteDeviation,
        context: makeContext(),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.actionType, OperationalActionType.overrideRouteDeviation);
    });

    test('policyVersion is set', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.policyVersion, 'rbac_v1.0.0');
    });

    test('occurredAt is UTC', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.occurredAt.isUtc, isTrue);
    });

    test('contextSnapshot matches context.toJson()', () async {
      final context = makeContext(
        actorId: 'actor-789',
        roleId: 'operator',
        organizationId: 'org-002',
      );
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: context,
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.contextSnapshot, context.toJson());
      expect(decision.contextSnapshot['actor_id'], 'actor-789');
      expect(decision.contextSnapshot['role_id'], 'operator');
      expect(decision.contextSnapshot['organization_id'], 'org-002');
    });

    test('denied decision carries reason', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'operator'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.reason, isNotNull);
      expect(decision.reason, isNotEmpty);
    });

    test('approved decision has null reason', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'admin'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.reason, isNull);
    });

    test('isApproved getter returns true for approved', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'admin'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.isApproved, isTrue);
    });

    test('isApproved getter returns false for denied', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.adminOnly,
        context: makeContext(roleId: 'operator'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.isApproved, isFalse);
    });
  });

  group('RbacPolicyEvaluator - Standard Actions', () {
    test('operator can resolveAlert', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'operator'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
    });

    test('operator can acknowledgeAlert', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.acknowledgeAlert,
        context: makeContext(roleId: 'operator'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
    });

    test('auditor can resolveAlert', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'auditor'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
    });

    test('contractorViewer can resolveAlert', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'contractor_viewer'),
        targetRef: makeTargetRef(),
        nowUtc: testNowUtc,
      );

      expect(decision.result, DecisionResult.approved);
      expect(decision.isApproved, isTrue);
    });
  });
}
