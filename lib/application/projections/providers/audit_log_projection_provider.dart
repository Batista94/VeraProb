import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/audit_log.dart';
import '../../../domain/enums/incident_lifecycle_status.dart';
import '../../audit/audit_service.dart';
import '../../../state/providers/fleet_providers.dart';
import '../../../domain/entities/operational_trip.dart';
import 'audit_filter_provider.dart';
import '../models/audit_log_projection.dart';

/// Provides a formatted, read-only projection of the Audit Logs.
/// Fetches the logs from the AuditService (acting as the persistent event store).
final auditLogProjectionProvider = FutureProvider<AuditLogProjection>((
  ref,
) async {
  // Fetch from the persistent/in-memory store.
  final auditService = ref.watch(auditServiceProvider);
  final rawLogs = await auditService.getRecentLogs(limit: 200);

  // 1. O(1) Lookup Map for Enrichment (Avoids nested iterative joins)
  final trips = ref.watch(enrichedTripsProvider);
  final lookupMap = <String, OperationalTrip>{};
  for (final trip in trips) {
    lookupMap[trip.id] = trip;
    if (trip.vehicleId != null) {
      lookupMap[trip.vehicleId!] = trip;
    }
  }

  // 2. Watch Filters
  final filters = ref.watch(auditFilterProvider);

  // 3. Filter the RAW logs before mapping
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

  // 4. Enrich and Map
  final projectionEntries = filteredLogs.map((log) {
    final category = _determineCategory(log.actionType);
    final details = _buildDetails(log);

    // OCC Density Lookup
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
      statusLabel: tripInfo?.status.label, // Using the enum's existing label
      lifecycleStatus: _determineLifecycleStatus(log.actionType),
    );
  }).toList();

  return AuditLogProjection(
    entries: projectionEntries,
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
