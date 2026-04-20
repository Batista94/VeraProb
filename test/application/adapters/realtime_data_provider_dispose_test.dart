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
    ).thenReturn(DateTime.utc(2026, 4, 15, 16, 21));
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

  group('Limpeza de Recursos', () {
    test('dispose cancela timer de reconexÃ£o', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);

      // ForÃ§ar erro para agendar reconexÃ£o
      when(
        () => mockChannel.subscribe(),
      ).thenThrow(Exception('connection failed'));

      try {
        await provider.connect();
      } catch (_) {}

      // Dispose deve cancelar timer
      provider.dispose();

      // Aguardar tempo que seria de reconexÃ£o
      await Future.delayed(const Duration(seconds: 2));

      // NÃ£o deve ter tentado reconectar
      verify(
        () => mockChannel.subscribe(),
      ).called(1); // Apenas tentativa inicial
    });

    test('dispose cancela timer de debounce', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      // Enviar payload que agendaria debounce
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
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);

      // Dispose antes do debounce disparar
      provider.dispose();

      // Aguardar tempo de debounce
      await Future.delayed(const Duration(milliseconds: 100));

      // NÃ£o deve ter emitido (timer cancelado)
      expect(emissions, isEmpty);
    });

    test('dispose fecha stream de posiÃ§Ãµes', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      bool streamClosed = false;
      provider.positionStream.listen((_) {}, onDone: () => streamClosed = true);

      provider.dispose();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamClosed, isTrue);
    });

    test('dispose fecha stream de status', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      bool streamClosed = false;
      provider.connectionStatus.listen(
        (_) {},
        onDone: () => streamClosed = true,
      );

      provider.dispose();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamClosed, isTrue);
    });

    test('dispose limpa buffers', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      final emissions = <List<VehiclePosition>>[];
      provider.positionStream.listen(emissions.add);

      // Adicionar posiÃ§Ãµes ao buffer
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
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        errors: null,
      );

      provider.onPayloadReceived(payload);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(emissions, isNotEmpty);

      provider.dispose();

      // Tentar adicionar apÃ³s dispose nÃ£o deve causar erro
      expect(() => provider.onPayloadReceived(payload), returnsNormally);
    });

    test('dispose desconecta canal Supabase', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      provider.dispose();

      verify(() => mockChannel.unsubscribe()).called(1);
    });

    test('dispose pode ser chamado mÃºltiplas vezes sem erro', () async {
      final provider = RealtimeDataProvider(mockDateTime, mockClient);
      await provider.connect();

      expect(() {
        provider.dispose();
        provider.dispose();
        provider.dispose();
      }, returnsNormally);
    });
  });
}
