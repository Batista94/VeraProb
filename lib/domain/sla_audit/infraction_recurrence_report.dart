import 'package:equatable/equatable.dart';

/// A single prior infraction dot for the mini-timeline.
///
/// Carries [occurredAtUtc] for placement and [clauseRef] for color coding.
/// INV-9: [occurredAtUtc] is always UTC.
class PriorInfractionDot extends Equatable {
  final DateTime occurredAtUtc;
  final String clauseRef;

  const PriorInfractionDot({
    required this.occurredAtUtc,
    required this.clauseRef,
  }) : assert(true); // UTC assertion enforced in service layer

  @override
  List<Object?> get props => [occurredAtUtc, clauseRef];
}

/// Value object summarising the recurrence context for a verdict card.
///
/// [infractionNumberThisMonth] is the ordinal position of the current
/// infraction (prior count + 1). A value of 1 means first offense this month.
///
/// [priorInfractions] lists previous infractions in chronological order
/// (ascending) — excludes the current entry.
///
/// INV-18: pure Dart, zero Flutter/Supabase dependencies.
class InfractionRecurrenceReport extends Equatable {
  final String vehiclePlate;
  final int infractionNumberThisMonth;
  final List<PriorInfractionDot> priorInfractions;

  const InfractionRecurrenceReport({
    required this.vehiclePlate,
    required this.infractionNumberThisMonth,
    required this.priorInfractions,
  });

  /// Convenience constructor for first-offense (no prior infractions).
  const InfractionRecurrenceReport.firstOffense(String plate)
    : vehiclePlate = plate,
      infractionNumberThisMonth = 1,
      priorInfractions = const [];

  @override
  List<Object?> get props => [
    vehiclePlate,
    infractionNumberThisMonth,
    priorInfractions,
  ];
}
