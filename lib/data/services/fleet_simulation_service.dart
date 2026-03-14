import 'dart:async';
import 'dart:math';
import '../../application/adapters/stress_scenario_config.dart';
import '../../domain/entities/operational_trip.dart';
import '../../domain/entities/trip_event.dart';
import '../../domain/entities/vehicle_position.dart';
import '../../domain/enums/event_type.dart';
import '../../domain/enums/trip_status.dart';

/// Simulates a realistic GTFS Realtime feed for São Paulo.
///
/// Generates trips and positions along real bus corridors,
/// with natural movement patterns, delays, and state transitions.
class FleetSimulationService {
  final StressScenarioConfig? config;
  late final Random _random; // Deterministic seed for consistency
  Timer? _simTimer;

  FleetSimulationService({this.config}) {
    _random = Random(config?.seed ?? 42);
  }

  // São Paulo real bus route corridors (approximate)
  static const _corridors = [
    _RouteCorridor(
      shortName: '809U-10',
      longName: 'Cidade Universitária',
      color: '#FF5722',
      startLat: -23.5587,
      startLng: -46.7308, // USP
      endLat: -23.5473,
      endLng: -46.6350, // Centro
    ),
    _RouteCorridor(
      shortName: '7279-10',
      longName: 'Shop. Eldorado',
      color: '#2196F3',
      startLat: -23.5728,
      startLng: -46.6978, // Pinheiros
      endLat: -23.5425,
      endLng: -46.6492, // Consolação
    ),
    _RouteCorridor(
      shortName: '3012-10',
      longName: 'Terminal Lapa',
      color: '#4CAF50',
      startLat: -23.5244,
      startLng: -46.6916, // Lapa
      endLat: -23.5634,
      endLng: -46.6539, // Paulista
    ),
    _RouteCorridor(
      shortName: '2012-10',
      longName: 'Terminal Bandeira',
      color: '#9C27B0',
      startLat: -23.5503,
      startLng: -46.6405, // Terminal Bandeira
      endLat: -23.5862,
      endLng: -46.6652, // Ibirapuera
    ),
    _RouteCorridor(
      shortName: '5154-10',
      longName: 'V. Mariana',
      color: '#FF9800',
      startLat: -23.5866,
      startLng: -46.6367, // Vila Mariana
      endLat: -23.5505,
      endLng: -46.6333, // Sé
    ),
    _RouteCorridor(
      shortName: '2504-10',
      longName: 'Metrô Santana',
      color: '#00BCD4',
      startLat: -23.5027,
      startLng: -46.6285, // Santana
      endLat: -23.5429,
      endLng: -46.6339, // Luz
    ),
    _RouteCorridor(
      shortName: '875A-10',
      longName: 'Terminal Sacomã',
      color: '#E91E63',
      startLat: -23.5898,
      startLng: -46.6042, // Sacomã
      endLat: -23.5552,
      endLng: -46.6297, // Liberdade
    ),
    _RouteCorridor(
      shortName: '6291-10',
      longName: 'Term. Princ. Isabel',
      color: '#607D8B',
      startLat: -23.5342,
      startLng: -46.6445, // Princesa Isabel
      endLat: -23.5614,
      endLng: -46.6713, // Clínicas
    ),
  ];

  // Simulated driver names
  static const _driverNames = [
    'João Silva',
    'Maria Santos',
    'Pedro Lima',
    'Ana Costa',
    'Carlos Oliveira',
    'Fernanda Souza',
    'Roberto Almeida',
    'Beatriz Ferreira',
  ];

  // Simulated plates
  static const _plates = [
    'ABC-1234',
    'DEF-5678',
    'GHI-9012',
    'JKL-3456',
    'MNO-7890',
    'PQR-1357',
    'STU-2468',
    'VWX-9876',
  ];

  // Internal state for simulation
  final List<_SimulatedTrip> _trips = [];
  final Map<String, List<TripEvent>> _eventLog = {};
  final _tripChangeController =
      StreamController<List<OperationalTrip>>.broadcast();
  final _positionChangeController =
      StreamController<List<VehiclePosition>>.broadcast();
  bool _initialized = false;
  int _tickCount = 0;
  int _eventCounter = 0;

  /// Initialize all simulated trips
  void _initializeTrips() {
    if (_initialized) return;
    _initialized = true;

    final count = config?.vehicleCount ?? _corridors.length;

    for (var i = 0; i < count; i++) {
      final corridor = _corridors[i % _corridors.length];
      _trips.add(
        _SimulatedTrip(
          id: 'trip-${corridor.shortName}-${i.toString().padLeft(3, '0')}',
          routeId: 'route-${i % _corridors.length}',
          corridor: corridor,
          driverName: _driverNames[i % _driverNames.length],
          vehiclePlate: _plates[i % _plates.length],
          progress: _random.nextDouble() * 0.8 + 0.1, // 10-90% along route
          status: _randomActiveStatus(),
          speed: 15 + _random.nextDouble() * 35, // 15-50 km/h
          delaySeconds: 0,
        ),
      );
    }

    // Set some interesting states deterministically based on seed
    if (_trips.length > 3) {
      _trips[3] = _trips[3].copyWith(
        status: TripStatus.delayed,
        delaySeconds: 480, // 8 min delay
      );
    }
    if (_trips.length > 5) {
      _trips[5] = _trips[5].copyWith(status: TripStatus.atStop, speed: 0);
    }
  }

  TripStatus _randomActiveStatus() {
    final roll = _random.nextDouble();
    if (roll < 0.7) return TripStatus.enRoute;
    if (roll < 0.85) return TripStatus.atStop;
    if (roll < 0.95) return TripStatus.delayed;
    return TripStatus.dispatched;
  }

  void _ensureSimulationRunning(Duration interval) {
    if (_simTimer != null) return;
    _initializeTrips();
    _simTimer = Timer.periodic(interval, (_) {
      _tickCount++;
      _advanceSimulation();
      _emitCurrentState();
    });
  }

  /// Get a stream of operational trips, updated every [interval].
  Stream<List<OperationalTrip>> tripStream({
    Duration interval = const Duration(seconds: 15),
  }) async* {
    _ensureSimulationRunning(interval);
    yield currentTrips;
    yield* _tripChangeController.stream;
  }

  /// Get a stream of vehicle positions, updated every [interval].
  Stream<List<VehiclePosition>> positionStream({
    Duration interval = const Duration(seconds: 15),
  }) async* {
    _ensureSimulationRunning(interval);
    yield currentPositions;
    yield* _positionChangeController.stream;
  }

  /// Get current snapshot of trips (non-streaming)
  List<OperationalTrip> get currentTrips {
    _initializeTrips();
    return _trips.map((t) => t.toOperationalTrip()).toList();
  }

  /// Get current snapshot of positions (non-streaming)
  List<VehiclePosition> get currentPositions {
    _initializeTrips();
    return _trips
        .where((t) => t.status.isActive && !t.isSignalLost)
        .map((t) => t.toVehiclePosition())
        .toList();
  }

  // ── Mutation Methods (for OperationalControlService) ──────

  /// Update the status of a trip by ID.
  /// Returns the previous status for event generation.
  TripStatus? updateTripStatus(
    String tripId,
    TripStatus newStatus, {
    int? delaySeconds,
  }) {
    _initializeTrips();
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return null;

    final oldStatus = _trips[index].status;
    _trips[index] = _trips[index].copyWith(
      status: newStatus,
      delaySeconds:
          delaySeconds ?? (newStatus == TripStatus.enRoute ? 0 : null),
      speed:
          newStatus == TripStatus.interrupted || newStatus == TripStatus.atStop
          ? 0
          : null,
    );

    // Notify listeners
    _emitCurrentState();
    return oldStatus;
  }

  /// Store a trip event in the in-memory log.
  TripEvent addEvent({
    required String tripId,
    required EventType eventType,
    TripStatus? fromStatus,
    TripStatus? toStatus,
    Map<String, dynamic>? metadata,
  }) {
    _eventCounter++;
    final event = TripEvent(
      id: 'evt-$_eventCounter',
      tripId: tripId,
      eventType: eventType,
      fromStatus: fromStatus,
      toStatus: toStatus,
      metadata: metadata,
      createdAt: DateTime.now().toUtc(),
    );
    _eventLog.putIfAbsent(tripId, () => []);
    _eventLog[tripId]!.insert(0, event); // Newest first
    return event;
  }

  /// Get all events for a trip, newest first.
  List<TripEvent> getEventsForTrip(String tripId) {
    return _eventLog[tripId] ?? [];
  }

  /// Get a trip by ID.
  OperationalTrip? getTripById(String tripId) {
    _initializeTrips();
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return null;
    return _trips[index].toOperationalTrip();
  }

  /// Push current state to stream listeners.
  void _emitCurrentState() {
    _tripChangeController.add(currentTrips);
    _positionChangeController.add(currentPositions);
  }

  /// Advance simulation by one tick
  void _advanceSimulation() {
    for (var i = 0; i < _trips.length; i++) {
      var trip = _trips[i];

      // Move vehicles along their corridors
      if (trip.status == TripStatus.enRoute ||
          trip.status == TripStatus.delayed) {
        var newProgress = trip.progress + (0.005 + _random.nextDouble() * 0.01);
        if (newProgress >= 1.0) {
          newProgress = 0.05; // Loop back
        }
        trip = trip.copyWith(
          progress: newProgress,
          speed: 15 + _random.nextDouble() * 35,
        );
      }

      // Occasionally change states
      if (_tickCount % 4 == 0) {
        trip = _evolveState(trip, i);
      }

      // Add slight noise to positions
      trip = trip.copyWith(
        latNoise: (_random.nextDouble() - 0.5) * 0.0003,
        lngNoise: (_random.nextDouble() - 0.5) * 0.0003,
      );

      _trips[i] = trip;
    }
  }

  _SimulatedTrip _evolveState(_SimulatedTrip trip, int index) {
    final roll = _random.nextDouble();
    final incidentProb = config?.incidentProbability ?? 0.05;
    final signalLossProb = config?.signalLossProbability ?? 0.05;

    // Signal loss toggle
    if (roll < signalLossProb) {
      return trip.copyWith(isSignalLost: !trip.isSignalLost);
    }

    switch (trip.status) {
      case TripStatus.enRoute:
        if (roll < incidentProb) {
          return trip.copyWith(
            status: TripStatus.delayed,
            delaySeconds: 180 + _random.nextInt(600),
          );
        }
        if (roll < 0.1) {
          return trip.copyWith(status: TripStatus.atStop, speed: 0);
        }
        return trip;

      case TripStatus.atStop:
        if (roll < 0.4) {
          return trip.copyWith(
            status: TripStatus.enRoute,
            speed: 20 + _random.nextDouble() * 20,
          );
        }
        return trip;

      case TripStatus.delayed:
        if (roll < 0.2) {
          return trip.copyWith(status: TripStatus.enRoute, delaySeconds: 0);
        }
        // Increase delay
        return trip.copyWith(
          delaySeconds: trip.delaySeconds + 30 + _random.nextInt(60),
        );

      case TripStatus.dispatched:
        if (roll < 0.3) {
          return trip.copyWith(
            status: TripStatus.enRoute,
            speed: 10 + _random.nextDouble() * 15,
          );
        }
        return trip;

      default:
        return trip;
    }
  }
}

/// Internal route corridor definition
class _RouteCorridor {
  final String shortName;
  final String longName;
  final String color;
  final double startLat, startLng;
  final double endLat, endLng;

  const _RouteCorridor({
    required this.shortName,
    required this.longName,
    required this.color,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
  });

  double latAt(double progress) => startLat + (endLat - startLat) * progress;
  double lngAt(double progress) => startLng + (endLng - startLng) * progress;
}

/// Internal simulated trip state
class _SimulatedTrip {
  final String id;
  final String routeId;
  final _RouteCorridor corridor;
  final String driverName;
  final String vehiclePlate;
  final double progress; // 0.0 to 1.0 along corridor
  final TripStatus status;
  final double speed;
  final int delaySeconds;
  final double latNoise;
  final double lngNoise;
  final bool isSignalLost;

  const _SimulatedTrip({
    required this.id,
    required this.routeId,
    required this.corridor,
    required this.driverName,
    required this.vehiclePlate,
    required this.progress,
    required this.status,
    required this.speed,
    this.delaySeconds = 0,
    this.latNoise = 0,
    this.lngNoise = 0,
    this.isSignalLost = false,
  });

  _SimulatedTrip copyWith({
    String? id,
    String? routeId,
    _RouteCorridor? corridor,
    String? driverName,
    String? vehiclePlate,
    double? progress,
    TripStatus? status,
    double? speed,
    int? delaySeconds,
    double? latNoise,
    double? lngNoise,
    bool? isSignalLost,
  }) {
    return _SimulatedTrip(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      corridor: corridor ?? this.corridor,
      driverName: driverName ?? this.driverName,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      speed: speed ?? this.speed,
      delaySeconds: delaySeconds ?? this.delaySeconds,
      latNoise: latNoise ?? this.latNoise,
      lngNoise: lngNoise ?? this.lngNoise,
      isSignalLost: isSignalLost ?? this.isSignalLost,
    );
  }

  double get currentLat => corridor.latAt(progress) + latNoise;
  double get currentLng => corridor.lngAt(progress) + lngNoise;

  OperationalTrip toOperationalTrip() {
    return OperationalTrip(
      id: id,
      routeId: routeId,
      status: status,
      scheduledStart: DateTime.now().subtract(
        Duration(minutes: (progress * 60).toInt()),
      ),
      scheduledEnd: DateTime.now().add(
        Duration(minutes: ((1.0 - progress) * 60).toInt()),
      ),
      actualStart: status.isActive || status.isTerminal
          ? DateTime.now().subtract(Duration(minutes: (progress * 60).toInt()))
          : null,
      delaySeconds: delaySeconds,
      completionPct: progress * 100,
      sourceType: 'gtfs_realtime',
      driverName: driverName,
      vehiclePlate: vehiclePlate,
      routeShortName: corridor.shortName,
      routeLongName: corridor.longName,
      routeColor: corridor.color,
    );
  }

  VehiclePosition toVehiclePosition() {
    return VehiclePosition(
      tripId: id,
      latitude: currentLat,
      longitude: currentLng,
      speed: speed,
      heading: _calculateHeading(),
      timestamp: DateTime.now().toUtc(),
      source: 'api_public',
      routeName: corridor.shortName,
      vehiclePlate: vehiclePlate,
    );
  }

  double _calculateHeading() {
    final dLat = corridor.endLat - corridor.startLat;
    final dLng = corridor.endLng - corridor.startLng;
    return (atan2(dLng, dLat) * 180 / pi + 360) % 360;
  }
}
