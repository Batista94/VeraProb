import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/adapters/realtime_data_provider.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockRealtimeClient extends Mock implements RealtimeClient {}

class MockRealtimeChannel extends Mock implements RealtimeChannel {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

void main() {
  late MockSupabaseClient mockClient;
  late MockRealtimeChannel mockChannel;
  late MockDateTimeProvider mockDateTime;
  late RealtimeDataProvider provider;

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

    provider = RealtimeDataProvider(mockDateTime, mockClient);
  });

  group('ConnectionStatus', () {
    test('connect() emite connecting â†’ connected', () async {
      // Arrange
      final statuses = <ConnectionStatus>[];
      final subscription = provider.connectionStatus.listen(statuses.add);

      // Act
      await provider.connect();
      await Future.delayed(Duration.zero); // Aguarda microtask queue

      // Assert
      expect(statuses, [
        ConnectionStatus.connecting,
        ConnectionStatus.connected,
      ]);

      await subscription.cancel();
    });

    test('disconnect() emite disconnected', () async {
      // Arrange
      await provider.connect();
      await Future.delayed(Duration.zero);

      final statuses = <ConnectionStatus>[];
      final subscription = provider.connectionStatus.listen(statuses.add);

      // Act
      await provider.disconnect();
      await Future.delayed(Duration.zero);

      // Assert
      expect(statuses, contains(ConnectionStatus.disconnected));

      await subscription.cancel();
    });

    test('getter status retorna Ãºltimo valor emitido', () async {
      // Arrange & Act
      expect(provider.status, ConnectionStatus.disconnected);

      await provider.connect();
      await Future.delayed(Duration.zero);
      expect(provider.status, ConnectionStatus.connected);

      await provider.disconnect();
      await Future.delayed(Duration.zero);
      expect(provider.status, ConnectionStatus.disconnected);
    });
  });
}
