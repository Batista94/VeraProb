import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/adapters/realtime_data_provider.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockRealtimeChannel extends Mock implements RealtimeChannel {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

void main() {
  late MockSupabaseClient mockClient;
  late MockRealtimeChannel mockChannel;
  late MockDateTimeProvider mockDateTime;

  setUpAll(() {
    registerFallbackValue(PostgresChangeEvent.all);
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockChannel = MockRealtimeChannel();
    mockDateTime = MockDateTimeProvider();

    when(
      () => mockDateTime.nowUtc(),
    ).thenReturn(DateTime.utc(2026, 4, 15, 16, 16));
    when(() => mockClient.channel(any())).thenReturn(mockChannel);
    when(
      () => mockChannel.onPostgresChanges(
        event: any(named: 'event'),
        schema: any(named: 'schema'),
        table: any(named: 'table'),
        callback: any(named: 'callback'),
      ),
    ).thenReturn(mockChannel);
    when(() => mockChannel.subscribe()).thenReturn(mockChannel);
    when(() => mockChannel.unsubscribe()).thenAnswer((_) async => 'ok');
  });

  group('Mensagens Malformadas', () {
    test('payload vazio nÃ£o causa crash', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {},
        errors: null,
      );

      expect(() => provider.onPayloadReceived(payload), returnsNormally);
      provider.disconnect();
    });

    test('campo tripId faltando Ã© ignorado', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'latitude': -23.5505,
          'longitude': -46.6333,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      expect(emissions, isEmpty);
      provider.disconnect();
    });

    test('campo latitude faltando Ã© ignorado', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'trip_id': 'trip-1',
          'longitude': -46.6333,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      expect(emissions, isEmpty);
      provider.disconnect();
    });

    test('campo longitude faltando Ã© ignorado', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'trip_id': 'trip-1',
          'latitude': -23.5505,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      expect(emissions, isEmpty);
      provider.disconnect();
    });

    test('campo timestamp faltando Ã© ignorado', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'trip_id': 'trip-1',
          'latitude': -23.5505,
          'longitude': -46.6333,
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      expect(emissions, isEmpty);
      provider.disconnect();
    });

    test('latitude com tipo errado (string) Ã© ignorado', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'trip_id': 'trip-1',
          'latitude': 'invalid',
          'longitude': -46.6333,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      expect(emissions, isEmpty);
      provider.disconnect();
    });

    test('longitude com tipo errado (string) Ã© ignorado', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'trip_id': 'trip-1',
          'latitude': -23.5505,
          'longitude': 'invalid',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      expect(emissions, isEmpty);
      provider.disconnect();
    });

    test('timestamp com formato invÃ¡lido Ã© ignorado', () {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      provider.connect();
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      final payload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'trip_id': 'trip-1',
          'latitude': -23.5505,
          'longitude': -46.6333,
          'timestamp': 'not-a-date',
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      expect(emissions, isEmpty);
      provider.disconnect();
    });
  });
}
