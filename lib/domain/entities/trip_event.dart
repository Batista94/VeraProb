import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

/// An immutable audit record of an operational factEvent.
///
/// TripEvents form an append-only log that provides complete auditability
/// of every state change in the system. They are never updated or deleted.
class TripEvent extends Equatable {
  final String id;
  final String tripId;
  final EventType eventType;
  final TripStatus? fromStatus;
  final TripStatus? toStatus;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const TripEvent({
    required this.id,
    required this.tripId,
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    this.metadata,
    required this.createdAt,
  });

  /// Human-readable summary of this factEvent
  String get summary {
    switch (eventType) {
      case EventType.statusChange:
        return '${fromStatus?.label ?? "?"} → ${toStatus?.label ?? "?"}';
      case EventType.delayDetected:
        final minutes = metadata?['delay_seconds'] as int? ?? 0;
        return 'Atraso de ${minutes ~/ 60} min detectado';
      case EventType.delayRecovered:
        return 'Atraso recuperado';
      case EventType.positionLost:
        return 'Sinal GPS perdido';
      case EventType.positionRestored:
        return 'Sinal GPS restaurado';
      case EventType.driverAssigned:
        return 'Motorista: ${metadata?['driver_name'] ?? 'N/A'}';
      case EventType.vehicleAssigned:
        return 'Veículo: ${metadata?['vehicle_plate'] ?? 'N/A'}';
      case EventType.feedDisconnected:
        return 'Feed ${metadata?['feed_name'] ?? ''} desconectado';
      case EventType.feedReconnected:
        return 'Feed ${metadata?['feed_name'] ?? ''} reconectado';
      case EventType.manualOverride:
        return 'Alteração manual: ${metadata?['reason'] ?? 'N/A'}';
    }
  }

  factory TripEvent.fromJson(Map<String, dynamic> json) {
    return TripEvent(
      id: json['id'].toString(),
      tripId: json['trip_id'] as String,
      eventType: EventType.fromString(json['event_type'] as String),
      fromStatus: json['from_status'] != null
          ? TripStatus.fromString(json['from_status'] as String)
          : null,
      toStatus: json['to_status'] != null
          ? TripStatus.fromString(json['to_status'] as String)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trip_id': tripId,
      'event_type': eventType.dbValue,
      'from_status': fromStatus?.dbValue,
      'to_status': toStatus?.dbValue,
      'metadata': metadata,
    };
  }

  @override
  List<Object?> get props => [
    id,
    tripId,
    eventType,
    fromStatus,
    toStatus,
    createdAt,
  ];
}
