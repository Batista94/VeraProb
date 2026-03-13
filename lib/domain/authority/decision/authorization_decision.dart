import 'package:equatable/equatable.dart';
import '../core/authority_types.dart';

/// Semantic Result of a Policy Evaluation against an Action Context.
enum DecisionResult { approved, denied }

/// A pure Snapshot of the Operational World at the exact moment of an attempted action.
///
/// This is DTO-like by design. It does NOT hold live references to Services
/// or Providers. It represents "What did the system know when the user clicked?"
class AuthorizationContext extends Equatable {
  final ActorId actorId;
  final RoleId roleId;
  final String? tenantId; // Future proofing for Multi-Tenant
  final List<String> scopes;
  final DateTime capturedAt;

  const AuthorizationContext({
    required this.actorId,
    required this.roleId,
    this.tenantId,
    this.scopes = const [],
    required this.capturedAt,
  });

  @override
  List<Object?> get props => [actorId, roleId, tenantId, scopes, capturedAt];

  Map<String, dynamic> toJson() {
    return {
      'actor_id': actorId.value,
      'role_id': roleId.value,
      // ignore: use_null_aware_elements
      if (tenantId != null) 'tenant_id': tenantId,
      'scopes': scopes,
      'captured_at': capturedAt.toIso8601String(),
    };
  }
}

/// The Ultimate Forensic Asset in PactaFlow Enterprise.
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

  const AuthorizationDecision({
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
  });

  bool get isApproved => result == DecisionResult.approved;

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
  ];
}
