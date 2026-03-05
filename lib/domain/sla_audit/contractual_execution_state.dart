import 'dart:collection';

import 'package:uuid/uuid.dart';

import 'domain_event.dart';
import 'domain_exception.dart';
import 'execution_events.dart';
import 'execution_status.dart';

/// Aggregate Root tracking the lifecycle and judgment of a single
/// contractual service execution obligation.
///
/// Unlike [PlanDeclaration] (immutable), this aggregate is **mutable** —
/// it transitions through states as the evaluation engine processes
/// telemetry evidence.
///
/// **Identity**: Equality is based exclusively on [id].
/// Does NOT use Equatable (mutable entity).
///
/// **Creation**: Use [ContractualExecutionState.create]. Direct
/// construction is prohibited (private constructor).
///
/// **State machine**:
/// ```
/// pending → executed   (via bindExecution)
/// pending → noShow     (via markNoShow, only after window expires)
/// pending → evidenceGap (via markEvidenceGap)
/// ```
/// All non-pending states are **final** — no further transitions allowed.
class ContractualExecutionState {
  // ── Identity ──────────────────────────────────────────────
  final String id;
  final String organizationId;
  final String setId;
  final String contractId;
  final int planVersion;

  // ── Geofence (denormalized from ContractualServiceExecution) ───
  /// Start geofence center latitude. Immutable after creation.
  final double startLatitude;

  /// Start geofence center longitude. Immutable after creation.
  final double startLongitude;

  /// Start geofence radius in meters. Immutable after creation.
  final int startRadiusMeters;

  // ── Vehicle Planning ──────────────────────────────────────────
  /// Planned vehicle for this obligation. Null means any vehicle can fulfill it.
  final String? plannedVehicleId;

  // ── Financial ─────────────────────────────────────────────
  /// Contractual value of this service obligation.
  final double contractualValue;

  /// Multiplier applied to contractualValue on NoShow. >= 1.0.
  final double noShowPenaltyMultiplier;

  // ── Time Window ───────────────────────────────────────────
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;

  // ── Status ────────────────────────────────────────────────
  ExecutionStatus _status;
  ExecutionStatus get status => _status;

  // ── Binding Evidence (only when executed) ─────────────────
  String? _boundVehicleId;
  DateTime? _bindingTimestampUtc;
  double? _bindingLatitude;
  double? _bindingLongitude;

  String? get boundVehicleId => _boundVehicleId;
  DateTime? get bindingTimestampUtc => _bindingTimestampUtc;
  double? get bindingLatitude => _bindingLatitude;
  double? get bindingLongitude => _bindingLongitude;

  // ── Lifecycle Timestamps ──────────────────────────────────
  final DateTime createdAtUtc;
  DateTime _lastEvaluatedAtUtc;
  DateTime _statusLastUpdatedAtUtc;
  DateTime? _finalizedAtUtc;

  DateTime get lastEvaluatedAtUtc => _lastEvaluatedAtUtc;
  DateTime get statusLastUpdatedAtUtc => _statusLastUpdatedAtUtc;
  DateTime? get finalizedAtUtc => _finalizedAtUtc;

  // ── Domain Events ─────────────────────────────────────────
  final List<DomainEvent> _domainEvents = [];
  List<DomainEvent> get domainEvents => UnmodifiableListView(_domainEvents);

  // ── Private Constructor ───────────────────────────────────
  ContractualExecutionState._({
    required this.id,
    required this.organizationId,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.startLatitude,
    required this.startLongitude,
    required this.startRadiusMeters,
    this.plannedVehicleId,
    required this.contractualValue,
    required this.noShowPenaltyMultiplier,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required ExecutionStatus status,
    required this.createdAtUtc,
    required DateTime lastEvaluatedAtUtc,
    required DateTime statusLastUpdatedAtUtc,
  }) : _status = status,
       _lastEvaluatedAtUtc = lastEvaluatedAtUtc,
       _statusLastUpdatedAtUtc = statusLastUpdatedAtUtc;

  // ── Factory ───────────────────────────────────────────────
  /// Creates a new [ContractualExecutionState] in [ExecutionStatus.pending].
  ///
  /// Validates the time window invariant.
  /// Generates a UUID v4 for identity.
  /// No binding fields are set at creation.
  ///
  /// Throws [DomainException] if [windowEndUtc] is not after [windowStartUtc].
  static ContractualExecutionState create({
    required String organizationId,
    required String setId,
    required String contractId,
    required int planVersion,
    required double startLatitude,
    required double startLongitude,
    required int startRadiusMeters,
    String? plannedVehicleId,
    required double contractualValue,
    required double noShowPenaltyMultiplier,
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
  }) {
    if (!windowEndUtc.isAfter(windowStartUtc)) {
      throw const DomainException(
        'windowEndUtc must be strictly after windowStartUtc',
      );
    }

    if (contractualValue <= 0) {
      throw const DomainException('contractualValue must be greater than 0');
    }

    if (noShowPenaltyMultiplier < 1.0) {
      throw const DomainException('noShowPenaltyMultiplier must be >= 1.0');
    }

    final now = DateTime.now().toUtc();

    return ContractualExecutionState._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      setId: setId,
      contractId: contractId,
      planVersion: planVersion,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      startRadiusMeters: startRadiusMeters,
      plannedVehicleId: plannedVehicleId,
      contractualValue: contractualValue,
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
      windowStartUtc: windowStartUtc,
      windowEndUtc: windowEndUtc,
      status: ExecutionStatus.pending,
      createdAtUtc: now,
      lastEvaluatedAtUtc: now,
      statusLastUpdatedAtUtc: now,
    );
  }

  // ── State Transitions ─────────────────────────────────────

  /// Binds a vehicle to this obligation, marking it as [ExecutionStatus.executed].
  ///
  /// Allowed only when [status] == [ExecutionStatus.pending].
  /// Throws [DomainException] if the transition is invalid.
  void bindExecution({
    required String vehicleId,
    required double latitude,
    required double longitude,
    required DateTime timestampUtc,
  }) {
    _assertPending('bindExecution');

    _status = ExecutionStatus.executed;
    _boundVehicleId = vehicleId;
    _bindingTimestampUtc = timestampUtc;
    _bindingLatitude = latitude;
    _bindingLongitude = longitude;
    _lastEvaluatedAtUtc = timestampUtc;
    _statusLastUpdatedAtUtc = timestampUtc;
    _finalizedAtUtc = timestampUtc;

    _domainEvents.add(
      ExecutionBoundEvent(
        organizationId: organizationId,
        occurredAtUtc: timestampUtc,
        setId: setId,
        contractId: contractId,
        planVersion: planVersion,
        vehicleId: vehicleId,
        bindingTimestampUtc: timestampUtc,
        bindingLatitude: latitude,
        bindingLongitude: longitude,
      ),
    );
  }

  /// Marks this obligation as [ExecutionStatus.noShow].
  ///
  /// Allowed only when:
  /// - [status] == [ExecutionStatus.pending]
  /// - [nowUtc] is after [windowEndUtc] (window has expired)
  ///
  /// Throws [DomainException] if the transition is invalid.
  void markNoShow(DateTime nowUtc) {
    _assertPending('markNoShow');

    if (!nowUtc.isAfter(windowEndUtc)) {
      throw const DomainException(
        'Cannot mark noShow before the time window has expired',
      );
    }

    _status = ExecutionStatus.noShow;
    _lastEvaluatedAtUtc = nowUtc;
    _statusLastUpdatedAtUtc = nowUtc;
    _finalizedAtUtc = nowUtc;

    _domainEvents.add(
      NoShowDeclaredEvent(
        organizationId: organizationId,
        occurredAtUtc: nowUtc,
        setId: setId,
        contractId: contractId,
        planVersion: planVersion,
        declaredAtUtc: nowUtc,
      ),
    );
  }

  /// Marks this obligation as [ExecutionStatus.evidenceGap].
  ///
  /// Allowed only when [status] == [ExecutionStatus.pending].
  /// Throws [DomainException] if the transition is invalid.
  void markEvidenceGap(DateTime nowUtc) {
    _assertPending('markEvidenceGap');

    _status = ExecutionStatus.evidenceGap;
    _lastEvaluatedAtUtc = nowUtc;
    _statusLastUpdatedAtUtc = nowUtc;
    _finalizedAtUtc = nowUtc;

    _domainEvents.add(
      EvidenceGapDeclaredEvent(
        organizationId: organizationId,
        occurredAtUtc: nowUtc,
        setId: setId,
        contractId: contractId,
        planVersion: planVersion,
        declaredAtUtc: nowUtc,
      ),
    );
  }

  /// Updates the evaluation timestamp without changing state.
  void updateEvaluationTimestamp(DateTime nowUtc) {
    _lastEvaluatedAtUtc = nowUtc;
  }

  // ── Guards ────────────────────────────────────────────────

  void _assertPending(String method) {
    if (_status != ExecutionStatus.pending) {
      throw DomainException(
        'Cannot call $method: current status is $_status '
        '(only pending allows transitions)',
      );
    }
  }

  /// Reconstitutes a [ContractualExecutionState] from persistence.
  ///
  /// Restores the full state of the aggregate, including identity,
  /// status, and binder evidence. Does NOT emit domain events.
  static ContractualExecutionState reconstitute({
    required String id,
    required String organizationId,
    required String setId,
    required String contractId,
    required int planVersion,
    required double startLatitude,
    required double startLongitude,
    required int startRadiusMeters,
    String? plannedVehicleId,
    required double contractualValue,
    required double noShowPenaltyMultiplier,
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
    required ExecutionStatus status,
    required DateTime createdAtUtc,
    required DateTime lastEvaluatedAtUtc,
    required DateTime statusLastUpdatedAtUtc,
    DateTime? finalizedAtUtc,
    String? boundVehicleId,
    DateTime? bindingTimestampUtc,
    double? bindingLatitude,
    double? bindingLongitude,
  }) {
    final state = ContractualExecutionState._(
      id: id,
      organizationId: organizationId,
      setId: setId,
      contractId: contractId,
      planVersion: planVersion,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      startRadiusMeters: startRadiusMeters,
      plannedVehicleId: plannedVehicleId,
      contractualValue: contractualValue,
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
      windowStartUtc: windowStartUtc,
      windowEndUtc: windowEndUtc,
      status: status,
      createdAtUtc: createdAtUtc,
      lastEvaluatedAtUtc: lastEvaluatedAtUtc,
      statusLastUpdatedAtUtc: statusLastUpdatedAtUtc,
    );

    state._finalizedAtUtc = finalizedAtUtc;
    state._boundVehicleId = boundVehicleId;
    state._bindingTimestampUtc = bindingTimestampUtc;
    state._bindingLatitude = bindingLatitude;
    state._bindingLongitude = bindingLongitude;

    return state;
  }

  // ── Identity Equality ─────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContractualExecutionState &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
