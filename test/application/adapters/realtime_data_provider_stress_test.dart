import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/adapters/realtime_data_provider.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

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
    ).thenReturn(DateTime.utc(2026, 4, 15, 16, 28));
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

  group('Stress Testing & Circuit Breaker', () {
    test('circuit breaker ativa após 15 falhas consecutivas', () {
      fakeAsync((async) {
        final provider = RealtimeDataProvider(mockDateTime, mockClient);

        // Forçar falha em todas as tentativas
        when(
          () => mockChannel.subscribe(),
        ).thenThrow(Exception('connection failed'));

        final statusChanges = <ConnectionStatus>[];
        provider.connectionStatus.listen(statusChanges.add);

        // Primeira tentativa
        try {
          provider.connect();
        } catch (_) {}

        // Avançar tempo para todas as 15 tentativas
        // 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s, 30s, 30s, 30s, 30s, 30s, 30s, 30s
        async.elapse(const Duration(seconds: 2)); // Tentativa 1 (com jitter)
        async.elapse(const Duration(seconds: 3)); // Tentativa 2
        async.elapse(const Duration(seconds: 5)); // Tentativa 3
        async.elapse(const Duration(seconds: 9)); // Tentativa 4
        async.elapse(const Duration(seconds: 17)); // Tentativa 5
        async.elapse(const Duration(seconds: 31)); // Tentativa 6
        async.elapse(const Duration(seconds: 31)); // Tentativa 7
        async.elapse(const Duration(seconds: 31)); // Tentativa 8
        async.elapse(const Duration(seconds: 31)); // Tentativa 9
        async.elapse(const Duration(seconds: 31)); // Tentativa 10
        async.elapse(const Duration(seconds: 31)); // Tentativa 11
        async.elapse(const Duration(seconds: 31)); // Tentativa 12
        async.elapse(const Duration(seconds: 31)); // Tentativa 13
        async.elapse(const Duration(seconds: 31)); // Tentativa 14
        async.elapse(const Duration(seconds: 31)); // Tentativa 15

        // Verificar que status final é 'failed'
        expect(statusChanges.last, ConnectionStatus.failed);
        expect(
          statusChanges.where((s) => s == ConnectionStatus.reconnecting).length,
          greaterThanOrEqualTo(14),
        );

        provider.dispose();
      });
    });

    test('circuit breaker não tenta reconectar após status failed', () {
      fakeAsync((async) {
        final provider = RealtimeDataProvider(mockDateTime, mockClient);

        when(
          () => mockChannel.subscribe(),
        ).thenThrow(Exception('connection failed'));

        // Forçar 15 falhas
        try {
          provider.connect();
        } catch (_) {}

        // Avançar tempo para 15 tentativas
        async.elapse(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 9));
        async.elapse(const Duration(seconds: 17));
        for (int i = 0; i < 10; i++) {
          async.elapse(const Duration(seconds: 31));
        }

        // Resetar contador de chamadas
        reset(mockChannel);
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Avançar mais tempo - não deve haver novas tentativas
        async.elapse(const Duration(seconds: 60));

        // Verificar que subscribe não foi chamado novamente
        verifyNever(() => mockChannel.subscribe());

        provider.dispose();
      });
    });

    test('suporta 1000 payloads simultâneos sem perda', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      final emissions = <List<dynamic>>[];
      provider.positionStream.listen(emissions.add);

      // Enviar 1000 payloads rapidamente
      for (int i = 0; i < 1000; i++) {
        final payload = PostgresChangePayload(
          schema: 'public',
          table: 'vehicle_positions',
          commitTimestamp: DateTime.now().toUtc(),
          eventType: PostgresChangeEvent.insert,
          oldRecord: {},
          newRecord: {
            'trip_id': 'trip-$i',
            'latitude': -23.5505 + (i * 0.0001),
            'longitude': -46.6333 + (i * 0.0001),
            'timestamp': DateTime.now()
                .toUtc()
                .add(Duration(seconds: i))
                .toIso8601String(),
          },
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      // Aguardar debounce
      await Future.delayed(const Duration(milliseconds: 100));

      // Verificar que todas as posições foram processadas
      expect(emissions, isNotEmpty);
      final lastSnapshot = emissions.last;
      expect(lastSnapshot.length, 1000);

      provider.dispose();
    });

    test('mantém performance com buffer de 5000 posições', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      final emissions = <List<dynamic>>[];
      provider.positionStream.listen(emissions.add);

      // Preencher buffer com 5000 posições
      for (int i = 0; i < 5000; i++) {
        final payload = PostgresChangePayload(
          schema: 'public',
          table: 'vehicle_positions',
          commitTimestamp: DateTime.now().toUtc(),
          eventType: PostgresChangeEvent.insert,
          oldRecord: {},
          newRecord: {
            'trip_id': 'trip-$i',
            'latitude': -23.5505,
            'longitude': -46.6333,
            'timestamp': DateTime.now()
                .toUtc()
                .add(Duration(seconds: i))
                .toIso8601String(),
          },
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      await Future.delayed(const Duration(milliseconds: 100));

      // Adicionar nova posição e verificar que é processada rapidamente
      final startTime = DateTime.now().toUtc();

      final newPayload = PostgresChangePayload(
        schema: 'public',
        table: 'vehicle_positions',
        commitTimestamp: DateTime.now().toUtc(),
        eventType: PostgresChangeEvent.insert,
        oldRecord: {},
        newRecord: {
          'trip_id': 'trip-new',
          'latitude': -23.5505,
          'longitude': -46.6333,
          'timestamp': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 5001))
              .toIso8601String(),
        },
        errors: null,
      );
      provider.onPayloadReceived(newPayload);

      await Future.delayed(const Duration(milliseconds: 100));

      final processingTime = DateTime.now().toUtc().difference(startTime);

      // Processamento deve ser rápido mesmo com buffer grande
      expect(processingTime.inMilliseconds, lessThan(200));
      expect(emissions.last.any((p) => p.tripId == 'trip-new'), isTrue);

      provider.dispose();
    });

    test('recupera de desconexão durante alta carga', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      final emissions = <List<dynamic>>[];
      provider.positionStream.listen(emissions.add);

      // Enviar 100 payloads
      for (int i = 0; i < 100; i++) {
        final payload = PostgresChangePayload(
          schema: 'public',
          table: 'vehicle_positions',
          commitTimestamp: DateTime.now().toUtc(),
          eventType: PostgresChangeEvent.insert,
          oldRecord: {},
          newRecord: {
            'trip_id': 'trip-$i',
            'latitude': -23.5505,
            'longitude': -46.6333,
            'timestamp': DateTime.now()
                .toUtc()
                .add(Duration(seconds: i))
                .toIso8601String(),
          },
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      await Future.delayed(const Duration(milliseconds: 100));
      final beforeDisconnect = emissions.length;

      // Desconectar
      await provider.disconnect();

      // Reconectar
      await provider.connect();

      // Enviar mais 100 payloads
      for (int i = 100; i < 200; i++) {
        final payload = PostgresChangePayload(
          schema: 'public',
          table: 'vehicle_positions',
          commitTimestamp: DateTime.now().toUtc(),
          eventType: PostgresChangeEvent.insert,
          oldRecord: {},
          newRecord: {
            'trip_id': 'trip-$i',
            'latitude': -23.5505,
            'longitude': -46.6333,
            'timestamp': DateTime.now()
                .toUtc()
                .add(Duration(seconds: i))
                .toIso8601String(),
          },
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      await Future.delayed(const Duration(milliseconds: 100));

      // Verificar que continuou processando após reconexão
      expect(emissions.length, greaterThan(beforeDisconnect));
      expect(emissions.last.length, 100); // Buffer foi limpo no disconnect

      provider.dispose();
    });

    test('TTL remove posições antigas sob carga contínua', () async {
      // Mock que avança no tempo
      var currentTime = DateTime.utc(2026, 4, 15, 16, 28);
      when(() => mockDateTime.nowUtc()).thenAnswer((_) => currentTime);

      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      final emissions = <List<dynamic>>[];
      provider.positionStream.listen(emissions.add);

      // Enviar posições antigas (3 minutos atrás)
      for (int i = 0; i < 50; i++) {
        final payload = PostgresChangePayload(
          schema: 'public',
          table: 'vehicle_positions',
          commitTimestamp: DateTime.now().toUtc(),
          eventType: PostgresChangeEvent.insert,
          oldRecord: {},
          newRecord: {
            'trip_id': 'trip-old-$i',
            'latitude': -23.5505,
            'longitude': -46.6333,
            'timestamp': currentTime
                .subtract(const Duration(minutes: 3))
                .toIso8601String(),
          },
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      await Future.delayed(const Duration(milliseconds: 100));

      // Avançar o tempo do mock
      currentTime = currentTime.add(const Duration(seconds: 1));

      // Enviar posições recentes
      for (int i = 0; i < 50; i++) {
        final payload = PostgresChangePayload(
          schema: 'public',
          table: 'vehicle_positions',
          commitTimestamp: DateTime.now().toUtc(),
          eventType: PostgresChangeEvent.insert,
          oldRecord: {},
          newRecord: {
            'trip_id': 'trip-new-$i',
            'latitude': -23.5505,
            'longitude': -46.6333,
            'timestamp': currentTime.toIso8601String(),
          },
          errors: null,
        );
        provider.onPayloadReceived(payload);
      }

      await Future.delayed(const Duration(milliseconds: 100));

      // Verificar que apenas posições recentes estão no buffer
      final lastSnapshot = emissions.last;
      expect(lastSnapshot.length, 50); // Apenas as recentes
      expect(
        lastSnapshot.every((p) => p.tripId.startsWith('trip-new')),
        isTrue,
      );

      provider.dispose();
    });
  });
}
