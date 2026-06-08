import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

/// Service that logs security incidents via the `log-security-incident`
/// Edge Function RPC.
///
/// INV-30: Consumes Supabase client exclusively via [supabaseClientProvider].
/// INV-26: Logging failures are silently swallowed — the caller must never
/// learn whether the log succeeded or failed.
class SecurityIncidentLogger {
  final Ref? _ref;

  SecurityIncidentLogger(this._ref);

  /// Fires a `log-security-incident` RPC call.
  ///
  /// [eventType] — e.g. `SECURITY_VIOLATION_BYPASS_ATTEMPT`.
  /// [metadata] — JSONB with IP, User-Agent, route attempted, etc.
  /// [jwtClaimsSnapshot] — sanitized JWT claims for forensic record.
  ///
  /// Returns silently on any error (INV-26: no information leakage).
  Future<void> log({
    required String eventType,
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> jwtClaimsSnapshot,
  }) async {
    try {
      final client = _ref?.read(supabaseClientProvider);
      if (client == null) return;
      await client.functions.invoke(
        'log-security-incident',
        body: {
          'event_type': eventType,
          'metadata': {
            ...metadata,
            'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
          },
          'jwt_claims_snapshot': jwtClaimsSnapshot,
        },
      );
    } catch (e) {
      // Silent failure — INV-26: do not reveal logging status to caller.
      debugPrint('[SecurityIncidentLogger] Failed to log incident: $e');
    }
  }
}

/// Provider for [SecurityIncidentLogger].
///
/// INV-30: Client injected via supabaseClientProvider (no direct instantiation).
final securityIncidentLoggerProvider = Provider<SecurityIncidentLogger>((ref) {
  return SecurityIncidentLogger(ref);
});
