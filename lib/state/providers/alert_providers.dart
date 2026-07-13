import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/alert_service.dart';
import 'package:veraprob/application/sla_audit/quick_reconciliation_service.dart';
import 'package:veraprob/infrastructure/audio/alert_sound_service.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/telegram_providers.dart';
import 'sla_providers.dart';

import 'auth_providers.dart';

/// Real-time stream of active operational alerts via Supabase Realtime.
///
/// Uses Postgres Changes subscription on `operational_alerts` table.
/// Filters by organization_id and status='ACTIVE' client-side.
/// INV-1: Org-scoped via currentOrganizationIdProvider.
///
/// Overrides [updateShouldNotify] to always return `true` so that every
/// stream emission triggers a rebuild in listeners — even if the list is
/// equal by `==`. Real-time alerts must propagate immediately (Req 8.2).
final activeAlertsStreamProvider =
    StreamNotifierProvider.autoDispose<
      ActiveAlertsNotifier,
      List<OperationalAlert>
    >(ActiveAlertsNotifier.new);

/// StreamNotifier backing [activeAlertsStreamProvider].
///
/// Always notifies listeners on every emission to guarantee real-time
/// alert propagation regardless of equality.
class ActiveAlertsNotifier extends StreamNotifier<List<OperationalAlert>> {
  @override
  Stream<List<OperationalAlert>> build() {
    final client = ref.watch(supabaseClientProvider);
    final orgId = ref.watch(currentOrganizationIdProvider);
    if (orgId == null) return Stream.value([]);

    return client
        .from('operational_alerts')
        .stream(primaryKey: ['id'])
        .eq('organization_id', orgId)
        .order('severity')
        .order('triggered_at_utc', ascending: false)
        .map(
          (rows) =>
              rows.where((r) => r['status'] == 'ACTIVE').map(_fromRow).toList(),
        );
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<OperationalAlert>> previous,
    AsyncValue<List<OperationalAlert>> next,
  ) {
    // Always notify — real-time alerts must propagate immediately (Req 8.2)
    return true;
  }
}

/// Fallback: one-shot fetch of active alerts (for non-realtime contexts).
final activeAlertsProvider = FutureProvider<List<OperationalAlert>>((
  ref,
) async {
  final repo = ref.watch(operationalAlertRepositoryProvider);
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return [];
  return repo.findActive(orgId).withProviderTimeout();
});

/// Provides alerts for a specific entity (SET ID).
final entityAlertsProvider =
    FutureProvider.family<List<OperationalAlert>, String>((
      ref,
      entityId,
    ) async {
      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) return [];
      final repo = ref.watch(operationalAlertRepositoryProvider);
      return repo
          .findByEntityId(entityId, organizationId: organizationId)
          .withProviderTimeout();
    });

/// Provides the AlertService for lifecycle transitions.
final alertServiceProvider = Provider<AlertService>((ref) {
  return AlertService(repo: ref.watch(operationalAlertRepositoryProvider));
});

/// Provides the QuickReconciliationService for 1-click evidence linking.
final quickReconciliationServiceProvider = Provider<QuickReconciliationService>(
  (ref) {
    return QuickReconciliationService(
      alertRepo: ref.watch(operationalAlertRepositoryProvider),
      alertService: ref.watch(alertServiceProvider),
      telegramRepo: ref.watch(telegramRepositoryProvider),
      client: ref.watch(supabaseClientProvider),
      clock: ref.watch(dateTimeProviderProvider),
    );
  },
);

/// Industrial sound service for CRITICAL alert feedback.
/// autoDispose ensures AudioPlayer is released on logout/tab close.
final alertSoundServiceProvider = Provider.autoDispose<AlertSoundService>((
  ref,
) {
  final service = AlertSoundService();
  ref.onDispose(() => service.dispose());
  return service;
});

OperationalAlert _fromRow(Map<String, dynamic> row) {
  final viewedRaw = row['viewed_by_user_ids'];
  final viewedByUserIds = viewedRaw is List
      ? viewedRaw.cast<String>()
      : <String>[];

  return OperationalAlert(
    id: row['id'] as String,
    organizationId: row['organization_id'] as String,
    entityId: row['entity_id'] as String,
    contractId: row['contract_id'] as String,
    alertType: row['alert_type'] as String,
    severity: row['severity'] as String,
    triggeredAtUtc: DateTime.parse(row['triggered_at_utc'] as String),
    triggeringEventId: row['triggering_event_id'] as String?,
    traceId: row['trace_id'] as String?,
    context: Map<String, dynamic>.from(row['context'] as Map? ?? {}),
    status: row['status'] as String,
    acknowledgedAtUtc: row['acknowledged_at_utc'] != null
        ? DateTime.parse(row['acknowledged_at_utc'] as String)
        : null,
    acknowledgedByUserId: row['acknowledged_by_user_id'] as String?,
    resolvedAtUtc: row['resolved_at_utc'] != null
        ? DateTime.parse(row['resolved_at_utc'] as String)
        : null,
    viewedByUserIds: viewedByUserIds,
  );
}
