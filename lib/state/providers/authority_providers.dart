import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/authority/authorizing_command_bus.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/application/operational_control/operational_control_facade.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/authority_policy_evaluator.dart';
import 'package:veraprob/domain/authority/repositories/forensic_decision_repository.dart';
import 'package:veraprob/infrastructure/authority/postgres_forensic_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Live [AuthorizationContext] from JWT session (INV-1 actor + org + role).
///
/// Fail-closed when unsigned: empty actor + most restrictive role.
AuthorizationContext buildAuthorizationContext(Ref ref) {
  final dateTimeProvider = ref.read(dateTimeProviderProvider);
  final operatorId = ref.read(currentOperatorIdProvider);
  final orgId = ref.read(currentOrganizationIdProvider);
  final role = ref.read(currentUserRoleProvider);

  return AuthorizationContext(
    actorId: ActorId(operatorId ?? ''),
    roleId: RoleId(_roleIdFor(role)),
    organizationId: orgId,
    capturedAt: dateTimeProvider.nowUtc(),
  );
}

String _roleIdFor(UserRole role) {
  return switch (role) {
    UserRole.admin => 'admin',
    UserRole.operator => 'operator',
    UserRole.auditor => 'auditor',
    UserRole.contractorViewer => 'contractor_viewer',
    UserRole.superAdmin => 'super_admin',
  };
}

final authorizationContextProvider = Provider<AuthorizationContext>((ref) {
  // Recompute when auth/org/role change; capture time is still fresh on read.
  ref.watch(authStateProvider);
  ref.watch(currentOrganizationIdProvider);
  ref.watch(currentUserRoleProvider);
  return buildAuthorizationContext(ref);
});

/// ---------------------------------------------------------
/// COMMAND BUS & AUTHORITY DEPENDENCIES
/// ---------------------------------------------------------

final forensicDecisionRepositoryProvider = Provider<ForensicDecisionRepository>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    return PostgresForensicRepository(client);
  },
);

/// Policy Ruleset - Purely functional, no persistence needed
final authorityPolicyEvaluatorProvider = Provider<AuthorityPolicyEvaluator>((
  ref,
) {
  return AuthorityPolicyEvaluator();
});

/// The Command Bus Interceptor Hub
final operationalCommandBusProvider = Provider<OperationalCommandBus>((ref) {
  final evaluator = ref.watch(authorityPolicyEvaluatorProvider);
  final repo = ref.watch(forensicDecisionRepositoryProvider);
  final controlService = ref.watch(operationalControlProvider);

  // Closure so context is LIVE at the moment of dispatch (fresh capturedAt).
  return AuthorizingCommandBus(
    evaluator,
    repo,
    () => buildAuthorizationContext(ref),
    controlService,
    ref.watch(dateTimeProviderProvider),
  );
});

/// ---------------------------------------------------------
/// APPLICATION FACADE (UI ENTRYPOINT)
/// ---------------------------------------------------------
/// The ONLY object the UI should talk to for mutating operational reality.
final operationalControlFacadeProvider = Provider<OperationalControlFacade>((
  ref,
) {
  final bus = ref.watch(operationalCommandBusProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  return OperationalControlFacade(bus, authRepo);
});
