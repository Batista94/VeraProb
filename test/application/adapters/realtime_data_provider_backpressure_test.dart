import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/adapters/realtime_data_provider.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
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

    when(() => mockDateTime.nowUtc()).thenReturn(DateTime.now().toUtc());
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

  group('Debouncing com Monotonicidade', () {
    test(
      '1000 mensagens em 100ms → apenas últimas de cada tripId processadas',
      () async {
        // Arrange
        final baseTime = DateTime(2026, 4, 15, 10, 0, 0).toUtc();
        when(
          () => mockDateTime.nowUtc(),
        ).thenReturn(baseTime.add(const Duration(seconds: 1)));

        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final emissions = <List<VehiclePosition>>[];
        provider.positionStream.listen(emissions.add);

        await provider.connect();
        await Future.delayed(Duration.zero); // Garantir subscription ativa

        // Act - simular 1000 mensagens para 10 tripIds diferentes
        for (int i = 0; i < 1000; i++) {
          final tripId = 'trip-${i % 10}'; // 10 trips diferentes
          final payload = PostgresChangePayload(
            oldRecord: {},
            newRecord: {
              'id': 'pos-$i',
              'trip_id': tripId,
              'latitude': -23.5 + (i * 0.0001),
              'longitude': -46.6 + (i * 0.0001),
              'speed': 50.0,
              'heading': 90.0,
              'timestamp': baseTime
                  .add(Duration(milliseconds: i))
                  .toIso8601String(),
              'source': 'realtime',
            },
            eventType: PostgresChangeEvent.insert,
            table: 'vehicle_positions',
            schema: 'public',
            commitTimestamp: DateTime.now().toUtc(),
            errors: null,
          );
          provider.onPayloadReceived(payload);
        }

        // Aguardar debounce timer (50ms) + margem para processamento
        await Future.delayed(const Duration(milliseconds: 100));

        // Assert - deve ter emitido apenas 1 snapshot com 10 posições (última de cada trip)
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(10));

        // Verificar que são as últimas posições de cada trip
        for (int tripIdx = 0; tripIdx < 10; tripIdx++) {
          final tripId = 'trip-$tripIdx';
          final position = emissions.first.firstWhere(
            (p) => p.tripId == tripId,
          );

          // Última mensagem para este trip foi i = 990 + tripIdx
          final expectedLastIndex = 990 + tripIdx;
          expect(position.id, equals('pos-$expectedLastIndex'));
        }

        provider.dispose();
      },
    );

    test(
      'MONOTONICIDADE: evento com occurred_at anterior é DESCARTADO',
      () async {
        // Arrange
        final baseTime = DateTime(2026, 4, 15, 10, 0, 0).toUtc();
        when(
          () => mockDateTime.nowUtc(),
        ).thenReturn(baseTime.add(const Duration(seconds: 15)));

        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final emissions = <List<VehiclePosition>>[];
        provider.positionStream.listen(emissions.add);

        await provider.connect();
        await Future.delayed(Duration.zero);

        // Act - enviar posição T+10s
        final payload1 = PostgresChangePayload(
          oldRecord: {},
          newRecord: {
            'id': 'pos-1',
            'trip_id': 'trip-1',
            'latitude': -23.5,
            'longitude': -46.6,
            'speed': 50.0,
            'heading': 90.0,
            'timestamp': baseTime
                .add(const Duration(seconds: 10))
                .toIso8601String(),
            'source': 'realtime',
          },
          eventType: PostgresChangeEvent.insert,
          table: 'vehicle_positions',
          schema: 'public',
          commitTimestamp: DateTime.now().toUtc(),
          errors: null,
        );
        provider.onPayloadReceived(payload1);

        await Future.delayed(const Duration(milliseconds: 60));
        emissions.clear(); // Limpar primeira emissão

        // Enviar posição T+5s (ANTERIOR - deve ser descartada)
        final payload2 = PostgresChangePayload(
          oldRecord: {},
          newRecord: {
            'id': 'pos-2',
            'trip_id': 'trip-1',
            'latitude': -23.6,
            'longitude': -46.7,
            'speed': 60.0,
            'heading': 180.0,
            'timestamp': baseTime
                .add(const Duration(seconds: 5))
                .toIso8601String(),
            'source': 'realtime',
          },
          eventType: PostgresChangeEvent.insert,
          table: 'vehicle_positions',
          schema: 'public',
          commitTimestamp: DateTime.now().toUtc(),
          errors: null,
        );
        provider.onPayloadReceived(payload2);

        await Future.delayed(const Duration(milliseconds: 60));

        // Assert - NÃO deve ter emitido nova snapshot (evento descartado)
        expect(emissions.length, equals(0));

        provider.dispose();
      },
    );

    test('mensagens agrupadas em janelas de 50ms', () async {
      // Arrange
      final baseTime = DateTime(2026, 4, 15, 10, 0, 0).toUtc();
      when(
        () => mockDateTime.nowUtc(),
      ).thenReturn(baseTime.add(const Duration(seconds: 1)));

      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      await provider.connect();
      await Future.delayed(Duration.zero);

      // Act - enviar 3 mensagens rapidamente
      for (int i = 0; i < 3; i++) {
        final payload = PostgresChangePayload(
          oldRecord: {},
          newRecord: {
            'id': 'pos-$i',
            'trip_id': 'trip-1',
            'latitude': -23.5 + (i * 0.001),
            'longitude': -46.6,
            'speed': 50.0,
            'heading': 90.0,
            'timestamp': baseTime
                .add(Duration(milliseconds: i * 10))
                .toIso8601String(),
            'source': 'realtime',
          },
          eventType: PostgresChangeEvent.insert,
          table: 'vehicle_positions',
          schema: 'public',
          commitTimestamp: DateTime.now().toUtc(),
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      // Assert - ainda não deve ter emitido (dentro da janela de 50ms)
      expect(emissions.length, equals(0));

      // Aguardar janela de debounce completar
      await Future.delayed(const Duration(milliseconds: 60));

      // Assert - deve ter emitido 1 snapshot com última posição
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(1));
      expect(emissions.first.first.id, equals('pos-2'));

      provider.dispose();
    });

    test(
      'IoT Chaos: bulk flood após 4h offline (eventos com occurred_at antigo)',
      () async {
        // Arrange
        final now = DateTime(2026, 4, 15, 14, 0, 0).toUtc();
        final fourHoursAgo = now.subtract(const Duration(hours: 4));
        // Mock retorna tempo próximo aos eventos (dentro do TTL de 2 minutos)
        when(
          () => mockDateTime.nowUtc(),
        ).thenReturn(fourHoursAgo.add(const Duration(seconds: 510)));

        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final emissions = <List<VehiclePosition>>[];
        provider.positionStream.listen(emissions.add);

        await provider.connect();
        await Future.delayed(Duration.zero);

        // Act - simular 500 eventos acumulados de 4h atrás chegando de uma vez
        for (int i = 0; i < 500; i++) {
          final payload = PostgresChangePayload(
            oldRecord: {},
            newRecord: {
              'id': 'pos-old-$i',
              'trip_id': 'trip-${i % 5}',
              'latitude': -23.5,
              'longitude': -46.6,
              'speed': 50.0,
              'heading': 90.0,
              'timestamp': fourHoursAgo
                  .add(Duration(seconds: i))
                  .toIso8601String(),
              'source': 'realtime',
            },
            eventType: PostgresChangeEvent.insert,
            table: 'vehicle_positions',
            schema: 'public',
            commitTimestamp: DateTime.now().toUtc(),
            errors: null,
          );
          provider.onPayloadReceived(payload);
        }

        // Aguardar debounce
        await Future.delayed(const Duration(milliseconds: 60));

        // Assert - deve ter processado e agrupado por tripId
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(5)); // 5 trips diferentes

        // Verificar que são as últimas posições de cada trip
        for (int tripIdx = 0; tripIdx < 5; tripIdx++) {
          final tripId = 'trip-$tripIdx';
          final position = emissions.first.firstWhere(
            (p) => p.tripId == tripId,
          );

          // Última mensagem para este trip
          final expectedLastIndex = 495 + tripIdx;
          expect(position.id, equals('pos-old-$expectedLastIndex'));
        }

        provider.dispose();
      },
    );

    test('buffer não estoura memória com múltiplas atualizações', () async {
      // Arrange
      final baseTime = DateTime(2026, 4, 15, 10, 0, 0).toUtc();
      when(
        () => mockDateTime.nowUtc(),
      ).thenReturn(baseTime.add(const Duration(seconds: 15)));

      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      await provider.connect();
      await Future.delayed(Duration.zero);

      // Act - enviar 10 atualizações para o mesmo tripId
      for (int i = 0; i < 10; i++) {
        final payload = PostgresChangePayload(
          oldRecord: {},
          newRecord: {
            'id': 'pos-$i',
            'trip_id': 'trip-1',
            'latitude': -23.5 + (i * 0.001),
            'longitude': -46.6,
            'speed': 50.0,
            'heading': 90.0,
            'timestamp': baseTime.add(Duration(seconds: i)).toIso8601String(),
            'source': 'realtime',
          },
          eventType: PostgresChangeEvent.insert,
          table: 'vehicle_positions',
          schema: 'public',
          commitTimestamp: DateTime.now().toUtc(),
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      await Future.delayed(const Duration(milliseconds: 60));

      // Assert - deve ter apenas 1 posição no snapshot (última)
      expect(emissions.length, equals(1));
      expect(emissions.first.length, equals(1));
      expect(emissions.first.first.id, equals('pos-9'));

      provider.dispose();
    });
  });
}
