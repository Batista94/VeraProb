import 'package:veraprob/domain/enums/incident_lifecycle_status.dart';

/// A rigidly formatted audit log entry for the projection layer.
class AuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String action;
  final String actorId;
  final String? actorName;
  final String? details;
  final String category; // e.g., 'SYSTEM', 'OPERATOR'

  // Extended Fields for OCC Density via Projection Enrichment
  final String? vehiclePlate;
  final String? routeName;
  final String? statusLabel;
  final IncidentLifecycleStatus? lifecycleStatus;

  const AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.actorId,
    this.actorName,
    this.details,
    required this.category,
    this.vehiclePlate,
    this.routeName,
    this.statusLabel,
    this.lifecycleStatus,
  });
}

/// Contains paginated or filtered audit logs ready for the UI.
class AuditLogProjection {
  final List<AuditLogEntry> entries;
  final bool isLoading;
  final bool hasMore;

  const AuditLogProjection({
    this.entries = const [],
    this.isLoading = false,
    this.hasMore = false,
  });

  AuditLogProjection copyWith({
    List<AuditLogEntry>? entries,
    bool? isLoading,
    bool? hasMore,
  }) {
    return AuditLogProjection(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}
