import 'package:uuid/uuid.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/authority_policy_evaluator.dart';
import 'package:veraprob/domain/enums/user_role.dart';

/// Production-ready RBAC Policy Evaluator.
///
/// Evaluates an [OperationalActionType] against an [AuthorizationContext]
/// using Role-Based Access Control rules with organizational isolation.
///
/// Rules:
/// 1. **RBAC Integrity:** UserRole.operator cannot perform Action.adminOnly
/// 2. **Contextual Decisions:** Users can only approve/reject trips within their own organizationId
/// 3. **SuperAdmin Bypass:** UserRole.superAdmin ignores standard organization blocks
/// 4. **Edge Cases:** Null/missing permissions default to Access.denied
class RbacPolicyEvaluator implements AuthorityPolicyEvaluator {
  final Uuid _uuid;

  RbacPolicyEvaluator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _policyVersion = 'rbac_v1.0.0';

  @override
  Future<AuthorizationDecision> evaluate({
    required OperationalActionType actionType,
    required AuthorizationContext context,
    required TargetRef targetRef,
  }) async {
    final decision = _evaluateSync(
      actionType: actionType,
      context: context,
      targetRef: targetRef,
    );

    return AuthorizationDecision(
      decisionId: _uuid.v4(),
      actorId: context.actorId,
      roleId: context.roleId,
      actionType: actionType,
      targetRef: targetRef,
      policyVersion: _policyVersion,
      result: decision.result,
      reason: decision.reason,
      occurredAt:
          StaticDateTimeProvider.instance?.now() ?? DateTime.now().toUtc(),
      contextSnapshot: context.toJson(),
    );
  }

  ({DecisionResult result, String? reason}) _evaluateSync({
    required OperationalActionType actionType,
    required AuthorizationContext context,
    required TargetRef targetRef,
  }) {
    // Edge Case: null/missing roleId defaults to denied
    if (context.roleId.value.isEmpty) {
      return (
        result: DecisionResult.denied,
        reason: 'RoleId vazio ou ausente.',
      );
    }

    // Resolve UserRole from RoleId
    final userRole = _resolveUserRole(context.roleId);

    // SuperAdmin bypass: approve all actions (before org check)
    if (userRole == UserRole.superAdmin) {
      return (result: DecisionResult.approved, reason: null);
    }

    // Edge Case: null/missing organizationId defaults to denied (after SuperAdmin check)
    if (context.organizationId == null || context.organizationId!.isEmpty) {
      return (
        result: DecisionResult.denied,
        reason: 'OrganizationId vazio ou ausente.',
      );
    }

    // RBAC Integrity: operator cannot perform admin_only
    if (actionType == OperationalActionType.adminOnly) {
      if (userRole == UserRole.operator || userRole == UserRole.auditor) {
        return (
          result: DecisionResult.denied,
          reason:
              'Acesso negado: ${userRole.label} não possui permissão para ações administrativas.',
        );
      }
      // contractorViewer also cannot perform admin_only
      if (userRole == UserRole.contractorViewer) {
        return (
          result: DecisionResult.denied,
          reason:
              'Acesso negado: Visualizador Contratante não possui permissão para ações administrativas.',
        );
      }
    }

    // Contextual Decisions: approve/reject trips only within own organizationId
    if (actionType == OperationalActionType.approveTrip ||
        actionType == OperationalActionType.rejectTrip) {
      return _evaluateTripAction(actionType, context, targetRef, userRole);
    }

    // Default: approve standard actions for recognized roles
    return (result: DecisionResult.approved, reason: null);
  }

  ({DecisionResult result, String? reason}) _evaluateTripAction(
    OperationalActionType actionType,
    AuthorizationContext context,
    TargetRef targetRef,
    UserRole userRole,
  ) {
    // Extract target organization from TargetRef metadata
    // Format: "trip:uuid:orgId" or we check against context.organizationId
    final targetOrgId = _extractTargetOrganizationId(targetRef);

    // If target has no org info, default to denied
    if (targetOrgId == null || targetOrgId.isEmpty) {
      return (
        result: DecisionResult.denied,
        reason:
            'Acesso negado: não foi possível determinar a organização do alvo.',
      );
    }

    // SuperAdmin already handled above (bypass)

    // Check if user's organization matches target's organization
    if (context.organizationId != targetOrgId) {
      return (
        result: DecisionResult.denied,
        reason:
            'Acesso negado: usuário da organização ${context.organizationId} não pode ${actionType.key} trip da organização $targetOrgId.',
      );
    }

    // operator and admin can approve/reject trips within their org
    if (userRole == UserRole.operator || userRole == UserRole.admin) {
      return (result: DecisionResult.approved, reason: null);
    }

    // auditor and contractorViewer cannot approve/reject trips
    return (
      result: DecisionResult.denied,
      reason:
          'Acesso negado: ${userRole.label} não possui permissão para ${actionType.key}.',
    );
  }

  UserRole _resolveUserRole(RoleId roleId) {
    switch (roleId.value) {
      case 'admin':
        return UserRole.admin;
      case 'operator':
        return UserRole.operator;
      case 'auditor':
        return UserRole.auditor;
      case 'contractor_viewer':
        return UserRole.contractorViewer;
      case 'super_admin':
        return UserRole.superAdmin;
      default:
        // Unknown role defaults to most restrictive
        return UserRole.contractorViewer;
    }
  }

  String? _extractTargetOrganizationId(TargetRef targetRef) {
    // TargetRef format: entityType = "trip", entityId = "uuid:orgId"
    // Or we use a simpler approach: entityId contains org info
    final parts = targetRef.entityId.split(':');
    if (parts.length >= 2) {
      return parts[1];
    }
    // If no org info in entityId, return null (will be denied)
    return null;
  }
}
