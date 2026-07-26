import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Maps PostgREST/PostgreSQL errors from `simulate_sla_sandbox` to typed
/// domain exceptions with Portuguese user-facing messages (INV-10).
///
/// Fail-closed: never rethrows [PostgrestException] or leaks SQL/stack traces.
mixin SandboxSimulationErrorMapper on PostgresErrorInterceptor {
  Exception mapSandboxSimulationException(PostgrestException e) {
    final nested = _parseNestedPayload(e.message);
    final code = nested['code'] ?? e.code ?? '';
    final message = (nested['message'] ?? e.message).toLowerCase();
    return _classify(code, message);
  }

  Exception _classify(String code, String message) {
    if (code == '57014' ||
        message.contains('statement timeout') ||
        message.contains('canceling statement') ||
        message.contains('query_canceled')) {
      return SandboxSimulationException(SandboxSimulationFailure.timeout);
    }

    if (code == '55P03' ||
        code == 'lock_not_available' ||
        message.contains('already running')) {
      return SandboxSimulationException(
        SandboxSimulationFailure.concurrentLock,
      );
    }

    if (message.contains('10,000') || message.contains('10000')) {
      return SandboxSimulationException(
        SandboxSimulationFailure.eventLimitExceeded,
      );
    }

    if (message.contains('session quota') ||
        message.contains('quota exceeded')) {
      return SandboxSimulationException(
        SandboxSimulationFailure.sessionQuotaExceeded,
      );
    }

    if (message.contains('period cannot exceed')) {
      return SandboxSimulationException(SandboxSimulationFailure.periodTooLong);
    }

    if (message.contains('period_end must be after') ||
        (code == '22023' && message.contains('period'))) {
      return SandboxSimulationException(SandboxSimulationFailure.invalidPeriod);
    }

    // INV-26: not found / wrong org / RLS denial — same client shape
    if (code == 'PGRST116' ||
        code == 'P0002' ||
        code == 'no_data_found' ||
        code == '42501' ||
        message.contains('not_found')) {
      return SandboxSimulationException(
        SandboxSimulationFailure.contractNotFound,
      );
    }

    // Fail-closed: P0001 and unknown codes never rethrow raw PostgREST
    return const IntegrityException(
      'Não foi possível concluir a simulação. Verifique os parâmetros e tente novamente.',
    );
  }

  Map<String, String> _parseNestedPayload(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return const {};
    try {
      final decoded = json.decode(trimmed) as Map<String, dynamic>;
      return {
        'code': decoded['code']?.toString() ?? '',
        'message': decoded['message']?.toString() ?? raw,
      };
    } catch (_) {
      return {'message': raw};
    }
  }
}
