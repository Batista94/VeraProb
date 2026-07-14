import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';

/// Write port for the SLA Sandbox shadow evaluation engine.
abstract class SandboxSimulationCommandService {
  /// Invokes `simulate_sla_sandbox` and returns the created session UUID.
  Future<String> simulate({
    required String organizationId,
    required String contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required SandboxSimulationOverrides overrides,
    required String sessionLabel,
  });
}

/// Read port for sandbox simulation sessions and per-event results.
abstract class SandboxSimulationQueryService {
  /// Lists non-expired sessions for the tenant, newest first.
  Future<List<SandboxSimulationSession>> listSessions({
    required String organizationId,
    String? contractId,
    int limit = 50,
  });

  /// Fetches a single session by ID (RLS-scoped).
  Future<SandboxSimulationSession?> getSession({
    required String organizationId,
    required String sessionId,
  });

  /// Returns all per-event results for a session, ordered by occurrence time.
  Future<List<SandboxSimulationResult>> listResults({
    required String organizationId,
    required String sessionId,
  });
}
