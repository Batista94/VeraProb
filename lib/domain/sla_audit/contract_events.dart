import 'domain_event.dart';

/// Emitted when a [Contract] aggregate is created (status: draft).
class ContractCreatedEvent extends DomainEvent {
  final String contractId;
  final String name;
  final String contractorName;
  final DateTime validFromUtc;
  final DateTime validUntilUtc;

  const ContractCreatedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.contractId,
    required this.name,
    required this.contractorName,
    required this.validFromUtc,
    required this.validUntilUtc,
  });
}

/// Emitted when a [Contract] transitions from [draft] to [active]
/// upon the first plan declaration.
class ContractActivatedEvent extends DomainEvent {
  final String contractId;
  final DateTime activatedAtUtc;

  const ContractActivatedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.contractId,
    required this.activatedAtUtc,
  });
}

/// Emitted when a [Contract] is formally closed (terminal state).
class ContractClosedEvent extends DomainEvent {
  final String contractId;
  final DateTime closedAtUtc;
  final String closedByUserId;
  final String reason;

  const ContractClosedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.contractId,
    required this.closedAtUtc,
    required this.closedByUserId,
    required this.reason,
  });
}

/// Emitted when a [Contract] is submitted for contractor approval.
/// Status transitions: draft → awaitingContractorAcceptance.
class ContractSubmittedForApprovalEvent extends DomainEvent {
  final String contractId;
  final String reviewToken;
  final DateTime submittedAtUtc;

  const ContractSubmittedForApprovalEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.contractId,
    required this.reviewToken,
    required this.submittedAtUtc,
  });
}

/// Emitted when a contractor accepts a contract via the review token link.
/// Status transitions: awaitingContractorAcceptance → active.
class ContractAcceptedByContractorEvent extends DomainEvent {
  final String contractId;
  final String reviewToken;
  final DateTime acceptedAtUtc;

  const ContractAcceptedByContractorEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.contractId,
    required this.reviewToken,
    required this.acceptedAtUtc,
  });
}
