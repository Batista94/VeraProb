import 'handshake_result.dart';

/// Domain boundary for the reconnection handshake with Supabase.
///
/// On connection restoration the [LocalSyncOrchestrator] calls
/// [performHandshake] to discover which [CanonicalFact] records were
/// published while the OCC was offline, then enqueues only those missing
/// facts — minimising bandwidth and avoiding full re-sync.
///
/// **INV-1:** [organizationId] is always passed explicitly; never derived
///            from client-side state.
/// **INV-9:** [clientLastSeenAtUtc] must be UTC.
/// **INV-18:** Pure Dart interface — zero Flutter / Supabase dependencies.
abstract class SyncHandshakeService {
  /// Returns facts the client missed since [clientLastSeenAtUtc].
  ///
  /// [organizationId] scopes the query to the tenant (INV-1).
  /// [clientLastSeenAtUtc] is the [receivedAtUtc] of the last fact the OCC
  /// successfully acknowledged; pass [DateTime.fromMillisecondsSinceEpoch(0)]
  /// as the epoch sentinel on first run.
  Future<HandshakeResult> performHandshake({
    required String organizationId,
    required DateTime clientLastSeenAtUtc,
  });
}
