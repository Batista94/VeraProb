import 'dart:collection';

import 'package:uuid/uuid.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'domain_event.dart';
import 'domain_exception.dart';
import 'execution_events.dart';
import 'execution_status.dart';

/// Aggregate Root tracking the lifecycle and judgment of a single
/// contractual service execution obligation.
///
/// **State machine**:
/// ```
/// planned → inTransit        (startTransit — Telegram button OR geofence entry)
/// planned → completed        (bindExecution — engine dwell confirmed)
/// planned → failed           (markFailed — sweep expired OR pg_cron 24h)
/// inTransit → completed      (bindExecution — engine dwell OR complete)
/// inTransit → completedWithGaps (completeWithGaps — /finish forced)
/// inTransit → failed         (markFailed — sweep expired)
/// failed → completed         (bindExecution — INV-12 late arrival)
/// completedWithGaps → completed (bindExecution — INV-12 late arrival)
/// planned/inTransit → inhibited (justification approved — INV-15)
/// ```
/// Transitions to 'completed' from terminal states are final.
/// Guard: completed/failed cannot revert to inTransit.
class ContractualExecutionState {
  // ── Identity ──────────────────────────────────────────────
  final String id;
  final String organizationId;
  final String setId;
  final String contractId;
  final int planVersion;

  // ── Geofence (denormalized) ───────────────────────────────
  final double startLatitude; // Physical Metric - Double Required
  final double startLongitude; // Physical Metric - Double Required
  final int startRadiusMeters;

  // ── Vehicle Planning ──────────────────────────────────────
  final String? plannedVehicleId;

  // ── Financial ─────────────────────────────────────────────
  final Money contractualValue;
  final int noShowPenaltyBps;

  // ── Time Window ───────────────────────────────────────────
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;

  // ── Status ────────────────────────────────────────────────
  ExecutionStatus _status;
  ExecutionStatus get status => _status;

  // ── Binding Evidence ──────────────────────────────────────
  String? _boundVehicleId;
  DateTime? _bindingTimestampUtc;
  double? _bindingLatitude; // Physical Metric - Double Required
  double? _bindingLongitude; // Physical Metric - Double Required

  String? get boundVehicleId => _boundVehicleId;
  DateTime? get bindingTimestampUtc => _bindingTimestampUtc;
  double? get bindingLatitude =>
      _bindingLatitude; // Physical Metric - Double Required
  double? get bindingLongitude =>
      _bindingLongitude; // Physical Metric - Double Required

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

  /// Drains all pending domain events. Call after persisting events to
  /// prevent duplicate writes when the aggregate is reused across ticks.
  void clearDomainEvents() => _domainEvents.clear();

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
    required this.noShowPenaltyBps,
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
  /// Creates a new [ContractualExecutionState] in [ExecutionStatus.planned].
  static ContractualExecutionState create({
    required String organizationId,
    required String setId,
    required String contractId,
    required int planVersion,
    required double startLatitude, // Physical Metric - Double Required
    required double startLongitude, // Physical Metric - Double Required
    required int startRadiusMeters,
    String? plannedVehicleId,
    required Money contractualValue,
    required int noShowPenaltyBps,
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
  }) {
    if (!windowEndUtc.isAfter(windowStartUtc)) {
      throw const DomainException(
        'windowEndUtc must be strictly after windowStartUtc',
      );
    }
    if (contractualValue.cents <= 0) {
      throw const DomainException('contractualValue must be greater than 0');
    }
    if (noShowPenaltyBps < 10000) {
      throw const DomainException('noShowPenaltyBps must be >= 10000 (1.0x)');
    }

    final now =
        StaticDateTimeProvider.instance?.nowUtc() ?? DateTime.now().toUtc();

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
      noShowPenaltyBps: noShowPenaltyBps,
      windowStartUtc: windowStartUtc,
      windowEndUtc: windowEndUtc,
      status: ExecutionStatus.planned,
      createdAtUtc: now,
      lastEvaluatedAtUtc: now,
      statusLastUpdatedAtUtc: now,
    );
  }

  // ── State Transitions ─────────────────────────────────────

  /// Initiates transit for this obligation.
  ///
  /// Allowed from [ExecutionStatus.planned] only.
  /// Idempotent: if already [ExecutionStatus.inTransit], no-op (first-wins rule).
  /// [source]: 'telegram' | 'geofence'
  void startTransit({required DateTime timestampUtc, required String source}) {
    if (_status == ExecutionStatus.inTransit) return; // first-wins idempotency
    if (_status != ExecutionStatus.planned) {
      throw DomainException(
        'Cannot call startTransit: current status is $_status '
        '(only planned allows transition to inTransit)',
      );
    }
    _status = ExecutionStatus.inTransit;
    _lastEvaluatedAtUtc = timestampUtc;
    _statusLastUpdatedAtUtc = timestampUtc;

    _domainEvents.add(
      TransitStartedEvent(
        organizationId: organizationId,
        occurredAtUtc: timestampUtc,
        setId: setId,
        contractId: contractId,
        planVersion: planVersion,
        startedAtUtc: timestampUtc,
        source: source,
      ),
    );
  }

  /// Binds a vehicle to this obligation, marking it as [ExecutionStatus.completed].
  ///
  /// Allowed from: [planned] (engine auto-dwell), [inTransit] (engine after start),
  /// [failed] (INV-12 late arrival), [completedWithGaps] (INV-12 upgrade).
  /// Guard: [completed] and [inhibited] are terminal — throws.
  void bindExecution({
    required String vehicleId,
    required double latitude, // Physical Metric - Double Required
    required double longitude, // Physical Metric - Double Required
    required DateTime timestampUtc,
  }) {
    if (_status == ExecutionStatus.completed ||
        _status == ExecutionStatus.inhibited) {
      throw DomainException(
        'Cannot call bindExecution: current status is $_status (terminal)',
      );
    }
    _status = ExecutionStatus.completed;
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

  /// Marks this obligation as [ExecutionStatus.failed].
  ///
  /// Allowed from [planned] or [inTransit].
  /// Requires [nowUtc] to be after [windowEndUtc].
  void markFailed(DateTime nowUtc) {
    if (_status != ExecutionStatus.planned &&
        _status != ExecutionStatus.inTransit) {
      throw DomainException(
        'Cannot call markFailed: current status is $_status '
        '(only planned or inTransit allow transition to failed)',
      );
    }
    if (!nowUtc.isAfter(windowEndUtc)) {
      throw const DomainException(
        'Cannot mark failed before the time window has expired',
      );
    }
    _status = ExecutionStatus.failed;
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

  /// Marks this obligation as [ExecutionStatus.completedWithGaps].
  ///
  /// Allowed from [inTransit] only (driver used /finish with pending evidence).
  void completeWithGaps(DateTime nowUtc) {
    if (_status != ExecutionStatus.inTransit) {
      throw DomainException(
        'Cannot call completeWithGaps: current status is $_status '
        '(only inTransit allows transition to completedWithGaps)',
      );
    }
    _status = ExecutionStatus.completedWithGaps;
    _lastEvaluatedAtUtc = nowUtc;
    _statusLastUpdatedAtUtc = nowUtc;
    _finalizedAtUtc = nowUtc;

    _domainEvents.add(
      CompletedWithGapsEvent(
        organizationId: organizationId,
        occurredAtUtc: nowUtc,
        setId: setId,
        contractId: contractId,
        planVersion: planVersion,
        completedAtUtc: nowUtc,
      ),
    );
  }

  /// Suppresses this obligation — [ExecutionStatus.inhibited].
  ///
  /// Allowed from any non-terminal state (planned, inTransit, failed, completedWithGaps).
  /// [completed] and [inhibited] are terminal and cannot be inhibited.
  void inhibit({required DateTime timestampUtc, required String reason}) {
    if (_status == ExecutionStatus.completed ||
        _status == ExecutionStatus.inhibited) {
      throw DomainException(
        'Cannot call inhibit: current status is $_status (terminal)',
      );
    }
    _status = ExecutionStatus.inhibited;
    _statusLastUpdatedAtUtc = timestampUtc;
    _finalizedAtUtc = timestampUtc;

    _domainEvents.add(
      ExecutionInhibitedEvent(
        organizationId: organizationId,
        occurredAtUtc: timestampUtc,
        setId: setId,
        contractId: contractId,
        planVersion: planVersion,
        reason: reason,
      ),
    );
  }

  /// Updates the evaluation timestamp without changing state.
  void updateEvaluationTimestamp(DateTime nowUtc) {
    _lastEvaluatedAtUtc = nowUtc;
  }

  // ── Reconstitution ────────────────────────────────────────
  static ContractualExecutionState reconstitute({
    required String id,
    required String organizationId,
    required String setId,
    required String contractId,
    required int planVersion,
    required double startLatitude, // Physical Metric - Double Required
    required double startLongitude, // Physical Metric - Double Required
    required int startRadiusMeters,
    String? plannedVehicleId,
    required Money contractualValue,
    required int noShowPenaltyBps,
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
    required ExecutionStatus status,
    required DateTime createdAtUtc,
    required DateTime lastEvaluatedAtUtc,
    required DateTime statusLastUpdatedAtUtc,
    DateTime? finalizedAtUtc,
    String? boundVehicleId,
    DateTime? bindingTimestampUtc,
    double? bindingLatitude, // Physical Metric - Double Required
    double? bindingLongitude, // Physical Metric - Double Required
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
      noShowPenaltyBps: noShowPenaltyBps,
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
