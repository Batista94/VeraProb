import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/super_admin/cnpj_exceptions.dart';
import 'package:veraprob/infrastructure/super_admin/cnpj_infrastructure_exceptions.dart';
import 'package:veraprob/infrastructure/super_admin/receita_ws_cnpj_service.dart';

import 'receita_ws_cnpj_service_test.mocks.dart';

@GenerateMocks([SupabaseClient, FunctionsClient])
void main() {
  late MockSupabaseClient mockSupabaseClient;
  late MockFunctionsClient mockFunctionsClient;
  late ReceitaWsCnpjService service;

  setUp(() {
    mockSupabaseClient = MockSupabaseClient();
    mockFunctionsClient = MockFunctionsClient();

    when(mockSupabaseClient.functions).thenReturn(mockFunctionsClient);

    service = ReceitaWsCnpjService(mockSupabaseClient);
  });

  group('ReceitaWsCnpjService — Enterprise Resilience Suite', () {
    const validCnpj = '45518855000147';

    group('Happy Path & Contract', () {
      test('lookup returns CnpjCompanyData on success', () async {
        when(
          mockFunctionsClient.invoke(
            'super-admin-proxy',
            body: anyNamed('body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            status: 200,
            data: {
              'data': {
                'cnpj': validCnpj,
                'legalName': 'Viação Cometa Azul',
                'tradeName': 'Cometa Azul',
                'situation': 'ATIVA',
              },
            },
          ),
        );

        final result = await service.lookup(validCnpj);

        expect(result, isNotNull);
        expect(result!.cnpj, equals(validCnpj));
        expect(result.legalName, equals('Viação Cometa Azul'));
        expect(result.tradeName, equals('Cometa Azul'));
        expect(result.situation, equals('ATIVA'));
      });

      test(
        'lookup returns null when proxy returns data:null (not found)',
        () async {
          when(
            mockFunctionsClient.invoke(any, body: anyNamed('body')),
          ).thenAnswer(
            (_) async => FunctionResponse(status: 200, data: {'data': null}),
          );

          final result = await service.lookup(validCnpj);

          expect(result, isNull);
        },
      );
    });

    group('C — Confidentiality (INV-28)', () {
      test(
        'ExternalApiException does not leak raw status code in message',
        () async {
          when(
            mockFunctionsClient.invoke(any, body: anyNamed('body')),
          ).thenAnswer((_) async => FunctionResponse(status: 503));

          final exception = await _capture(() => service.lookup(validCnpj));

          expect(exception, isA<ExternalApiException>());
          expect(exception.toString(), isNot(contains('503')));
          expect(
            (exception as ExternalApiException).sanitizedCode,
            equals('upstream_server_error'),
          );
        },
      );
    });

    group('I — Integrity & Forensic Parsing', () {
      test('throws InvalidCnpjException if CNPJ length != 14', () async {
        await expectLater(
          () => service.lookup('123'),
          throwsA(
            isA<InvalidCnpjException>().having(
              (e) => e.reason,
              'reason',
              'invalid_format',
            ),
          ),
        );
      });

      test(
        'throws InvalidCnpjException when API returns status=ERROR',
        () async {
          when(
            mockFunctionsClient.invoke(any, body: anyNamed('body')),
          ).thenAnswer(
            (_) async => FunctionResponse(
              status: 200,
              data: {
                'data': {'status': 'ERROR', 'message': 'Invalid'},
              },
            ),
          );

          await expectLater(
            () => service.lookup(validCnpj),
            throwsA(
              isA<InvalidCnpjException>().having(
                (e) => e.reason,
                'reason',
                'api_status_error',
              ),
            ),
          );
        },
      );

      test(
        'throws DataParsingException on unexpected response shape',
        () async {
          when(
            mockFunctionsClient.invoke(any, body: anyNamed('body')),
          ).thenAnswer(
            (_) async => FunctionResponse(status: 200, data: 'not-a-map'),
          );

          await expectLater(
            () => service.lookup(validCnpj),
            throwsA(isA<DataParsingException>()),
          );
        },
      );

      test(
        'throws DataParsingException on contract drift (TypeError)',
        () async {
          when(
            mockFunctionsClient.invoke(any, body: anyNamed('body')),
          ).thenAnswer(
            (_) async => FunctionResponse(
              status: 200,
              data: {
                'data': {
                  'legalName': 123, // Should be String
                },
              },
            ),
          );

          await expectLater(
            () => service.lookup(validCnpj),
            throwsA(
              isA<DataParsingException>().having(
                (e) => e.field,
                'field',
                'legalName',
              ),
            ),
          );
        },
      );
    });

    group('A — Availability & Network Resilience', () {
      test('throws ServiceTimeoutException on TimeoutException', () async {
        when(
          mockFunctionsClient.invoke(any, body: anyNamed('body')),
        ).thenThrow(TimeoutException('timeout'));

        await expectLater(
          () => service.lookup(validCnpj),
          throwsA(isA<ServiceTimeoutException>()),
        );
      });

      test('throws RateLimitExceededException on 429 status', () async {
        when(
          mockFunctionsClient.invoke(any, body: anyNamed('body')),
        ).thenAnswer((_) async => FunctionResponse(status: 429));

        await expectLater(
          () => service.lookup(validCnpj),
          throwsA(isA<RateLimitExceededException>()),
        );
      });

      test(
        'throws ExternalApiException on generic FunctionException',
        () async {
          when(
            mockFunctionsClient.invoke(any, body: anyNamed('body')),
          ).thenThrow(FunctionException(status: 500));

          await expectLater(
            () => service.lookup(validCnpj),
            throwsA(isA<ExternalApiException>()),
          );
        },
      );
    });
  });
}

Future<CnpjLookupException> _capture(Future<Object?> Function() fn) async {
  try {
    await fn();
    fail('Expected CnpjLookupException but none was thrown');
  } on CnpjLookupException catch (e) {
    return e;
  }
}
