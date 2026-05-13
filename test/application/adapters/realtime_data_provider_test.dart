import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/adapters/realtime_data_provider.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

void main() {
  group('RealtimeDataProvider onPayloadReceived', () {
    late RealtimeDataProvider provider;
    late MockDateTimeProvider mockDateTime;
    late MockSupabaseClient mockClient;

    setUp(() {
      mockDateTime = MockDateTimeProvider();
      mockClient = MockSupabaseClient();
      when(() => mockDateTime.nowUtc()).thenReturn(DateTime.now().toUtc());
      provider = RealtimeDataProvider(mockDateTime, mockClient);
    });

    tearDown(() async {
      await provider.disconnect();
    });

    test('ignores empty payload', () {
      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
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
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'id': '1',
          'trip_id': 'trip1',
          'latitude': -20.0,
          'longitude': -40.0,
          'speed': 50.0,
          'heading': 90.0,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'source': 'gps',
        },
        errors: [],
      );

      provider.onPayloadReceived(validPayload);
      // StreamController.broadcast() delivers events asynchronously via the
      // microtask queue. Awaiting here lets the event loop process the queued
      // emission before the assertion runs.
      await Future.delayed(const Duration(milliseconds: 60));
      expect(emitCount, 1);
    });

    test('swallows parsing errors gently', () {
      int emitCount = 0;
      provider.positionStream.listen((_) => emitCount++);

      final invalidPayload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
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
    test('deduplicates: does not emit identical snapshot', () async {
      int emitCount = 0;
      provider.positionStream.listen((_) => emitCount++);

      final now = DateTime.now().toUtc();
      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: now,
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'id': '1',
          'trip_id': 'trip1',
          'latitude': -20.0,
          'longitude': -40.0,
          'timestamp': now.toIso8601String(),
        },
        errors: [],
      );

      // First emission
      provider.onPayloadReceived(payload);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(emitCount, 1);

      // Second emission with same data
      provider.onPayloadReceived(payload);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(emitCount, 1, reason: 'Should not emit duplicate snapshot');
    });

    test('evicts stale entries from buffer', () async {
      List<List<dynamic>> emissions = [];
      provider.positionStream.listen((snapshot) {
        emissions.add(snapshot);
      });

      final staleTimestamp = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      final freshTimestamp = DateTime.now().toUtc();

      final firstPayload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'id': 'fresh',
          'trip_id': 'trip-fresh',
          'latitude': -20.0,
          'longitude': -40.0,
          'timestamp': freshTimestamp.toIso8601String(),
        },
        errors: [],
      );

      final stalePayload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'id': 'old',
          'trip_id': 'trip-old',
          'latitude': -20.0,
          'longitude': -40.0,
          'timestamp': staleTimestamp.toIso8601String(),
        },
        errors: [],
      );

      // Add fresh one
      provider.onPayloadReceived(firstPayload);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(emissions.last, hasLength(1));

      // Add another fresh one but with a stale timestamp internally
      // In the real world, this would be an update or another trip that is actually old data.
      provider.onPayloadReceived(stalePayload);
      await Future.delayed(const Duration(milliseconds: 60));

      // Since stalePayload is 5 mins old, it should be evicted immediately after being added to buffer.
      // So the snapshot will still only have trip-fresh.
      // BUT, since the snapshot (trip-fresh) is the same as the PREVIOUS snapshot (trip-fresh), it WON'T emit!
      // To force an emission, we need the result to be different.

      final secondFreshPayload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'id': 'fresh-2',
          'trip_id': 'trip-fresh-2',
          'latitude': -21.0,
          'longitude': -41.0,
          'timestamp': freshTimestamp.toIso8601String(),
        },
        errors: [],
      );

      provider.onPayloadReceived(secondFreshPayload);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(emissions.last, hasLength(2));
      expect(emissions.last.map((p) => p.tripId), contains('trip-fresh-2'));
    });
  });
}
