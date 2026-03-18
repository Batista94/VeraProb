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
  }) {
    _validateCommon(
      contractId,
      declaredByUserId,
      originalFileHash,
      declaredAtUtc,
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
    final event = _buildEvent(
      organizationId: organizationId,
      id: id,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      totalServicesDeclared: services.length,
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
      domainEvents: [event],
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
  }) {
    _validateCommon(
      contractId,
      declaredByUserId,
      originalFileHash,
      declaredAtUtc,
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
    final event = _buildEvent(
      organizationId: organizationId,
      id: id,
      contractId: contractId,
      declaredAtUtc: declaredAtUtc,
      declaredByUserId: declaredByUserId,
      planVersion: planVersion,
      totalServicesDeclared: 0, // SETs projected post-creation
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
      domainEvents: [event],
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
      services: List.unmodifiable(services),
      shiftPatterns: List.unmodifiable(shiftPatterns),
      domainEvents: const [],
    );
  }

  // ── Private helpers ───────────────────────────────────────

  static void _validateCommon(
    String contractId,
    String declaredByUserId,
    String originalFileHash,
    DateTime declaredAtUtc,
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
    if (declaredAtUtc.isAfter(DateTime.now().toUtc())) {
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
  }) {
    return ContractualPlanDeclaredEvent(
      organizationId: organizationId,
      occurredAtUtc: DateTime.now().toUtc(),
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
    _services,
    _shiftPatterns,
  ];
}
