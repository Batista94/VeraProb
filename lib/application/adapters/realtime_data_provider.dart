import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'operational_data_provider.dart';

/// Connection status for the realtime provider.
enum ConnectionStatus {
  connecting,
  connected,
  disconnected,
  reconnecting,
  failed,
}

/// Real-time adapter that connects to Supabase Realtime for live vehicle
/// telemetry from the `vehicle_positions` table.
///
/// Uses a **stateful stream reconstruction** pattern:
/// - Maintains a `Map<tripId, VehiclePosition>` buffer
/// - Each Realtime payload updates one entry
/// - Stale entries (older than [_positionTtl]) are evicted before emission
/// - Deduplicates: only emits when the snapshot actually changes
///
/// This guarantees the downstream `Stream<List<VehiclePosition>>` always
/// represents the **current operational state** of the fleet.
class RealtimeDataProvider implements IOperationalDataProvider {
  final IDateTimeProvider _dateTimeProvider;
  final SupabaseClient _client;

  /// INV-30: SupabaseClient must be injected — no fallback to singleton.
  RealtimeDataProvider(this._dateTimeProvider, this._client);

  final _controller = StreamController<List<VehiclePosition>>.broadcast();
  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();

  RealtimeChannel? _channel;
  bool _isConnected = false;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  Timer? _reconnectionTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 15;

  /// Internal buffer: tripId → latest position.
  final Map<String, VehiclePosition> _positionBuffer = {};

  /// Pending positions for debouncing (tripId → position).
  final Map<String, VehiclePosition> _pendingPositions = {};

  /// Debounce timer.
  Timer? _debounceTimer;

  /// Debounce window duration.
  static const Duration _debounceWindow = Duration(milliseconds: 50);

  /// Last emitted snapshot for deduplication.
  List<VehiclePosition> _lastEmittedSnapshot = [];

  /// Time-to-live for buffered positions.
  /// Consistent with [VehiclePosition.isStale] which uses 2 minutes.
  static const Duration _positionTtl = Duration(minutes: 2);

  @override
  Stream<List<VehiclePosition>> get positionStream => _controller.stream;

  @override
  bool get isConnected => _isConnected;

  /// Stream of connection status changes.
  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  /// Current connection status.
  ConnectionStatus get status => _status;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    _status = ConnectionStatus.connecting;
    _connectionStatusController.add(_status);

    try {
      _channel = _client.channel('fleet-live-positions');

      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'vehicle_positions',
            callback: (payload) {
              onPayloadReceived(payload);
            },
          )
          .subscribe();

      _isConnected = true;
      _reconnectAttempts = 0; // Reset on successful connection

      _status = ConnectionStatus.connected;
      _connectionStatusController.add(_status);

      if (kDebugMode) {
        debugPrint(
          '[TELEMETRY] RealtimeDataProvider connected to vehicle_positions',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TELEMETRY] Connection failed: $e');
      }
      _scheduleReconnect();
      // Não relançar - reconexão será agendada automaticamente
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;

    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;

    await _channel?.unsubscribe();
    _channel = null;
    _positionBuffer.clear();
    _pendingPositions.clear();
    _lastEmittedSnapshot = [];
    _isConnected = false;

    _status = ConnectionStatus.disconnected;
    _connectionStatusController.add(_status);

    if (kDebugMode) {
      debugPrint('[TELEMETRY] RealtimeDataProvider disconnected');
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _reconnectAttempts++;
      _status = ConnectionStatus.failed;
      _connectionStatusController.add(_status);
      _reconnectionTimer?.cancel();
      return;
    }

    _reconnectAttempts++;
    _status = ConnectionStatus.reconnecting;
    _connectionStatusController.add(_status);

    // Exponential backoff: 2^(attempt-1) * 1000ms, max 30s
    final baseDelay = min(pow(2, _reconnectAttempts - 1) * 1000, 30000).toInt();

    // Jitter: ±100ms (~10-20% variation for 1s base)
    final jitter = Random().nextInt(200) - 100;
    final delay = Duration(milliseconds: baseDelay + jitter);

    _reconnectionTimer = Timer(delay, () {
      if (kDebugMode) {
        debugPrint('[TELEMETRY] Reconnecting (attempt $_reconnectAttempts)...');
      }
      connect();
    });
  }

  // ── Internal ──────────────────────────────────────────────────

  @visibleForTesting
  void onPayloadReceived(PostgresChangePayload payload) {
    if (_controller.isClosed) return;

    final record = payload.newRecord;
    if (record.isEmpty) return;

    try {
      final position = VehiclePosition(
        id: record['id']?.toString(),
        tripId: record['trip_id'] as String,
        latitude: (record['latitude'] as num).toDouble(),
        longitude: (record['longitude'] as num).toDouble(),
        speed: (record['speed'] as num?)?.toDouble(),
        heading: (record['heading'] as num?)?.toDouble(),
        timestamp: DateTime.parse(record['timestamp'] as String),
        source: (record['source'] as String?) ?? 'realtime',
        routeName: record['route_name'] as String?,
        vehiclePlate: record['vehicle_plate'] as String?,
      );

      // MONOTONICIDADE: Descartar eventos com timestamp anterior ao que já está no buffer
      final existingPending = _pendingPositions[position.tripId];
      final existingBuffer = _positionBuffer[position.tripId];

      // Verificar contra o mais recente dos dois buffers
      final existing = (existingPending != null && existingBuffer != null)
          ? (existingPending.timestamp.isAfter(existingBuffer.timestamp)
                ? existingPending
                : existingBuffer)
          : (existingPending ?? existingBuffer);

      if (existing != null && existing.timestamp.isAfter(position.timestamp)) {
        if (kDebugMode) {
          debugPrint(
            '[TELEMETRY] Discarded out-of-order event | '
            'trip=${position.tripId} | '
            'existing=${existing.timestamp.toIso8601String()} | '
            'received=${position.timestamp.toIso8601String()}',
          );
        }
        return; // Descartar cronologicamente anterior
      }

      // Atualizar buffer pendente
      _pendingPositions[position.tripId] = position;

      // Cancelar timer existente e criar novo
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceWindow, _flushPendingPositions);

      if (kDebugMode) {
        debugPrint(
          '[TELEMETRY] Payload received | '
          'trip=${position.tripId} | '
          'buffer=${_pendingPositions.length} vehicles',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TELEMETRY] Error parsing payload: $e');
      }
    }
  }

  /// Flush pending positions to main buffer and emit snapshot.
  @visibleForTesting
  void flushPendingPositions() {
    _flushPendingPositions();
  }

  void _flushPendingPositions() {
    if (_pendingPositions.isEmpty || _controller.isClosed) return;

    // 1. Mover posições pendentes para buffer principal
    _positionBuffer.addAll(_pendingPositions);
    _pendingPositions.clear();

    // 2. Evict stale entries (TTL)
    final now = _dateTimeProvider.nowUtc();
    _positionBuffer.removeWhere(
      (_, pos) => now.difference(pos.timestamp) > _positionTtl,
    );

    // 3. Build deterministic snapshot (sorted by tripId)
    final snapshot = _positionBuffer.values.toList()
      ..sort((a, b) => a.tripId.compareTo(b.tripId));

    // 4. Deduplicate: emit only if snapshot changed
    if (snapshot.length != _lastEmittedSnapshot.length ||
        !listEquals(snapshot, _lastEmittedSnapshot)) {
      _lastEmittedSnapshot = snapshot;
      if (!_controller.isClosed) {
        _controller.add(snapshot);
      }
    }
  }

  /// Dispose all resources: timers, streams, and channel subscription.
  void dispose() {
    // 1. Cancel reconnection timer
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;

    // 2. Cancel debounce timer
    _debounceTimer?.cancel();
    _debounceTimer = null;

    // 3. Disconnect channel
    if (_isConnected) {
      _channel?.unsubscribe();
      _channel = null;
      _isConnected = false;
    }

    // 4. Close streams
    _controller.close();
    _connectionStatusController.close();

    // 5. Clear buffers
    _positionBuffer.clear();
    _pendingPositions.clear();
    _lastEmittedSnapshot = [];
  }
}
