/// Abstract base class for all domain events.
///
/// Domain events are identity-based, not value-based.
/// They represent facts that occurred within the domain.
/// They do NOT use Equatable — each event instance is unique.
abstract class DomainEvent {
  /// The Tenant / Organization ID where this event occurred.
  final String organizationId;

  /// The UTC timestamp when this event occurred.
  final DateTime occurredAtUtc;

  const DomainEvent({
    required this.organizationId,
    required this.occurredAtUtc,
  });
}
