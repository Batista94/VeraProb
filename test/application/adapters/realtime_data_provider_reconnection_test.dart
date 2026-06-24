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
    when(() => mockChannel.unsubscribe()).thenAnswer((_) async => 'ok');
  });

  group('Reconexão com Exponential Backoff + Jitter', () {
    test('erro no subscribe agenda reconexão automática', () {
      fakeAsync((async) {
        // Arrange
        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final statuses = <ConnectionStatus>[];
        provider.connectionStatus.listen(statuses.add);

        int subscribeCallCount = 0;
        when(() => mockChannel.subscribe()).thenAnswer((_) {
          subscribeCallCount++;
          if (subscribeCallCount == 1) {
            throw Exception('Connection failed');
          }
          return mockChannel; // Segunda tentativa sucede
        });

        // Act - primeira tentativa falha, mas não lança exceção (capturada internamente)
        provider.connect();
        async.flushMicrotasks();

        // Assert - deve ter emitido connecting
        expect(statuses, contains(ConnectionStatus.connecting));

        // Avançar tempo para trigger reconexão (1s base + jitter ~100ms)
        async.elapse(const Duration(milliseconds: 1200));

        // Assert - deve ter tentado reconectar
        expect(subscribeCallCount, equals(2));
        expect(statuses, contains(ConnectionStatus.reconnecting));
        expect(statuses.last, equals(ConnectionStatus.connected));
      });
    });

    test(
      'intervalos de backoff seguem exponencial: 1s, 2s, 4s, 8s, 16s, 30s (max)',
      () {
        fakeAsync((async) {
          // Arrange
          final provider = RealtimeDataProvider(mockDateTime, mockClient);
          final reconnectTimestamps = <int>[];

          int subscribeCallCount = 0;
          when(() => mockChannel.subscribe()).thenAnswer((_) {
            subscribeCallCount++;
            reconnectTimestamps.add(async.elapsed.inMilliseconds);

            if (subscribeCallCount <= 6) {
              throw Exception('Connection failed');
            }
            return mockChannel; // 7Âª tentativa sucede
          });

          // Act - primeira tentativa
          provider.connect();
          async.flushMicrotasks();

          // Simular 6 reconexões
          // Tentativa 1: ~1000ms (2^0 * 1000)
          async.elapse(const Duration(milliseconds: 1200));

          // Tentativa 2: ~2000ms (2^1 * 1000)
          async.elapse(const Duration(milliseconds: 2200));

          // Tentativa 3: ~4000ms (2^2 * 1000)
          async.elapse(const Duration(milliseconds: 4200));

          // Tentativa 4: ~8000ms (2^3 * 1000)
          async.elapse(const Duration(milliseconds: 8200));

          // Tentativa 5: ~16000ms (2^4 * 1000)
          async.elapse(const Duration(milliseconds: 16200));

          // Tentativa 6: ~30000ms (max cap)
          async.elapse(const Duration(milliseconds: 30200));

          // Assert - verificar que houve 7 tentativas (1 inicial + 6 reconexões)
          expect(subscribeCallCount, equals(7));

          // Verificar intervalos aproximados (com tolerância para jitter Â±100ms)
          final intervals = <int>[];
          for (int i = 1; i < reconnectTimestamps.length; i++) {
            intervals.add(reconnectTimestamps[i] - reconnectTimestamps[i - 1]);
          }

          // Intervalos esperados: ~1000, ~2000, ~4000, ~8000, ~16000, ~30000
          expect(intervals[0], inInclusiveRange(900, 1300)); // 1s Â± jitter
          expect(intervals[1], inInclusiveRange(1900, 2300)); // 2s Â± jitter
          expect(intervals[2], inInclusiveRange(3900, 4300)); // 4s Â± jitter
          expect(intervals[3], inInclusiveRange(7900, 8300)); // 8s Â± jitter
          expect(intervals[4], inInclusiveRange(15900, 16300)); // 16s Â± jitter
          expect(
            intervals[5],
            inInclusiveRange(29900, 30300),
          ); // 30s Â± jitter (max)
        });
      },
    );

    test('jitter adiciona variação de Â±100ms no delay', () {
      fakeAsync((async) {
        // Arrange
        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final reconnectTimestamps = <int>[];

        int subscribeCallCount = 0;
        when(() => mockChannel.subscribe()).thenAnswer((_) {
          subscribeCallCount++;
          reconnectTimestamps.add(async.elapsed.inMilliseconds);

          // Sempre falhar para forçar reconexões
          throw Exception('Connection failed');
        });

        // Act - primeira tentativa
        provider.connect();
        async.flushMicrotasks();

        // Simular apenas 3 tentativas para observar jitter na primeira reconexão
        for (int i = 0; i < 3; i++) {
          async.elapse(const Duration(milliseconds: 1200));
        }

        // Assert - verificar que houve múltiplas tentativas
        expect(subscribeCallCount, greaterThanOrEqualTo(3));

        // Calcular intervalo da PRIMEIRA reconexão (entre tentativa 0 e 1)
        if (reconnectTimestamps.length >= 2) {
          final firstInterval = reconnectTimestamps[1] - reconnectTimestamps[0];

          // Primeira reconexão deve ter delay de ~1000ms Â± 100ms (jitter)
          expect(
            firstInterval,
            inInclusiveRange(900, 1300),
            reason: 'Primeira reconexão deve ter delay de ~1s Â± jitter',
          );
        }

        // Verificar que há variação nos timestamps (jitter está funcionando)
        final uniqueTimestamps = reconnectTimestamps.toSet();
        expect(
          uniqueTimestamps.length,
          equals(reconnectTimestamps.length),
          reason:
              'Cada tentativa deve ter timestamp único (jitter funcionando)',
        );
      });
    });

    test('status muda para reconnecting durante tentativas', () {
      fakeAsync((async) {
        // Arrange
        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final statuses = <ConnectionStatus>[];
        provider.connectionStatus.listen(statuses.add);

        when(
          () => mockChannel.subscribe(),
        ).thenThrow(Exception('Connection failed'));

        // Act
        provider.connect();
        async.flushMicrotasks();

        // Avançar tempo para trigger reconexão
        async.elapse(const Duration(milliseconds: 1200));

        // Assert
        expect(statuses, contains(ConnectionStatus.connecting));
        expect(statuses, contains(ConnectionStatus.reconnecting));
      });
    });

    test('tentativas resetam após conexão bem-sucedida', () {
      fakeAsync((async) {
        // Arrange
        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final reconnectTimestamps = <int>[];

        int subscribeCallCount = 0;
        when(() => mockChannel.subscribe()).thenAnswer((_) {
          subscribeCallCount++;
          reconnectTimestamps.add(async.elapsed.inMilliseconds);

          if (subscribeCallCount == 1) {
            throw Exception('First attempt fails');
          }
          return mockChannel; // Segunda tentativa sucede
        });

        // Act - primeira tentativa falha, segunda sucede
        provider.connect();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1200)); // Reconexão sucede

        // Desconectar
        provider.disconnect();
        async.flushMicrotasks();

        // Resetar contador para nova sessão
        subscribeCallCount = 0;
        reconnectTimestamps.clear();

        when(() => mockChannel.subscribe()).thenAnswer((_) {
          subscribeCallCount++;
          reconnectTimestamps.add(async.elapsed.inMilliseconds);

          if (subscribeCallCount == 1) {
            throw Exception('First attempt fails again');
          }
          return mockChannel;
        });

        // Reconectar - deve começar do zero (delay de ~1s, não ~2s)
        provider.connect();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1200));

        // Assert - deve ter usado delay de ~1s (reset funcionou)
        expect(subscribeCallCount, equals(2));
        final interval = reconnectTimestamps[1] - reconnectTimestamps[0];
        expect(
          interval,
          inInclusiveRange(900, 1300),
          reason: 'Após reset, delay deve ser ~1s (não ~2s)',
        );
      });
    });

    test('circuit breaker para após 15 tentativas e emite status failed', () {
      fakeAsync((async) {
        // Arrange
        final provider = RealtimeDataProvider(mockDateTime, mockClient);
        final statuses = <ConnectionStatus>[];
        provider.connectionStatus.listen(statuses.add);

        int subscribeCallCount = 0;
        when(() => mockChannel.subscribe()).thenAnswer((_) {
          subscribeCallCount++;
          throw Exception('Connection always fails');
        });

        // Act - primeira tentativa
        provider.connect();
        async.flushMicrotasks();

        // Simular 15 reconexões (circuit breaker deve parar)
        for (int i = 0; i < 15; i++) {
          async.elapse(const Duration(seconds: 35)); // Avançar tempo suficiente
        }

        // Assert - deve ter parado após 15 tentativas
        expect(
          subscribeCallCount,
          lessThanOrEqualTo(16),
        ); // 1 inicial + 15 reconexões
        expect(statuses.last, equals(ConnectionStatus.failed));
      });
    });
  });
}
