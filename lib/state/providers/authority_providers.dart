import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/authority/authorizing_command_bus.dart';
import '../../application/authority/operational_command_bus.dart';
import '../../application/operational_control/operational_control_facade.dart';
import '../../domain/authority/core/authority_types.dart';
import '../../domain/authority/decision/authorization_decision.dart';
import '../../domain/authority/policies/authority_policy_evaluator.dart';
import '../../domain/authority/policies/in_memory_policy_evaluator.dart';
import '../../domain/authority/repositories/forensic_decision_repository.dart';
import '../../domain/authority/repositories/in_memory_forensic_repository.dart';
import '../../infrastructure/authority/postgres_forensic_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../state/providers/fleet_providers.dart';

/// ---------------------------------------------------------
/// FASE 4: MOCK AUTH SESSION
/// ---------------------------------------------------------
/// This mimics a live auth session holding the current user's scopes.
/// In production, this reads from SupabaseAuth / SessionState.
final mockAuthorizationContextProvider = StateProvider<AuthorizationContext>((
  ref,
) {
  // Starts with an approved role by default for initial map loads
  return AuthorizationContext(
    actorId: const ActorId('mock_operator_id_123'),
    roleId: const RoleId('supervisor'),
    capturedAt: DateTime.now(),
  );
});

/// ---------------------------------------------------------
/// FASE 3/4: COMMAND BUS & AUTHORITY DEPENDENCIES
/// ---------------------------------------------------------

final forensicDecisionRepositoryProvider = Provider<ForensicDecisionRepository>(
  (ref) {
    final mode = ref.watch(persistenceModeProvider);
    switch (mode) {
      case PersistenceMode.inMemory:
        return InMemoryForensicRepository();
      case PersistenceMode.postgres:
        final client = ref.watch(supabaseClientProvider);
        return PostgresForensicRepository(client);
    }
  },
);

/// Policy Ruleset - Purely functional, no persistence needed
final authorityPolicyEvaluatorProvider = Provider<AuthorityPolicyEvaluator>((
  ref,
) {
  return InMemoryPolicyEvaluator();
});

/// The Command Bus Interceptor Hub
final operationalCommandBusProvider = Provider<OperationalCommandBus>((ref) {
  final evaluator = ref.watch(authorityPolicyEvaluatorProvider);
  final repo = ref.watch(forensicDecisionRepositoryProvider);
  final controlService = ref.watch(operationalControlProvider);

  // Notice we pass a closure so the context is LIVE at the moment of dispatch
  return AuthorizingCommandBus(
    evaluator,
    repo,
    () => ref.read(mockAuthorizationContextProvider),
    controlService,
  );
});

/// ---------------------------------------------------------
/// FASE 4: APPLICATION FACADE (UI ENTRYPOINT)
/// ---------------------------------------------------------
/// The ONLY object the UI should talk to for mutating operational reality.
final operationalControlFacadeProvider = Provider<OperationalControlFacade>((
  ref,
) {
  final bus = ref.watch(operationalCommandBusProvider);
  return OperationalControlFacade(bus);
});
