import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pactaflow/application/adapters/realtime_data_provider.dart';

void main() {
  group('RealtimeDataProvider onPayloadReceived', () {
    late RealtimeDataProvider provider;

    setUp(() {
      provider = RealtimeDataProvider();
    });

    tearDown(() async {
      await provider.disconnect();
    });

    test('ignores empty payload', () {
      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {},
        errors: [],
      );

      // Should not throw or crash
      provider.onPayloadReceived(payload);
    });

    test('parses and buffers position successfully', () async {
      int emitCount = 0;
      provider.positionStream.listen((_) => emitCount++);

      final validPayload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'id': '1',
          'trip_id': 'trip1',
          'latitude': -20.0,
          'longitude': -40.0,
          'speed': 50.0,
          'heading': 90.0,
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'gps',
        },
        errors: [],
      );

      provider.onPayloadReceived(validPayload);
      // StreamController.broadcast() delivers events asynchronously via the
      // microtask queue. Awaiting here lets the event loop process the queued
      // emission before the assertion runs.
      await Future.delayed(Duration.zero);
      expect(emitCount, 1);
    });

    test('swallows parsing errors gently', () {
      int emitCount = 0;
      provider.positionStream.listen((_) => emitCount++);

      final invalidPayload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'id': '1', 'trip_id': 'trip1',
          'latitude': 'invalid_string', // This will crash cast to num
        },
        errors: [],
      );

      // Should catch the error internally and not emit
      provider.onPayloadReceived(invalidPayload);
      expect(emitCount, 0);
    });
  });
}
