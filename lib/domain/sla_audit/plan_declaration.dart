import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'contractual_plan_declared_event.dart';
import 'contractual_service_execution.dart';
import 'domain_event.dart';
import 'domain_exception.dart';
import 'rule_snapshot.dart';

/// Aggregate Root representing the formal, immutable, and auditable
/// declaration of a contractual operational plan.
///
/// This is the source of truth for the SLA Auditor module.
///
/// **Immutability**: All fields are `final`. The [services] list is
/// exposed as an unmodifiable view. No setters, no mutation.
///
/// **Creation**: Use [PlanDeclaration.create] factory. Direct construction
/// is prohibited (private constructor).
///
/// **Domain events**: The aggregate emits a [ContractualPlanDeclaredEvent]
/// upon creation, accessible via [domainEvents].
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

  // ── Internal collections ──────────────────────────────────
  final List<ContractualServiceExecution> _services;
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
    required List<ContractualServiceExecution> services,
    required List<DomainEvent> domainEvents,
  }) : _services = services,
       _domainEvents = domainEvents;

  // ── Public read-only views ────────────────────────────────
  /// Unmodifiable view of the contractual service executions.
  List<ContractualServiceExecution> get services =>
      UnmodifiableListView(_services);

  /// Unmodifiable view of domain events emitted by this aggregate.
  List<DomainEvent> get domainEvents => UnmodifiableListView(_domainEvents);

  // ── Factory ───────────────────────────────────────────────
  /// Creates a new [PlanDeclaration] aggregate.
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
    // ── Validate invariants ─────────────────────────────────
    if (contractId.isEmpty) {
      throw const DomainException('contractId must not be empty');
    }
    if (declaredByUserId.isEmpty) {
      throw const DomainException('declaredByUserId must not be empty');
    }
    if (originalFileHash.isEmpty) {
      throw const DomainException('originalFileHash must not be empty');
    }
    if (services.isEmpty) {
      throw const DomainException('services must not be empty');
    }

    // ── Check for duplicate SETs ────────────────────────────
    final setIds = <String>{};
    for (final service in services) {
      if (!setIds.add(service.setId)) {
        throw DomainException(
          'Duplicate Service Execution Token detected: ${service.setId}',
        );
      }
    }

    // ── declaredAtUtc must not be in the future ─────────────
    if (declaredAtUtc.isAfter(DateTime.now().toUtc())) {
      throw const DomainException('declaredAtUtc must not be in the future');
    }

    // ── Generate identity ───────────────────────────────────
    final id = const Uuid().v4();

    // ── Emit domain event ───────────────────────────────────
    final event = ContractualPlanDeclaredEvent(
      organizationId: organizationId,
      occurredAtUtc: DateTime.now().toUtc(),
      planDeclarationId: id,
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
      domainEvents: [event],
    );
  }

  /// Reconstitutes a [PlanDeclaration] from persistence.
  ///
  /// This factory is used by infrastructure repositories to restore
  /// the aggregate state. It does NOT emit domain events.
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
      services: List.unmodifiable(services),
      domainEvents: const [], // RECONSTITUTION: No events emitted
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
    _services,
  ];
}
