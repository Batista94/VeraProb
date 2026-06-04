import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'contract_events.dart';
import 'contract_status.dart';
import 'domain_event.dart';
import 'domain_exception.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Aggregate Root representing a formal contractual agreement between
/// the operating organization and a contractor.
///
/// **Lifecycle:** `draft → awaitingContractorAcceptance → active → closed`
/// - [draft]: created, awaiting submission or plan declaration.
/// - [awaitingContractorAcceptance]: submitted for contractor review via token.
/// - [active]: contractor accepted (or plan declared directly from draft).
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
/// - A [awaitingContractorAcceptance] contract cannot receive new plans.
class Contract extends Equatable {
  // ── Identity ──────────────────────────────────────────────
  /// UUID v4 generated internally. Immutable.
  final String id;

  /// Optimistic locking version counter. Auto-incremented on each UPDATE.
  /// Used to detect concurrent modifications (Lost Update prevention).
  /// New aggregates start at version 1.
  final int version;

  // ── Attributes ────────────────────────────────────────────
  final String organizationId;
  final String name;
  final String contractorName;

  /// FK → public.contractors(id). Formal link to the organization's client
  /// (contractor). Nullable during the normalization rollout — legacy rows and
  /// new drafts may still rely on the denormalized [contractorName] until the
  /// contractor is formally selected (migration 20260806000001).
  final String? contractorId;

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

  /// Timestamp when the contract was submitted for contractor approval.
  /// Null until [submitForApproval] is called. (INV-3: UTC)
  final DateTime? submittedForApprovalAtUtc;

  /// Audit field: UUID of the source contract when created via cloning.
  /// Null for contracts created directly. Immutable after creation.
  final String? clonedFromContractId;

  /// Maximum cumulative penalty cap for this contract (INV-2: BIGINT cents).
  ///
  /// When set, [ContractualFinancialImpactQueryService] computes
  /// `marginErosionPercent = totalPenalties / financialCeiling × 100`.
  /// Null = no cap defined.
  final Money? financialCeiling;

  /// Multiplier applied to penalties (INV-19: BPS precision).
  ///
  /// Example: 1.75x -> 17500 BPS.
  /// Formula: `penalty = (base_penalty * penaltyMultiplierBps + 5000) ~/ 10000`
  /// (Symmetric Rounding — prevents cumulative drift from truncation).
  final int penaltyMultiplierBps;

  // ── Coordinates ───────────────────────────────────────────
  /// Optional geographic coordinates for this contract's primary location.
  /// **INV:** Always use `double` for physical metrics.
  final double? latitude; // Physical Metric - Double Required
  final double? longitude; // Physical Metric - Double Required

  // ── Forensic sealing (INV-34) ─────────────────────────────
  /// SHA-256 hash of the previous row state. 'GENESIS' on first insert.
  /// Null for rows that pre-date migration 20260415000000. Read-only —
  /// computed by the DB trigger `seal_contracts_forensic`. NEVER sent
  /// in INSERT/UPDATE payloads.
  final String? previousHash;

  /// SHA-256(id|version|status|organization_id|previous_hash) in hex.
  /// Computed by the DB trigger. Null for pre-migration rows not yet updated.
  /// Read-only — NEVER sent in INSERT/UPDATE payloads.
  final String? currentHash;

  // ── Internal events ───────────────────────────────────────
  final List<DomainEvent> _domainEvents;

  // ── Private constructor ───────────────────────────────────
  // ignore: prefer_const_constructors_in_immutables
  Contract._({
    required this.id,
    required this.version,
    required this.organizationId,
    required this.name,
    required this.contractorName,
    this.contractorId,
    this.description,
    required this.validFromUtc,
    required this.validUntilUtc,
    required this.status,
    required this.createdAtUtc,
    this.activatedAtUtc,
    this.closedAtUtc,
    this.closedByUserId,
    this.closeReason,
    this.submittedForApprovalAtUtc,
    this.clonedFromContractId,
    this.financialCeiling,
    required this.penaltyMultiplierBps,
    this.latitude,
    this.longitude,
    this.previousHash,
    this.currentHash,
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
    Money? financialCeiling,
    int penaltyMultiplierBps = 10000,
    double? latitude, // Physical Metric - Double Required
    double? longitude, // Physical Metric - Double Required
    required DateTime nowUtc,
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
    final now = nowUtc;

    // ── Emit domain factEvent ───────────────────────────────────
    final domainEvent = ContractCreatedEvent(
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
      version: 1, // New aggregate starts at version 1
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.draft,
      createdAtUtc: now,
      financialCeiling: financialCeiling,
      penaltyMultiplierBps: penaltyMultiplierBps,
      latitude: latitude,
      longitude: longitude,
      domainEvents: [domainEvent],
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
    int penaltyMultiplierBps = 10000,
    double? latitude, // Physical Metric - Double Required
    double? longitude, // Physical Metric - Double Required
    required DateTime nowUtc,
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
    final now = nowUtc;

    final domainEvent = ContractCreatedEvent(
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
      version: 1, // Cloned aggregate starts at version 1
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.draft,
      createdAtUtc: now,
      clonedFromContractId: clonedFromContractId,
      penaltyMultiplierBps: penaltyMultiplierBps,
      latitude: latitude,
      longitude: longitude,
      domainEvents: [domainEvent],
    );
  }

  // ── Factory: reconstitute ─────────────────────────────────
  /// Reconstitutes a [Contract] from persistence.
  ///
  /// Used by infrastructure repositories. Does NOT emit domain events.
  static Contract reconstitute({
    required String id,
    required int version,
    required String organizationId,
    required String name,
    required String contractorName,
    String? contractorId,
    String? description,
    required DateTime validFromUtc,
    required DateTime validUntilUtc,
    required ContractStatus status,
    required DateTime createdAtUtc,
    DateTime? activatedAtUtc,
    DateTime? closedAtUtc,
    String? closedByUserId,
    String? closeReason,
    DateTime? submittedForApprovalAtUtc,
    String? clonedFromContractId,
    Money? financialCeiling,
    required int penaltyMultiplierBps,
    double? latitude, // Physical Metric - Double Required
    double? longitude, // Physical Metric - Double Required
    String? previousHash,
    String? currentHash,
  }) {
    return Contract._(
      id: id,
      version: version,
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      contractorId: contractorId,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: status,
      createdAtUtc: createdAtUtc,
      activatedAtUtc: activatedAtUtc,
      closedAtUtc: closedAtUtc,
      closedByUserId: closedByUserId,
      closeReason: closeReason,
      submittedForApprovalAtUtc: submittedForApprovalAtUtc,
      clonedFromContractId: clonedFromContractId,
      financialCeiling: financialCeiling,
      penaltyMultiplierBps: penaltyMultiplierBps,
      latitude: latitude,
      longitude: longitude,
      previousHash: previousHash,
      currentHash: currentHash,
      domainEvents: const [], // RECONSTITUTION: no events emitted
    );
  }

  // ── copyWith ──────────────────────────────────────────────
  Contract copyWith({
    String? id,
    int? version,
    String? organizationId,
    String? name,
    String? contractorName,
    String? contractorId,
    String? description,
    DateTime? validFromUtc,
    DateTime? validUntilUtc,
    ContractStatus? status,
    DateTime? createdAtUtc,
    DateTime? activatedAtUtc,
    DateTime? closedAtUtc,
    String? closedByUserId,
    String? closeReason,
    DateTime? submittedForApprovalAtUtc,
    String? clonedFromContractId,
    Money? financialCeiling,
    int? penaltyMultiplierBps,
    double? latitude, // Physical Metric - Double Required
    double? longitude, // Physical Metric - Double Required
    String? previousHash,
    String? currentHash,
  }) {
    return Contract._(
      id: id ?? this.id,
      version: version ?? this.version,
      organizationId: organizationId ?? this.organizationId,
      name: name ?? this.name,
      contractorName: contractorName ?? this.contractorName,
      contractorId: contractorId ?? this.contractorId,
      description: description ?? this.description,
      validFromUtc: validFromUtc ?? this.validFromUtc,
      validUntilUtc: validUntilUtc ?? this.validUntilUtc,
      status: status ?? this.status,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      activatedAtUtc: activatedAtUtc ?? this.activatedAtUtc,
      closedAtUtc: closedAtUtc ?? this.closedAtUtc,
      closedByUserId: closedByUserId ?? this.closedByUserId,
      closeReason: closeReason ?? this.closeReason,
      submittedForApprovalAtUtc:
          submittedForApprovalAtUtc ?? this.submittedForApprovalAtUtc,
      clonedFromContractId: clonedFromContractId ?? this.clonedFromContractId,
      financialCeiling: financialCeiling ?? this.financialCeiling,
      penaltyMultiplierBps: penaltyMultiplierBps ?? this.penaltyMultiplierBps,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      previousHash: previousHash ?? this.previousHash,
      currentHash: currentHash ?? this.currentHash,
      domainEvents: const [],
    );
  }

  // ── State transitions ─────────────────────────────────────

  /// Transitions the contract from [draft] to [awaitingContractorAcceptance].
  ///
  /// Called by [SubmitContractForApprovalHandler]. Returns a new [Contract]
  /// instance with updated status and a [ContractSubmittedForApprovalEvent]
  /// in [domainEvents].
  ///
  /// Throws [DomainException] if the contract is not in [draft].
  Contract submitForApproval({
    required String reviewToken,
    required DateTime nowUtc,
  }) {
    if (status != ContractStatus.draft) {
      throw DomainException(
        'Cannot submit contract in status "$status" for approval. '
        'Only draft contracts can be submitted.',
      );
    }

    final now = nowUtc;
    final domainEvent = ContractSubmittedForApprovalEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      reviewToken: reviewToken,
      submittedAtUtc: now,
    );

    return Contract._(
      id: id,
      version: version, // Version preserved — incremented by DB trigger on save
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      contractorId: contractorId,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.awaitingContractorAcceptance,
      createdAtUtc: createdAtUtc,
      submittedForApprovalAtUtc: now,
      clonedFromContractId: clonedFromContractId,
      financialCeiling: financialCeiling,
      penaltyMultiplierBps: penaltyMultiplierBps,
      latitude: latitude,
      longitude: longitude,
      domainEvents: [domainEvent],
    );
  }

  /// Transitions the contract from [awaitingContractorAcceptance] to [active].
  ///
  /// Called by [AcceptByContractorHandler] after the contractor accepts via
  /// the public review link. Token possession is the authorization.
  ///
  /// Returns a new [Contract] instance with updated status and a
  /// [ContractAcceptedByContractorEvent] in [domainEvents].
  ///
  /// Throws [DomainException] if status is not [awaitingContractorAcceptance].
  Contract acceptByContractor({
    required String reviewToken,
    required DateTime nowUtc,
  }) {
    if (status != ContractStatus.awaitingContractorAcceptance) {
      throw DomainException(
        'Cannot accept contract in status "$status". '
        'Only contracts awaiting contractor acceptance can be accepted.',
      );
    }

    final now = nowUtc;
    final domainEvent = ContractAcceptedByContractorEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      reviewToken: reviewToken,
      acceptedAtUtc: now,
    );

    return Contract._(
      id: id,
      version: version, // Version preserved — incremented by DB trigger on save
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      contractorId: contractorId,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.active,
      createdAtUtc: createdAtUtc,
      activatedAtUtc: now,
      submittedForApprovalAtUtc: submittedForApprovalAtUtc,
      clonedFromContractId: clonedFromContractId,
      financialCeiling: financialCeiling,
      penaltyMultiplierBps: penaltyMultiplierBps,
      latitude: latitude,
      longitude: longitude,
      domainEvents: [domainEvent],
    );
  }

  /// Transitions the contract from [draft] to [active].
  ///
  /// Called automatically by [DeclareContractualPlanHandler] when the
  /// first plan is declared on a draft contract (fast-path: no approval
  /// flow required). Returns a new [Contract] instance with updated status
  /// and a [ContractActivatedEvent] in [domainEvents].
  ///
  /// Throws [DomainException] if the contract is not in [draft].
  Contract activate({required DateTime nowUtc}) {
    if (status != ContractStatus.draft) {
      throw DomainException(
        'Cannot activate contract in status "$status". '
        'Only draft contracts can be activated via plan declaration. '
        'Contracts awaiting acceptance must go through acceptByContractor().',
      );
    }

    final now = nowUtc;
    final domainEvent = ContractActivatedEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      activatedAtUtc: now,
    );

    return Contract._(
      id: id,
      version: version, // Version preserved — incremented by DB trigger on save
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      contractorId: contractorId,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.active,
      createdAtUtc: createdAtUtc,
      activatedAtUtc: now,
      closedAtUtc: closedAtUtc,
      closedByUserId: closedByUserId,
      closeReason: closeReason,
      submittedForApprovalAtUtc: submittedForApprovalAtUtc,
      clonedFromContractId: clonedFromContractId,
      financialCeiling: financialCeiling,
      penaltyMultiplierBps: penaltyMultiplierBps,
      latitude: latitude,
      longitude: longitude,
      domainEvents: [domainEvent],
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
    required DateTime nowUtc,
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

    final now = nowUtc;
    final domainEvent = ContractClosedEvent(
      organizationId: organizationId,
      occurredAtUtc: now,
      contractId: id,
      closedAtUtc: now,
      closedByUserId: closedByUserId,
      reason: reason,
    );

    return Contract._(
      id: id,
      version: version, // Version preserved — incremented by DB trigger on save
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      contractorId: contractorId,
      description: description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      status: ContractStatus.closed,
      createdAtUtc: createdAtUtc,
      activatedAtUtc: activatedAtUtc,
      closedAtUtc: now,
      closedByUserId: closedByUserId,
      closeReason: reason,
      submittedForApprovalAtUtc: submittedForApprovalAtUtc,
      clonedFromContractId: clonedFromContractId,
      financialCeiling: financialCeiling,
      penaltyMultiplierBps: penaltyMultiplierBps,
      latitude: latitude,
      longitude: longitude,
      domainEvents: [domainEvent],
    );
  }

  // ── Convenience status checks ────────────────────────────

  /// Returns `true` if the contract is in [ContractStatus.draft].
  bool get isDraft => status == ContractStatus.draft;

  /// Returns `true` if the contract is in [ContractStatus.active].
  bool get isActive => status == ContractStatus.active;

  /// Returns `true` if the contract is in [ContractStatus.closed].
  bool get isClosed => status == ContractStatus.closed;

  /// Returns `true` if awaiting contractor acceptance.
  bool get isAwaitingAcceptance =>
      status == ContractStatus.awaitingContractorAcceptance;

  // ── Guard methods ─────────────────────────────────────────

  /// Asserts that this contract can accept a new [PlanDeclaration].
  ///
  /// Called by [DeclareContractualPlanHandler] before creating a plan.
  /// Throws [DomainException] if the contract is [closed] or
  /// [awaitingContractorAcceptance] (must be accepted first).
  void assertCanReceivePlan() {
    if (status == ContractStatus.closed) {
      throw DomainException(
        'Contract "$name" is closed and cannot receive new plans.',
      );
    }
    if (status == ContractStatus.awaitingContractorAcceptance) {
      throw DomainException(
        'Contract "$name" is awaiting contractor acceptance '
        'and cannot receive new plans until accepted.',
      );
    }
  }

  // ── Equatable ─────────────────────────────────────────────
  @override
  List<Object?> get props => [
    id,
    version,
    organizationId,
    name,
    contractorName,
    contractorId,
    description,
    validFromUtc,
    validUntilUtc,
    status,
    createdAtUtc,
    activatedAtUtc,
    closedAtUtc,
    closedByUserId,
    closeReason,
    submittedForApprovalAtUtc,
    clonedFromContractId,
    financialCeiling,
    penaltyMultiplierBps,
    latitude,
    longitude,
    previousHash,
    currentHash,
  ];
}
