import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'contractual_evaluation_engine.dart';
import 'contractual_financial_closing_service.dart';

/// Orchestrator that connects the [ContractualEvaluationEngine] to the
/// live telemetry stream and a periodic sweep timer.
///
/// **Responsibilities:**
/// - Subscribe to the normalized vehicle state stream
/// - Forward each vehicle state to the engine for geofence evaluation
/// - Periodically sweep expired obligations for NoShow detection
/// - Trigger daily financial closing via [ContractualFinancialClosingService]
///
/// **Does NOT:**
/// - Import Flutter widgets or Riverpod
/// - Create global timers outside its own lifecycle
/// - Contain domain logic (delegated entirely to the engine)
///
/// All dependencies are injected via constructor.
class ContractualEvaluationSubscriber {
  final ContractualEvaluationEngine _engine;
  final Stream<List<VehicleOperationalState>> _vehicleStream;
  final Duration _sweepInterval;
  final String organizationId;
  final ContractualFinancialClosingService? _closingService;
  final IDateTimeProvider _dateTimeProvider;

  StreamSubscription<List<VehicleOperationalState>>? _subscription;
  Timer? _sweepTimer;

  ContractualEvaluationSubscriber({
    required ContractualEvaluationEngine engine,
    required Stream<List<VehicleOperationalState>> vehicleStream,
    required Duration sweepInterval,
    required this.organizationId,
    ContractualFinancialClosingService? closingService,
    IDateTimeProvider? dateTimeProvider,
  }) : _engine = engine,
       _vehicleStream = vehicleStream,
       _sweepInterval = sweepInterval,
       _closingService = closingService,
       _dateTimeProvider = dateTimeProvider ?? BrazilDateTimeProvider();

  /// Whether the subscriber is actively listening.
  bool get isActive => _subscription != null;

  /// Starts listening to the vehicle stream and the sweep timer.
  ///
  /// If already active, does nothing (prevents duplicate subscriptions).
  Future<void> start() async {
    if (isActive) return;

    _subscription = _vehicleStream.listen(_onVehicleData);

    _sweepTimer = Timer.periodic(_sweepInterval, (_) {
      _onSweepTick();
    });
  }

  /// Stops listening and cancels the sweep timer.
  ///
  /// Safe to call multiple times.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;

    _sweepTimer?.cancel();
    _sweepTimer = null;
  }

  // ── Internal Handlers ─────────────────────────────────────

  /// Processes each vehicle state sequentially within a batch.
  ///
  /// Sequential processing is required because the engine maintains
  /// internal dwell-time state that assumes single-threaded access.
  /// Errors from the engine are caught and logged — they never
  /// cancel the subscription.
  void _onVehicleData(List<VehicleOperationalState> states) async {
    for (final state in states) {
      try {
        await _engine.processVehicleState(
          state,
          organizationId: organizationId,
        );
      } catch (e) {
        if (kDebugMode) {
          print(
            '[SLA SUBSCRIBER] Error processing vehicle '
            '${state.vehicleId}: $e',
          );
        }
      }
    }
  }

  /// Sweep expired obligations for NoShow detection.
  /// Also triggers daily financial closing if configured.
  void _onSweepTick() async {
    try {
      await _engine.sweepExpiredObligations(
        nowUtc: _dateTimeProvider.nowUtc(),
        organizationId: organizationId,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[SLA SUBSCRIBER] Error during sweep: $e');
      }
    }

    try {
      if (_closingService != null) {
        await _closingService.onTick(organizationId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[SLA SUBSCRIBER] Error during financial closing: $e');
      }
    }
  }
}
