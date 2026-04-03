/// Nested dot representing a single prior infraction in the recurrence timeline.
class PriorInfractionDotView {
  final DateTime occurredAtUtc;
  final String clauseRef;

  const PriorInfractionDotView({
    required this.occurredAtUtc,
    required this.clauseRef,
  });
}

/// Read model for infraction recurrence tracking used in presentation layer.
class InfractionRecurrenceView {
  final String vehiclePlate;
  final int infractionNumberThisMonth;
  final List<PriorInfractionDotView> priorInfractions;

  const InfractionRecurrenceView({
    required this.vehiclePlate,
    required this.infractionNumberThisMonth,
    required this.priorInfractions,
  });

  /// Convenience factory for a vehicle with no prior infractions this month.
  factory InfractionRecurrenceView.firstOffense(String vehiclePlate) {
    return InfractionRecurrenceView(
      vehiclePlate: vehiclePlate,
      infractionNumberThisMonth: 1,
      priorInfractions: const [],
    );
  }
}
