import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/heartbeat_monitor_view.dart';
import '../../application/sla_audit/projections/heartbeat_query_service.dart';
import '../../domain/sla_audit/heartbeat_classifier.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/supabase_heartbeat_query_service.dart';

/// Provides the [HeartbeatQueryService] backed by Supabase.
final heartbeatQueryServiceProvider = Provider<HeartbeatQueryService>((ref) {
  return SupabaseHeartbeatQueryService(
    ref.watch(supabaseClientProvider),
    const HeartbeatClassifier(),
  );
});

/// Returns the fleet heartbeat health snapshot for [organizationId].
///
/// Scoped per org — use [FutureProvider.family] for the org parameter (INV-1).
final heartbeatMonitorProvider =
    FutureProvider.family<HeartbeatMonitorView, String>((
      ref,
      organizationId,
    ) async {
      final service = ref.watch(heartbeatQueryServiceProvider);
      return service.getHeartbeatMonitor(organizationId: organizationId);
    });
