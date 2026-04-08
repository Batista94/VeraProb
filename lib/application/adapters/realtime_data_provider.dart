import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'operational_data_provider.dart';

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

  RealtimeDataProvider(this._dateTimeProvider);

  final _controller = StreamController<List<VehiclePosition>>.broadcast();
  RealtimeChannel? _channel;
  bool _isConnected = false;

  /// Internal buffer: tripId → latest position.
  final Map<String, VehiclePosition> _positionBuffer = {};

  /// Last emitted snapshot for deduplication.
  List<VehiclePosition> _lastEmittedSnapshot = [];

  /// Time-to-live for buffered positions.
  /// Consistent with [VehiclePosition.isStale] which uses 2 minutes.
  static const Duration _positionTtl = Duration(minutes: 2);

  @override
  Stream<List<VehiclePosition>> get positionStream => _controller.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    _channel = supabase.channel('fleet-live-positions');

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

    if (kDebugMode) {
      debugPrint(
        '[TELEMETRY] RealtimeDataProvider connected to vehicle_positions',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;
    await _channel?.unsubscribe();
    _channel = null;
    _positionBuffer.clear();
    _lastEmittedSnapshot = [];
    _isConnected = false;

    if (kDebugMode) {
      debugPrint('[TELEMETRY] RealtimeDataProvider disconnected');
    }
  }

  // ── Internal ──────────────────────────────────────────────

  @visibleForTesting
  void onPayloadReceived(PostgresChangePayload payload) {
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

      // 1. Update buffer
      _positionBuffer[position.tripId] = position;

      // 2. Evict stale entries (TTL)
      final now = _dateTimeProvider.now();
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
        _controller.add(snapshot);
      }

      if (kDebugMode) {
        debugPrint(
          '[TELEMETRY] Payload received | '
          'trip=${position.tripId} | '
          'buffer=${_positionBuffer.length} vehicles',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TELEMETRY] Error parsing payload: $e');
      }
    }
  }
}
