import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../../state/providers/fleet_providers.dart';
import '../models/timeline_projection.dart';

/// Provides a unified chronological timeline for a specific vehicle/trip.
/// Requires `.family` to be scoped to a specific trip ID.
final timelineProjectionProvider = Provider.family<TimelineProjection, String>((
  ref,
  tripId,
) {
  final enrichedTrips = ref.watch(enrichedTripsProvider);

  if (enrichedTrips.isEmpty) {
    return TimelineProjection(tripId: tripId, routeName: 'Desconhecida');
  }

  final trips = enrichedTrips;
  final trip = trips.firstWhereOrNull((t) => t.id == tripId);

  if (trip == null) {
    return TimelineProjection(tripId: tripId, routeName: 'Desconhecida');
  }

  // Combine normal events and operational warnings into nodes
  final nodes = <TimelineNode>[];

  // 1. Add standard mock trip start event
  nodes.add(
    TimelineNode(
      timestamp: trip.actualStart ?? trip.scheduledStart,
      title: 'VIAGEM INICIADA',
      description: 'Partida registrada no sistema',
      eventType: 'TRIP_START',
      isWarning: false,
    ),
  );

  // 2. Add operational warnings (from SituationEngine)
  for (final warning in trip.warnings) {
    nodes.add(
      TimelineNode(
        timestamp:
            warning.detectedAt, // Using detection time as the timeline point
        title: 'Aviso: ${warning.type}',
        description: warning.message,
        eventType: 'WARNING',
        isWarning: true,
      ),
    );
  }

  // 3. Sort chronologically (newest first, or oldest first depending on UI needs.
  // Let's go newest first for a "feed" style timeline).
  nodes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return TimelineProjection(
    tripId: trip.id,
    routeName: trip.routeShortName ?? 'Linha ${trip.routeId}',
    nodes: nodes,
  );
});
