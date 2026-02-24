/// Represents a single unified chronological node for a vehicle's timeline.
class TimelineNode {
  final DateTime timestamp;
  final String title;
  final String description;
  final String? eventType; // Optional: raw type if needed for icons
  final bool isWarning;

  const TimelineNode({
    required this.timestamp,
    required this.title,
    required this.description,
    this.eventType,
    this.isWarning = false,
  });
}

/// A structured timeline projection for a specific trip/vehicle.
/// Groups events and warnings into a single chronological view.
class TimelineProjection {
  final String tripId;
  final String routeName;
  final List<TimelineNode> nodes;

  const TimelineProjection({
    required this.tripId,
    required this.routeName,
    this.nodes = const [],
  });

  bool get hasEvents => nodes.isNotEmpty;

  TimelineProjection copyWith({
    String? tripId,
    String? routeName,
    List<TimelineNode>? nodes,
  }) {
    return TimelineProjection(
      tripId: tripId ?? this.tripId,
      routeName: routeName ?? this.routeName,
      nodes: nodes ?? this.nodes,
    );
  }
}
