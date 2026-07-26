import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/sla_audit/sandbox_simulation_service.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/sandbox_simulation_error_mapper.dart';

/// Postgres implementation of the SLA Sandbox command and query ports.
///
/// **INV-10 / INV-26:** Every PostgREST failure is translated by
/// [SandboxSimulationErrorMapper] — raw [PostgrestException] never crosses
/// the infrastructure boundary.
class PostgresSandboxSimulationService extends BasePostgresRepository
    with SandboxSimulationErrorMapper
    implements SandboxSimulationCommandService, SandboxSimulationQueryService {
  PostgresSandboxSimulationService(super.client);

  @override
  Future<String> simulate({
    required String organizationId,
    required String contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required SandboxSimulationOverrides overrides,
    required String sessionLabel,
  }) {
    return _guarded(() async {
      return client.rpc<String>(
        'simulate_sla_sandbox',
        params: {
          'p_org_id': organizationId,
          'p_contract_id': contractId,
          'p_period_start': periodStartUtc.toIso8601String(),
          'p_period_end': periodEndUtc.toIso8601String(),
          'p_overrides': overrides.toJson(),
          'p_session_label': sessionLabel,
        },
      );
    });
  }

  @override
  Future<List<SandboxSimulationSession>> listSessions({
    required String organizationId,
    String? contractId,
    int limit = 50,
  }) {
    return _guarded(() async {
      var filter = client
          .from('sandbox_simulation_sessions')
          .select()
          .eq('organization_id', organizationId);

      if (contractId != null) {
        filter = filter.eq('contract_id', contractId);
      }

      final rows = await filter
          .gt('expires_at_utc', DateTime.now().toUtc().toIso8601String())
          .order('created_at_utc', ascending: false)
          .limit(limit);
      return (rows as List)
          .map(
            (r) => SandboxSimulationSession.fromRow(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList();
    });
  }

  @override
  Future<SandboxSimulationSession?> getSession({
    required String organizationId,
    required String sessionId,
  }) {
    return _guarded(() async {
      final row = await client
          .from('sandbox_simulation_sessions')
          .select()
          .eq('id', sessionId)
          .eq('organization_id', organizationId)
          .maybeSingle();

      if (row == null) return null;
      return SandboxSimulationSession.fromRow(Map<String, dynamic>.from(row));
    });
  }

  @override
  Future<List<SandboxSimulationResult>> listResults({
    required String organizationId,
    required String sessionId,
  }) {
    return _guarded(() async {
      final rows = await client
          .from('sandbox_simulation_results')
          .select()
          .eq('session_id', sessionId)
          .eq('organization_id', organizationId)
          .order('occurred_at_utc', ascending: true);

      return (rows as List)
          .map(
            (r) => SandboxSimulationResult.fromRow(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList();
    });
  }

  /// INV-10: fail-closed — PostgREST never escapes; other transport errors get a safe PT message.
  Future<T> _guarded<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PostgrestException catch (e) {
      throw mapSandboxSimulationException(e);
    } on DomainException {
      rethrow;
    } on IntegrityException {
      rethrow;
    } catch (_) {
      throw const IntegrityException(
        'Não foi possível concluir a simulação. Verifique os parâmetros e tente novamente.',
      );
    }
  }
}
