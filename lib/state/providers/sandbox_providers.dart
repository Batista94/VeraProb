import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/simulate_sla_sandbox_command.dart';
import 'package:veraprob/application/sla_audit/simulate_sla_sandbox_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sandbox_simulation_service.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'package:veraprob/state/session_recovery.dart';

import 'auth_providers.dart';
import 'contract_providers.dart';

// ── Infrastructure ────────────────────────────────────────────────────────────

final sandboxSimulationServiceProvider =
    Provider<PostgresSandboxSimulationService>(
      (ref) =>
          PostgresSandboxSimulationService(ref.watch(supabaseClientProvider)),
    );

// ── Handler ───────────────────────────────────────────────────────────────────

final simulateSlaSandboxHandlerProvider = Provider<SimulateSlaSandboxHandler>((
  ref,
) {
  return SimulateSlaSandboxHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    commandService: ref.watch(sandboxSimulationServiceProvider),
    permissions: ref.watch(permissionServiceProvider),
  );
});

// ── RBAC gate (client-side defense-in-depth) ──────────────────────────────────

/// True when the current user is TENANT_ADMIN or holds `sandbox:simulate`.
final canSimulateSandboxProvider = Provider<bool>((ref) {
  final role = ref.watch(currentUserRoleProvider);
  final permissions = ref.watch(permissionServiceProvider);
  return role == UserRole.admin ||
      permissions.hasPermission('sandbox:simulate');
});

// ── Query providers (RBAC-gated — Operators/Auditors denied) ─────────────────

/// Active simulation sessions for the current org, optionally filtered by contract.
final sandboxSessionsProvider = FutureProvider.autoDispose
    .family<List<SandboxSimulationSession>, String?>((ref, contractId) async {
      if (!ref.watch(canSimulateSandboxProvider)) return const [];
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return const [];
      return ref
          .watch(sandboxSimulationServiceProvider)
          .listSessions(organizationId: orgId, contractId: contractId)
          .withProviderTimeout();
    });

/// Single session detail.
final sandboxSessionDetailProvider = FutureProvider.autoDispose
    .family<SandboxSimulationSession?, String>((ref, sessionId) async {
      if (!ref.watch(canSimulateSandboxProvider)) return null;
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return null;
      return ref
          .watch(sandboxSimulationServiceProvider)
          .getSession(organizationId: orgId, sessionId: sessionId)
          .withProviderTimeout();
    });

/// Per-event results for a simulation session.
final sandboxSessionResultsProvider = FutureProvider.autoDispose
    .family<List<SandboxSimulationResult>, String>((ref, sessionId) async {
      if (!ref.watch(canSimulateSandboxProvider)) return const [];
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return const [];
      return ref
          .watch(sandboxSimulationServiceProvider)
          .listResults(organizationId: orgId, sessionId: sessionId)
          .withProviderTimeout();
    });

// ── Simulation command notifier ───────────────────────────────────────────────

/// Manages the simulation execution lifecycle: Idle → Loading → Success/Error.
///
/// On success, [state] holds the created session UUID. On failure, [state] is
/// [AsyncError] with a Portuguese [String] message only (INV-10 — no raw
/// exception objects in provider state).
final sandboxSimulationControllerProvider =
    NotifierProvider.autoDispose<
      SandboxSimulationController,
      AsyncValue<String?>
    >(SandboxSimulationController.new);

class SandboxSimulationController extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  /// Runs a sandbox simulation. Returns the session ID on success, or `null`
  /// on failure (Portuguese message in [state] as [AsyncError]).
  Future<String?> runSimulation({
    required String contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required SandboxSimulationOverrides overrides,
    required String sessionLabel,
  }) async {
    if (!ref.read(canSimulateSandboxProvider)) {
      state = AsyncError(
        SandboxSimulationException(
          SandboxSimulationFailure.unauthorized,
        ).message,
        StackTrace.current,
      );
      return null;
    }

    final session = await SessionRecovery.ensureSession(ref);
    if (session == null) {
      state = AsyncError(
        'Sessão expirada. Faça login novamente.',
        StackTrace.current,
      );
      return null;
    }

    final orgId = ref.read(currentOrganizationIdProvider) ?? session.orgId;
    final keepAlive = ref.keepAlive();
    state = const AsyncLoading();

    try {
      final sessionId = await ref
          .read(simulateSlaSandboxHandlerProvider)
          .handle(
            SimulateSlaSandboxCommand(
              organizationId: orgId,
              contractId: contractId,
              periodStartUtc: periodStartUtc,
              periodEndUtc: periodEndUtc,
              overrides: overrides,
              sessionLabel: sessionLabel,
              callerRole: ref.read(currentUserRoleProvider),
              sessionId: session.sessionId,
            ),
          );

      if (!ref.mounted) return null;

      state = AsyncData(sessionId);
      ref.invalidate(sandboxSessionsProvider(null));
      ref.invalidate(sandboxSessionsProvider(contractId));
      return sessionId;
    } catch (e, st) {
      if (!ref.mounted) return null;
      state = AsyncError(_toUserMessage(e), st);
      return null;
    } finally {
      keepAlive.close();
    }
  }

  void reset() => state = const AsyncData(null);
}

// ── UI-facing command wrapper (INV-13) ────────────────────────────────────────
// Returns `null` on success, else a Portuguese error message.

Future<String?> runSandboxSimulation(
  WidgetRef ref, {
  required String contractId,
  required DateTime periodStartUtc,
  required DateTime periodEndUtc,
  required SandboxSimulationOverrides overrides,
  required String sessionLabel,
}) async {
  final sessionId = await ref
      .read(sandboxSimulationControllerProvider.notifier)
      .runSimulation(
        contractId: contractId,
        periodStartUtc: periodStartUtc,
        periodEndUtc: periodEndUtc,
        overrides: overrides,
        sessionLabel: sessionLabel,
      );
  if (sessionId != null) return null;
  return _extractErrorMessage(ref.read(sandboxSimulationControllerProvider));
}

String _toUserMessage(Object e) {
  if (e is SandboxSimulationException) return e.message;
  if (e is DomainException) return e.message;
  if (e is IntegrityException) return e.message;
  if (e is ResourceNotFoundException) return e.message;
  if (e is String) return e;
  return 'Não foi possível executar a simulação. Tente novamente.';
}

String _extractErrorMessage(AsyncValue<String?> value) {
  return value.when(
    data: (_) => 'Não foi possível executar a simulação. Tente novamente.',
    loading: () => 'Não foi possível executar a simulação. Tente novamente.',
    error: (e, _) => _toUserMessage(e),
  );
}
