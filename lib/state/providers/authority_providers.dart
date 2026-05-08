import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/authority/authorizing_command_bus.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/application/operational_control/operational_control_facade.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/authority_policy_evaluator.dart';
import 'package:veraprob/domain/authority/policies/in_memory_policy_evaluator.dart';
import 'package:veraprob/domain/authority/repositories/forensic_decision_repository.dart';
import 'package:veraprob/domain/authority/repositories/in_memory_forensic_repository.dart';
import 'package:veraprob/infrastructure/authority/postgres_forensic_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// ---------------------------------------------------------
/// FASE 4: MOCK AUTH SESSION
/// ---------------------------------------------------------
/// This mimics a live auth session holding the current user's scopes.
/// In production, this reads from SupabaseAuth / SessionState.
class _MockAuthorizationContextNotifier extends Notifier<AuthorizationContext> {
  @override
  AuthorizationContext build() {
    final dateTimeProvider = ref.watch(dateTimeProviderProvider);
    // Starts with an approved role by default for initial map loads
    return AuthorizationContext(
      actorId: const ActorId('mock_operator_id_123'),
      roleId: const RoleId('supervisor'),
      capturedAt: dateTimeProvider.nowUtc(),
    );
  }
}

final mockAuthorizationContextProvider =
    NotifierProvider<_MockAuthorizationContextNotifier, AuthorizationContext>(
      _MockAuthorizationContextNotifier.new,
    );

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
    ref.watch(dateTimeProviderProvider),
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
  final authRepo = ref.watch(authRepositoryProvider);

  return OperationalControlFacade(bus, authRepo);
});
