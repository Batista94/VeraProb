import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_obligation.dart';

/// Semantic Result of a Policy Evaluation against an Action Context.
enum DecisionResult { approved, denied }

/// A pure Snapshot of the Operational World at the exact moment of an attempted action.
///
/// This is DTO-like by design. It does NOT hold live references to Services
/// or Providers. It represents "What did the system know when the user clicked?"
class AuthorizationContext extends Equatable {
  final ActorId actorId;
  final RoleId roleId;
  final String? organizationId; // Business entity isolation (INV-1)
  final String? tenantId; // Future proofing for Multi-Tenant
  final List<String> scopes;
  final DateTime capturedAt;

  const AuthorizationContext({
    required this.actorId,
    required this.roleId,
    this.organizationId,
    this.tenantId,
    this.scopes = const [],
    required this.capturedAt,
  });

  @override
  List<Object?> get props => [
    actorId,
    roleId,
    organizationId,
    tenantId,
    scopes,
    capturedAt,
  ];

  Map<String, dynamic> toJson() {
    return {
      'actor_id': actorId.value,
      'role_id': roleId.value,
      // ignore: use_null_aware_elements
      if (organizationId != null) 'organization_id': organizationId,
      // ignore: use_null_aware_elements
      if (tenantId != null) 'tenant_id': tenantId,
      'scopes': scopes,
      'captured_at': capturedAt.toIso8601String(),
    };
  }
}

/// The Ultimate Forensic Asset in veraprob Enterprise.
///
/// Represents the Immutable historical fact that an Actor attempted an Action
/// against a Target, and the Authority System either Approved or Denied it.
/// It does NOT store the Command object (to survive code/schema migrations).
class AuthorizationDecision extends Equatable {
  final String decisionId;
  final ActorId actorId;
  final RoleId roleId;
  final OperationalActionType actionType;
  final TargetRef targetRef;
  final String policyVersion;
  final DecisionResult result;
  final String? reason;
  final DateTime occurredAt;
  final Map<String, dynamic> contextSnapshot; // Serialized AuthorizationContext
  final List<AuthorizationObligation> obligations;

  const AuthorizationDecision.raw({
    required this.decisionId,
    required this.actorId,
    required this.roleId,
    required this.actionType,
    required this.targetRef,
    required this.policyVersion,
    required this.result,
    this.reason,
    required this.occurredAt,
    required this.contextSnapshot,
    this.obligations = const [],
  });

  factory AuthorizationDecision({
    required String decisionId,
    required ActorId actorId,
    required RoleId roleId,
    required OperationalActionType actionType,
    required TargetRef targetRef,
    required String policyVersion,
    required DecisionResult result,
    String? reason,
    required DateTime occurredAt,
    required Map<String, dynamic> contextSnapshot,
    List<AuthorizationObligation> obligations = const [],
  }) {
    assert(
      result != DecisionResult.denied || (reason != null && reason.isNotEmpty),
      'INV-7: Decisões negadas exigem reason obrigatório.',
    );
    return AuthorizationDecision.raw(
      decisionId: decisionId,
      actorId: actorId,
      roleId: roleId,
      actionType: actionType,
      targetRef: targetRef,
      policyVersion: policyVersion,
      result: result,
      reason: reason,
      occurredAt: occurredAt,
      contextSnapshot: _deepCopyMap(contextSnapshot),
      obligations: obligations,
    );
  }

  bool get isApproved => result == DecisionResult.approved;

  Map<String, dynamic> toJson() {
    return {
      'decision_id': decisionId,
      'actor_id': actorId.value,
      'role_id': roleId.value,
      'action_type': actionType.key,
      'target_ref': targetRef.urn,
      'policy_version': policyVersion,
      'result': result.name,
      'reason': reason,
      'occurred_at': occurredAt.toIso8601String(),
      'context_snapshot': _deepCopyMap(contextSnapshot),
      'obligations': obligations.map((o) => o.toJson()).toList(),
    };
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      if (entry.value is Map<String, dynamic>) {
        result[entry.key] = _deepCopyMap(entry.value as Map<String, dynamic>);
      } else if (entry.value is List) {
        result[entry.key] = List<dynamic>.from(
          entry.value as Iterable<dynamic>,
        );
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  @override
  List<Object?> get props => [
    decisionId,
    actorId,
    roleId,
    actionType,
    targetRef,
    policyVersion,
    result,
    reason,
    occurredAt,
    contextSnapshot,
    obligations,
  ];
}
