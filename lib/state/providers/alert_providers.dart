import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/alert_service.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'sla_providers.dart';

import 'auth_providers.dart';

/// Provides active operational alerts for OCC triage.
/// Sorted by severity (CRITICAL first) then by time (most recent first).
final activeAlertsProvider = FutureProvider<List<OperationalAlert>>((
  ref,
) async {
  final repo = ref.watch(operationalAlertRepositoryProvider);
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return [];
  return repo.findActive(orgId);
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
