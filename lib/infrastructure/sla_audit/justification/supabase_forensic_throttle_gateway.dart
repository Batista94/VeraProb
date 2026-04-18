/// Forensic Audit Signature: CX-05-v3.0 / Throttle / Infra
/// Security Guard: INV-1 (fail-fast), INV-2 (JWT RLS), INV-13 (port-bound),
///                 INV-16 (≤60 conn pool), INV-18 (zero-trust).
/// Authorized By: VeraProb QA Security + Senior Engineer
///
/// Supabase adapter for [ForensicThrottleGateway].
///
/// Delegates authority to three PL/pgSQL RPCs defined in migration
/// `20260418000002_forensic_throttle_state.sql`:
///   - `check_forensic_throttle(p_org_id)` → `(allowed, wait_seconds)`
///   - `record_forensic_failure(p_org_id)` → void
///   - `reset_forensic_throttle(p_org_id)` → void
///
/// All three RPCs execute `SECURITY INVOKER` with JWT-claim fail-fast and
/// RLS-protected state — a modified client cannot forge tenancy or bypass the
/// backoff horizon. The adapter only marshals arguments and surfaces the
/// `wait_seconds` verdict.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/justification/forensic_throttle_gateway.dart';

/// Supabase-backed [ForensicThrottleGateway] (INV-13).
class SupabaseForensicThrottleGateway implements ForensicThrottleGateway {
  final SupabaseClient _client;

  SupabaseForensicThrottleGateway(this._client);

  @override
  Future<void> assertAllowed({required String organizationId}) async {
    final response = await _client.rpc(
      'check_forensic_throttle',
      params: {'p_org_id': organizationId},
    );

    final row = _firstRow(response);
    if (row == null) {
      return;
    }

    final allowed = row['allowed'] as bool? ?? true;
    if (allowed) {
      return;
    }

    final waitSeconds = (row['wait_seconds'] as num?)?.toInt() ?? 0;
    throw ThrottleBlockedException(waitSeconds);
  }

  @override
  Future<void> recordFailure({required String organizationId}) async {
    await _client.rpc(
      'record_forensic_failure',
      params: {'p_org_id': organizationId},
    );
  }

  @override
  Future<void> recordSuccess({required String organizationId}) async {
    await _client.rpc(
      'reset_forensic_throttle',
      params: {'p_org_id': organizationId},
    );
  }

  Map<String, dynamic>? _firstRow(dynamic response) {
    if (response is List && response.isNotEmpty) {
      final first = response.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    return null;
  }
}
