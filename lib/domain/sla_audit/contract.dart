import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'contract_events.dart';
import 'contract_status.dart';
import 'domain_event.dart';
import 'domain_exception.dart';

/// Aggregate Root representing a formal contractual agreement between
/// the operating organization and a contractor.
///
/// **Lifecycle:** `draft → active → closed`
/// - [draft]: created, awaiting first plan declaration.
/// - [active]: first plan declared — operational.
/// - [closed]: terminal — no further plans accepted.
///
/// **Immutability:** Core identity and organizational fields are final.
/// State transitions mutate only status and lifecycle timestamps,
/// always through explicit domain methods that emit events.
///
/// **Creation:** Use [Contract.create] factory.
/// **Reconstitution:** Use [Contract.reconstitute] factory (no events emitted).
///
/// **Invariants (non-negotiable):**
/// - [name] must not be empty.
/// - [contractorName] must not be empty.
/// - [organizationId] is set at creation and never changes.
/// - [validFromUtc] must be strictly before [validUntilUtc].
/// - A [closed] contract cannot receive new plans.
class Contract extends Equatable {
  // ── Identity ──────────────────────────────────────────────
  /// UUID v4 generated internally. Immutable.
  final String id;

  // ── Attributes ────────────────────────────────────────────
  final String organizationId;
  final String name;
  final String contractorName;
  final String? description;
  final DateTime validFromUtc;
  final DateTime validUntilUtc;

  // ── State ─────────────────────────────────────────────────
  final ContractStatus status;
  final DateTime createdAtUtc;
  final DateTime? activatedAtUtc;
  final DateTime? closedAtUtc;
  final String? closedByUserId;
  final String? closeReason;

  /// Audit field: UUID of the source contract when created via cloning.
  /// Null for contracts created directly. Immutable after creation.
  final String? clonedFromContractId;

  // ── Internal events ───────────────────────────────────────
  final List<DomainEvent> _domainEvents;

  // ── Private constructor ───────────────────────────────────
  // ignore: prefer_const_constructors_in_immutables
  Contract._({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.contractorName,
    this.description,
    required this.validFromUtc,
    required this.validUntilUtc,
    required this.status,
    required this.createdAtUtc,
    this.activatedAtUtc,
    this.closedAtUtc,
    this.closedByUserId,
    this.closeReason,
    this.clonedFromContractId,
    required List<DomainEvent> domainEvents,
  }) : _domainEvents = domainEvents;

  // ── Public read-only view of events ──────────────────────
  /// Unmodifiable view of domain events emitted by this aggregate instance.
  List<DomainEvent> get domainEvents => UnmodifiableListView(_domainEvents);

  // ── Factory: create ───────────────────────────────────────
  /// Creates a new [Contract] in [ContractStatus.draft].
  ///
  /// Validates all domain invariants synchronously.
  /// Generates a UUID v4 for identity.
  /// Emits a [ContractCreatedEvent].
  ///
  /// Throws [DomainException] if any invariant is violated.
  static Contract create({
    required String organizationId,
    required String name,
    required String contractorName,
    String? description,
    required DateTime validFromUtc,
    required DateTime validUntilUtc,
  }) {
    // ── Validate invariants ─────────────────────────────────
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (name.trim().isEmpty) {
      throw const DomainException('name must not be empty');
    }
    if (contractorName.trim().isEmpty) {
      throw const DomainException('contractorName must not be empty');
    }
    if (!validUntilUtc.isAfter(validFromUtc)) {
      throw const DomainException(
        'validUntilUtc must be strictly after validFromUtc',
      );
    }

    // ── Generate identity and timestamps ────────────────────
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();

    // ── Emit domain event ───────────────────────────────────
    final event = ContractCreatedEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      name: name,
      contractorName: contractorName,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
    );

    return Contract._(
      id: id,
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.draft,
      createdAtUtc: now,
      domainEvents: [event],
    );
  }

  // ── Factory: createClone ──────────────────────────────────
  /// Creates a new [Contract] draft as a clone of an existing contract.
  ///
  /// Identical to [create] but records [clonedFromContractId] as an
  /// immutable audit reference. The [organizationId] must come from the
  /// authenticated JWT — never from the source contract.
  ///
  /// Throws [DomainException] if any invariant is violated.
  static Contract createClone({
    required String organizationId,
    required String name,
    required String contractorName,
    String? description,
    required DateTime validFromUtc,
    required DateTime validUntilUtc,
    required String clonedFromContractId,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (name.trim().isEmpty) {
      throw const DomainException('name must not be empty');
    }
    if (contractorName.trim().isEmpty) {
      throw const DomainException('contractorName must not be empty');
    }
    if (!validUntilUtc.isAfter(validFromUtc)) {
      throw const DomainException(
        'validUntilUtc must be strictly after validFromUtc',
      );
    }

    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();

    final event = ContractCreatedEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      name: name,
      contractorName: contractorName,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
    );

    return Contract._(
      id: id,
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.draft,
      createdAtUtc: now,
      clonedFromContractId: clonedFromContractId,
      domainEvents: [event],
    );
  }

  // ── Factory: reconstitute ─────────────────────────────────
  /// Reconstitutes a [Contract] from persistence.
  ///
  /// Used by infrastructure repositories. Does NOT emit domain events.
  static Contract reconstitute({
    required String id,
    required String organizationId,
    required String name,
    required String contractorName,
    String? description,
    required DateTime validFromUtc,
    required DateTime validUntilUtc,
    required ContractStatus status,
    required DateTime createdAtUtc,
    DateTime? activatedAtUtc,
    DateTime? closedAtUtc,
    String? closedByUserId,
    String? closeReason,
    String? clonedFromContractId,
  }) {
    return Contract._(
      id: id,
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: status,
      createdAtUtc: createdAtUtc,
      activatedAtUtc: activatedAtUtc,
      closedAtUtc: closedAtUtc,
      closedByUserId: closedByUserId,
      closeReason: closeReason,
      clonedFromContractId: clonedFromContractId,
      domainEvents: const [], // RECONSTITUTION: no events emitted
    );
  }

  // ── State transitions ─────────────────────────────────────

  /// Transitions the contract from [draft] to [active].
  ///
  /// Called automatically by [DeclareContractualPlanHandler] when the
  /// first plan is declared. Returns a new [Contract] instance with
  /// updated status and a [ContractActivatedEvent] in [domainEvents].
  ///
  /// Throws [DomainException] if the contract is not in [draft].
  Contract activate() {
    if (status != ContractStatus.draft) {
      throw DomainException(
        'Cannot activate contract in status "$status". '
        'Only draft contracts can be activated.',
      );
    }

    final now = DateTime.now().toUtc();
    final event = ContractActivatedEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      activatedAtUtc: now,
    );

    return Contract._(
      id: id,
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.active,
      createdAtUtc: createdAtUtc,
      activatedAtUtc: now,
      closedAtUtc: closedAtUtc,
      closedByUserId: closedByUserId,
      closeReason: closeReason,
      domainEvents: [event],
    );
  }

  /// Transitions the contract from [active] to [closed].
  ///
  /// [closed] is a terminal state. The engine continues evaluating
  /// any pending SETs already declared — contract closure does not
  /// retroactively alter execution states.
  ///
  /// Returns a new [Contract] instance with updated status and a
  /// [ContractClosedEvent] in [domainEvents].
  ///
  /// Throws [DomainException] if the contract is already [closed],
  /// or if required fields are empty.
  Contract close({
    required String closedByUserId,
    required String reason,
  }) {
    if (status == ContractStatus.closed) {
      throw const DomainException(
        'Contract is already closed. Closed is a terminal state.',
      );
    }
    if (closedByUserId.trim().isEmpty) {
      throw const DomainException('closedByUserId must not be empty');
    }
    if (reason.trim().isEmpty) {
      throw const DomainException('reason must not be empty');
    }

    final now = DateTime.now().toUtc();
    final event = ContractClosedEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      closedAtUtc: now,
      closedByUserId: closedByUserId,
      reason: reason,
    );

    return Contract._(
      id: id,
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.closed,
      createdAtUtc: createdAtUtc,
      activatedAtUtc: activatedAtUtc,
      closedAtUtc: now,
      closedByUserId: closedByUserId,
      closeReason: reason,
      domainEvents: [event],
    );
  }

  // ── Convenience status checks ────────────────────────────

  /// Returns `true` if the contract is in [ContractStatus.draft].
  bool get isDraft => status == ContractStatus.draft;

  /// Returns `true` if the contract is in [ContractStatus.active].
  bool get isActive => status == ContractStatus.active;

  /// Returns `true` if the contract is in [ContractStatus.closed].
  bool get isClosed => status == ContractStatus.closed;

  // ── Guard methods ─────────────────────────────────────────

  /// Asserts that this contract can accept a new [PlanDeclaration].
  ///
  /// Called by [DeclareContractualPlanHandler] before creating a plan.
  /// Throws [DomainException] if the contract is [closed].
  void assertCanReceivePlan() {
    if (status == ContractStatus.closed) {
      throw DomainException(
        'Contract "$name" is closed and cannot receive new plans.',
      );
    }
  }

  // ── Equatable ─────────────────────────────────────────────
  @override
  List<Object?> get props => [
    id,
    organizationId,
    name,
    contractorName,
    description,
    validFromUtc,
    validUntilUtc,
    status,
    createdAtUtc,
    activatedAtUtc,
    closedAtUtc,
    closedByUserId,
    closeReason,
    clonedFromContractId,
  ];
}
