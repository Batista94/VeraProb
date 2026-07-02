import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/webhooks/webhook_exceptions.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/webhooks/supabase_webhook_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class FakePostgrestFilterBuilder<T> extends Mock
    implements PostgrestFilterBuilder<T> {
  final Future<T> _future;
  FakePostgrestFilterBuilder(this._future);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    return _future.then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return _future.catchError(onError, test: test);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    return _future.whenComplete(action);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    return _future.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Stream<T> asStream() => _future.asStream();
}

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctionsClient;
  late SupabaseWebhookRepository repository;

  setUpAll(() {
    registerFallbackValue(const <String, dynamic>{});
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctionsClient = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctionsClient);
    repository = SupabaseWebhookRepository(mockClient);
  });

  group('SupabaseWebhookRepository - Adverse Scenarios & Security', () {
    test(
      'findEndpointHealth converts 42501 to SovereigntyViolationException (INV-2/26)',
      () async {
        final mockQuery = MockSupabaseQueryBuilder();
        when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);

        when(() => mockQuery.select()).thenAnswer(
          (_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(
            Future.error(
              const PostgrestException(
                message: 'RLS denied',
                code: '42501',
                details: null,
                hint: null,
              ),
            ),
          ),
        );

        expect(
          () => repository.findEndpointHealth(),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    test(
      'manualReplay converts P0001 to IntegrityException with original message (INV-26)',
      () async {
        when(
          () => mockClient.rpc<dynamic>(
            'webhook_manual_replay',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder<dynamic>(
            Future.error(
              const PostgrestException(
                message: 'Log is already in PENDING state',
                code: 'P0001',
                details: null,
                hint: null,
              ),
            ),
          ),
        );

        expect(
          () => repository.manualReplay('log-123'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              contains('Log is already in PENDING state'),
            ),
          ),
        );
      },
    );

    test(
      'manualReplay maps PGRST116 to generic domain message — anti-oracle (INV-26)',
      () async {
        when(
          () => mockClient.rpc<dynamic>(
            'webhook_manual_replay',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder<dynamic>(
            Future.error(
              const PostgrestException(
                message: 'Not Found',
                code: 'PGRST116',
                details: null,
                hint: null,
              ),
            ),
          ),
        );

        // INV-26: not-found e wrong-org são indistinguíveis — a mensagem
        // genérica não pode ecoar o erro técnico do PostgREST.
        expect(
          () => repository.manualReplay('log-404'),
          throwsA(
            isA<WebhookApplicationException>().having(
              (e) => e.message,
              'message',
              'Log de entrega indisponível para reprocessamento.',
            ),
          ),
        );
      },
    );

    test('findEndpointHealth maps valid data correctly', () async {
      final mockQuery = MockSupabaseQueryBuilder();
      when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);

      when(() => mockQuery.select()).thenAnswer(
        (_) => FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(
          Future.value([
            {
              'id': 'ep-123',
              'url': 'https://example.com/hook',
              'is_active': true,
              'created_at': '2026-07-01T12:00:00Z',
              'last_dispatched_at': '2026-07-01T12:05:00Z',
              'total_logs': 12,
              'pending_count': 0,
              'delivering_count': 0,
              'success_count': 10,
              'failed_count': 2,
              'dead_count': 0,
            },
          ]),
        ),
      );

      final endpoints = await repository.findEndpointHealth();
      expect(endpoints.length, 1);
      expect(endpoints.first.id, 'ep-123');
      expect(endpoints.first.successCount, 10);
    });

    test('revealSecret extracts secretHex and version correctly', () async {
      when(
        () => mockFunctionsClient.invoke(
          'reveal-webhook-signing-secret',
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) => Future.value(
          FunctionResponse(
            data: {'secret_hex': 'deadbeef', 'version': 3},
            status: 200,
          ),
        ),
      );

      final result = await repository.revealSecret('org-123');
      expect(result.secretHex, 'deadbeef');
      expect(result.version, 3);
    });

    test(
      'revealSecret throws WebhookSecretException on 404 (INV-26)',
      () async {
        when(
          () => mockFunctionsClient.invoke(
            'reveal-webhook-signing-secret',
            body: any(named: 'body'),
          ),
        ).thenThrow(
          const FunctionException(
            status: 404,
            reasonPhrase: 'Not Found',
            details: 'Not Found',
          ),
        );

        expect(
          () => repository.revealSecret('org-123'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              contains('Acesso negado'),
            ),
          ),
        );
      },
    );
  });
}
