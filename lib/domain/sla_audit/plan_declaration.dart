import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'contractual_plan_declared_event.dart';
import 'contractual_service_execution.dart';
import 'domain_event.dart';
import 'domain_exception.dart';
import 'rule_snapshot.dart';
import 'shift_pattern.dart';
import 'week_cycle.dart';

/// Aggregate Root representing the formal, immutable, and auditable
/// declaration of a contractual operational plan.
///
/// This is the source of truth for the SLA Auditor module.
///
/// **Two declaration modes:**
/// - **Manual (baseline):** [services] is non-empty; [shiftPatterns] is empty.
///   Operator declares explicit SETs. Preserved for backwards compatibility.
/// - **B2B Projected:** [shiftPatterns] is non-empty; [services] starts empty.
///   [ShiftProjectionService] generates SETs from shift patterns + dates.
///
/// **Immutability**: All fields are `final`. Collections exposed as unmodifiable views.
/// **Domain events**: Emits [ContractualPlanDeclaredEvent] on creation.
class PlanDeclaration extends Equatable {
  // ── Identity ──────────────────────────────────────────────
  /// UUID v4 generated internally. Immutable. Never from external input.
  final String id;

  // ── Attributes ────────────────────────────────────────────
  final String organizationId;
  final String contractId;
  final DateTime declaredAtUtc;
  final String declaredByUserId;
  final int planVersion;
  final String originalFileHash;
  final RuleSnapshot ruleSnapshot;

  /// Anchor date for industrial week-cycle calculations.
  ///
  /// Non-null when any [ShiftPattern] in this plan has a [WeekCycle] other
  /// than [WeekCycle.everyWeek]. [ShiftProjectionService] uses this as the
  /// reference point for `weeksSinceAnchor % 4` filtering.
  ///
  /// Must be UTC (INV-3). Null for standard weekly plans.
  final DateTime? cycleAnchorDateUtc;

  // ── Forensic sealing (INV-34) ─────────────────────────────
  /// SHA-256 hash of the previous row state. 'GENESIS' on first insert.
  /// Null for rows that pre-date migration 20260415000000. Read-only —
  /// computed by the DB trigger `seal_plan_declarations_forensic`. NEVER
  /// sent in INSERT payloads.
  final String? previousHash;

  /// SHA-256(id|plan_version|organization_id|original_file_hash|previous_hash) in hex.
  /// Computed by the DB trigger. Null for pre-migration rows. Read-only —
  /// NEVER sent in INSERT payloads.
  final String? currentHash;

  // ── Internal collections ──────────────────────────────────
  final List<ContractualServiceExecution> _services;
  final List<ShiftPattern> _shiftPatterns;
  final List<DomainEvent> _domainEvents;

  // ── Private constructor ───────────────────────────────────
  // ignore: prefer_const_constructors_in_immutables
  PlanDeclaration._({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.declaredAtUtc,
    required this.declaredByUserId,
    required this.planVersion,
    required this.originalFileHash,
    required this.ruleSnapshot,
    this.cycleAnchorDateUtc,
    this.previousHash,
    this.currentHash,
    required List<ContractualServiceExecution> services,
    required List<ShiftPattern> shiftPatterns,
    required List<DomainEvent> domainEvents,
  }) : _services = services,
       _shiftPatterns = shiftPatterns,
       _domainEvents = domainEvents;

  // ── Public read-only views ────────────────────────────────
  /// Unmodifiable view of manually-declared service executions.
  /// Empty for B2B projected plans.
  List<ContractualServiceExecution> get services =>
      UnmodifiableListView(_services);

  /// Unmodifiable view of shift patterns.
  /// Empty for manually-declared (baseline) plans.
  List<ShiftPattern> get shiftPatterns => UnmodifiableListView(_shiftPatterns);

  /// Whether this plan uses [ShiftPattern]-based projection (B2B mode).
  bool get isShiftBased => _shiftPatterns.isNotEmpty;

  /// Unmodifiable view of domain events emitted by this aggregate.
  List<DomainEvent> get domainEvents => UnmodifiableListView(_domainEvents);

  // ── Factory: manual plan (baseline) ──────────────────────

  /// Creates a manually-declared [PlanDeclaration] with explicit SETs.
  ///
  /// Validates all domain invariants synchronously.
  /// Generates a UUID v4 for identity.
  /// Emits a [ContractualPlanDeclaredEvent].
  ///
  /// Throws [DomainException] if any invariant is violated.
  static PlanDeclaration create({
    required String organizationId,
    required String contractId,
    required DateTime declaredAtUtc,
    required String declaredByUserId,
    required int planVersion,
    required String originalFileHash,
    required RuleSnapshot ruleSnapshot,
    required List<ContractualServiceExecution> services,
    required DateTime nowUtc,
  }) {
    _validateCommon(
      contractId,
      declaredByUserId,
      originalFileHash,
      declaredAtUtc,
      nowUtc,
    );
    if (services.isEmpty) {
      throw const DomainException('services must not be empty');
    }

    final setIds = <String>{};
    for (final service in services) {
      if (!setIds.add(service.setId)) {
        throw DomainException(
          'Duplicate Service Execution Token detected: ${service.setId}',
        );
      }
    }

    final id = const Uuid().v4();
    final domainEvent = _buildEvent(
      organizationId: organizationId,
      id: id,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      totalServicesDeclared: services.length,
      nowUtc: nowUtc,
    );

    return PlanDeclaration._(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      originalFileHash: originalFileHash,
      ruleSnapshot: ruleSnapshot,
      services: List.unmodifiable(services),
      shiftPatterns: const [],
      domainEvents: [domainEvent],
    );
  }

  // ── Factory: B2B shift-pattern plan ──────────────────────

  /// Creates a B2B [PlanDeclaration] with [ShiftPattern] recurrence rules.
  ///
  /// [ShiftProjectionService] will generate [ContractualServiceExecution]
  /// instances from these patterns post-creation.
  ///
  /// Throws [DomainException] if any invariant is violated.
  static PlanDeclaration createWithShiftPatterns({
    required String organizationId,
    required String contractId,
    required DateTime declaredAtUtc,
    required String declaredByUserId,
    required int planVersion,
    required String originalFileHash,
    required RuleSnapshot ruleSnapshot,
    required List<ShiftPattern> shiftPatterns,
    DateTime? cycleAnchorDateUtc,
    required DateTime nowUtc,
  }) {
    _validateCommon(
      contractId,
      declaredByUserId,
      originalFileHash,
      declaredAtUtc,
      nowUtc,
    );
    if (shiftPatterns.isEmpty) {
      throw const DomainException('shiftPatterns must not be empty');
    }

    // Validate that pattern indices are sequential and unique
    final indices = shiftPatterns.map((p) => p.index).toSet();
    if (indices.length != shiftPatterns.length) {
      throw const DomainException(
        'ShiftPattern indices must be unique within a PlanDeclaration',
      );
    }

    // Validate: cycleAnchorDateUtc required when any pattern uses a non-weekly cycle
    final hasCycledPattern = shiftPatterns.any(
      (p) => p.weekCycle != WeekCycle.everyWeek,
    );
    if (hasCycledPattern && cycleAnchorDateUtc == null) {
      throw const DomainException(
        'cycleAnchorDateUtc is required when any ShiftPattern uses a non-weekly WeekCycle.',
      );
    }
    if (cycleAnchorDateUtc != null && !cycleAnchorDateUtc.isUtc) {
      throw const DomainException(
        'cycleAnchorDateUtc must be UTC (INV-3). Call .toUtc() before passing.',
      );
    }

    final id = const Uuid().v4();
    final domainEvent = _buildEvent(
      organizationId: organizationId,
      id: id,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      totalServicesDeclared: 0, // SETs projected post-creation
      nowUtc: nowUtc,
    );

    return PlanDeclaration._(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      originalFileHash: originalFileHash,
      ruleSnapshot: ruleSnapshot,
      cycleAnchorDateUtc: cycleAnchorDateUtc,
      services: const [],
      shiftPatterns: List.unmodifiable(shiftPatterns),
      domainEvents: [domainEvent],
    );
  }

  // ── Reconstitution ────────────────────────────────────────

  /// Reconstitutes a [PlanDeclaration] from persistence.
  /// Does NOT emit domain events.
  static PlanDeclaration reconstitute({
    required String id,
    required String organizationId,
    required String contractId,
    required DateTime declaredAtUtc,
    required String declaredByUserId,
    required int planVersion,
    required String originalFileHash,
    required RuleSnapshot ruleSnapshot,
    required List<ContractualServiceExecution> services,
    List<ShiftPattern> shiftPatterns = const [],
    DateTime? cycleAnchorDateUtc,
    String? previousHash,
    String? currentHash,
  }) {
    return PlanDeclaration._(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      originalFileHash: originalFileHash,
      ruleSnapshot: ruleSnapshot,
      cycleAnchorDateUtc: cycleAnchorDateUtc,
      previousHash: previousHash,
      currentHash: currentHash,
      services: List.unmodifiable(services),
      shiftPatterns: List.unmodifiable(shiftPatterns),
      domainEvents: const [],
    );
  }

  // ── copyWith ──────────────────────────────────────────────
  PlanDeclaration copyWith({
    String? id,
    String? organizationId,
    String? contractId,
    DateTime? declaredAtUtc,
    String? declaredByUserId,
    int? planVersion,
    String? originalFileHash,
    RuleSnapshot? ruleSnapshot,
    List<ContractualServiceExecution>? services,
    List<ShiftPattern>? shiftPatterns,
    DateTime? cycleAnchorDateUtc,
    String? previousHash,
    String? currentHash,
  }) {
    return PlanDeclaration._(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      contractId: contractId ?? this.contractId,
      declaredAtUtc: declaredAtUtc ?? this.declaredAtUtc,
      declaredByUserId: declaredByUserId ?? this.declaredByUserId,
      planVersion: planVersion ?? this.planVersion,
      originalFileHash: originalFileHash ?? this.originalFileHash,
      ruleSnapshot: ruleSnapshot ?? this.ruleSnapshot,
      cycleAnchorDateUtc: cycleAnchorDateUtc ?? this.cycleAnchorDateUtc,
      previousHash: previousHash ?? this.previousHash,
      currentHash: currentHash ?? this.currentHash,
      services: List.unmodifiable(services ?? _services),
      shiftPatterns: List.unmodifiable(shiftPatterns ?? _shiftPatterns),
      domainEvents: const [],
    );
  }

  // ── Private helpers ───────────────────────────────────────

  static void _validateCommon(
    String contractId,
    String declaredByUserId,
    String originalFileHash,
    DateTime declaredAtUtc,
    DateTime nowUtc,
  ) {
    if (contractId.isEmpty) {
      throw const DomainException('contractId must not be empty');
    }
    if (declaredByUserId.isEmpty) {
      throw const DomainException('declaredByUserId must not be empty');
    }
    if (originalFileHash.isEmpty) {
      throw const DomainException('originalFileHash must not be empty');
    }
    if (declaredAtUtc.isAfter(nowUtc)) {
      throw const DomainException('declaredAtUtc must not be in the future');
    }
  }

  static ContractualPlanDeclaredEvent _buildEvent({
    required String organizationId,
    required String id,
    required String contractId,
    required DateTime declaredAtUtc,
    required String declaredByUserId,
    required int planVersion,
    required int totalServicesDeclared,
    required DateTime nowUtc,
  }) {
    return ContractualPlanDeclaredEvent(
      organizationId: organizationId,
      occurredAtUtc: nowUtc,
      planDeclarationId: id,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      totalServicesDeclared: totalServicesDeclared,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    contractId,
    declaredAtUtc,
    declaredByUserId,
    planVersion,
    originalFileHash,
    ruleSnapshot,
    cycleAnchorDateUtc,
    previousHash,
    currentHash,
    _services,
    _shiftPatterns,
  ];
}
