import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/alert_service.dart';
import '../../domain/sla_audit/operational_alert.dart';
import 'sla_providers.dart';

/// Provides active operational alerts for OCC triage.
/// Sorted by severity (CRITICAL first) then by time (most recent first).
final activeAlertsProvider = FutureProvider<List<OperationalAlert>>((
  ref,
) async {
  final repo = ref.watch(operationalAlertRepositoryProvider);
  // Organization ID will be injected from tenant context in production.
  // For now, fetch all active alerts across tenants in InMemory mode.
  return repo.findActive('');
});

/// Provides alerts for a specific entity (SET ID).
final entityAlertsProvider =
    FutureProvider.family<List<OperationalAlert>, String>((
      ref,
      entityId,
    ) async {
      final repo = ref.watch(operationalAlertRepositoryProvider);
      return repo.findByEntityId(entityId);
    });

/// Provides the AlertService for lifecycle transitions.
final alertServiceProvider = Provider<AlertService>((ref) {
  return AlertService(repo: ref.watch(operationalAlertRepositoryProvider));
});
