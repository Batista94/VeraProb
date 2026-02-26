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
  final String setId;
  final String contractId;

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
  DateTime? _finalizedAtUtc;

  DateTime get lastEvaluatedAtUtc => _lastEvaluatedAtUtc;
  DateTime? get finalizedAtUtc => _finalizedAtUtc;

  // ── Domain Events ─────────────────────────────────────────
  final List<DomainEvent> _domainEvents = [];
  List<DomainEvent> get domainEvents => UnmodifiableListView(_domainEvents);

  // ── Private Constructor ───────────────────────────────────
  ContractualExecutionState._({
    required this.id,
    required this.setId,
    required this.contractId,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required ExecutionStatus status,
    required this.createdAtUtc,
    required DateTime lastEvaluatedAtUtc,
  }) : _status = status,
       _lastEvaluatedAtUtc = lastEvaluatedAtUtc;

  // ── Factory ───────────────────────────────────────────────
  /// Creates a new [ContractualExecutionState] in [ExecutionStatus.pending].
  ///
  /// Validates the time window invariant.
  /// Generates a UUID v4 for identity.
  /// No binding fields are set at creation.
  ///
  /// Throws [DomainException] if [windowEndUtc] is not after [windowStartUtc].
  static ContractualExecutionState create({
    required String setId,
    required String contractId,
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
  }) {
    if (!windowEndUtc.isAfter(windowStartUtc)) {
      throw const DomainException(
        'windowEndUtc must be strictly after windowStartUtc',
      );
    }

    final now = DateTime.now().toUtc();

    return ContractualExecutionState._(
      id: const Uuid().v4(),
      setId: setId,
      contractId: contractId,
      windowStartUtc: windowStartUtc,
      windowEndUtc: windowEndUtc,
      status: ExecutionStatus.pending,
      createdAtUtc: now,
      lastEvaluatedAtUtc: now,
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
    _finalizedAtUtc = timestampUtc;

    _domainEvents.add(
      ExecutionBoundEvent(
        occurredAtUtc: timestampUtc,
        setId: setId,
        contractId: contractId,
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
    _finalizedAtUtc = nowUtc;

    _domainEvents.add(
      NoShowDeclaredEvent(
        occurredAtUtc: nowUtc,
        setId: setId,
        contractId: contractId,
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
    _finalizedAtUtc = nowUtc;

    _domainEvents.add(
      EvidenceGapDeclaredEvent(
        occurredAtUtc: nowUtc,
        setId: setId,
        contractId: contractId,
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
