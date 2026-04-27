import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/audit/audit_service.dart';
import 'package:veraprob/application/projections/models/audit_log_projection.dart';
import 'package:veraprob/application/projections/providers/audit_filter_provider.dart';
import 'package:veraprob/domain/entities/audit_log.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/enums/incident_lifecycle_status.dart';
import 'package:veraprob/infrastructure/audit/in_memory_audit_service.dart';
import 'package:veraprob/infrastructure/audit/postgres_audit_service.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

// ── Audit service (factory) ───────────────────────────────────────────────────

final auditServiceProvider = Provider<AuditService>((ref) {
  final mode = ref.watch(persistenceModeProvider);

  switch (mode) {
    case PersistenceMode.inMemory:
      return InMemoryAuditService(ref.watch(dateTimeProviderProvider));
    case PersistenceMode.postgres:
      final client = ref.watch(supabaseClientProvider);
      return PostgresAuditService(client, ref.watch(dateTimeProviderProvider));
  }
});

// ── Audit log projection ──────────────────────────────────────────────────────

final auditLogProjectionProvider = FutureProvider<AuditLogProjection>((
  ref,
) async {
  final auditService = ref.watch(auditServiceProvider);
  final rawLogs = await auditService.getRecentLogs(limit: 200);

  final trips = ref.watch(enrichedTripsProvider);
  final lookupMap = <String, OperationalTrip>{};
  for (final trip in trips) {
    lookupMap[trip.id] = trip;
    if (trip.vehicleId != null) {
      lookupMap[trip.vehicleId!] = trip;
    }
  }

  final filters = ref.watch(auditFilterProvider);

  var filteredLogs = rawLogs.where((log) {
    if (filters.startDate != null &&
        log.timestamp.isBefore(filters.startDate!)) {
      return false;
    }
    if (filters.endDate != null && log.timestamp.isAfter(filters.endDate!)) {
      return false;
    }
    final cat = _determineCategory(log.actionType);
    if (filters.category != null && cat != filters.category) {
      return false;
    }
    if (filters.entityId != null && log.entityId != filters.entityId) {
      return false;
    }
    if (filters.eventType != null && log.actionType != filters.eventType) {
      return false;
    }
    return true;
  }).toList();

  final projectionEntries = filteredLogs.map((log) {
    final category = _determineCategory(log.actionType);
    final details = _buildDetails(log);
    final tripInfo = lookupMap[log.entityId];

    return AuditLogEntry(
      id: log.id,
      timestamp: log.timestamp,
      action: log.actionType,
      actorId: log.operatorId,
      actorName: log.operatorId == 'SYSTEM' || log.operatorId.isEmpty
          ? 'Sistema'
          : 'Operador [${log.operatorId.length >= 4 ? log.operatorId.substring(0, 4) : log.operatorId}]',
      details: details,
      category: category,
      vehiclePlate: tripInfo?.vehiclePlate ?? tripInfo?.vehicleId,
      routeName: tripInfo?.routeShortName ?? tripInfo?.routeId,
      statusLabel: tripInfo?.status.label,
      lifecycleStatus: _determineLifecycleStatus(log.actionType),
    );
  }).toList();

  // Silent mode: show only exceptions (open/inProgress lifecycle)
  final displayEntries = filters.silentMode
      ? projectionEntries
            .where(
              (e) =>
                  e.lifecycleStatus == IncidentLifecycleStatus.open ||
                  e.lifecycleStatus == IncidentLifecycleStatus.inProgress,
            )
            .toList()
      : projectionEntries;

  return AuditLogProjection(
    entries: displayEntries,
    isLoading: false,
    hasMore: rawLogs.length == 200,
  );
});

String _determineCategory(String actionType) {
  if (actionType.contains('SYSTEM') || actionType.contains('AUTO')) {
    return 'SYSTEM';
  }
  return 'OPERATOR';
}

String? _buildDetails(AuditLog log) {
  if (log.reason != null && log.reason!.isNotEmpty) {
    return log.reason;
  }
  if (log.oldValue != null && log.newValue != null) {
    return 'Mudou de ${log.oldValue} para ${log.newValue}';
  }
  return 'Entidade: ${log.entityId}';
}

IncidentLifecycleStatus? _determineLifecycleStatus(String actionType) {
  final upper = actionType.toUpperCase();
  if (upper.contains('RESOLVED') ||
      upper.contains('CANCEL') ||
      upper.contains('MAINTENANCE')) {
    return IncidentLifecycleStatus.resolved;
  }
  if (upper.contains('ACKNOWLEDGE')) {
    return IncidentLifecycleStatus.acknowledged;
  }
  if (upper.contains('DELAY_CRITICAL') ||
      upper.contains('POS_LOST_CRITICAL') ||
      upper.contains('OFF_ROUTE_CRITICAL') ||
      upper.contains('CRITICAL')) {
    return IncidentLifecycleStatus.open;
  }
  if (upper.contains('DELAY') ||
      upper.contains('OFF_ROUTE') ||
      upper.contains('WARNING')) {
    return IncidentLifecycleStatus.inProgress;
  }
  return null;
}
