// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:veraprob/features/super_admin/domain/cnpj_exceptions.dart';
import 'package:veraprob/infrastructure/shared/services/receitaws_service.dart';
import 'package:veraprob/features/super_admin/infrastructure/cnpj_infrastructure_exceptions.dart';

void main() {
  group('ReceitaWsService — CIA Resilience Suite', () {
    late ReceitaWsService sut;

    // ── C: CONFIDENTIALITY ───────────────────────────────────────────────────
    // Typed exceptions must not carry raw response data (INV-28).

    group('C — Confidentiality: Exception Field Sanitization', () {
      test(
        '[HTTP 500] ExternalApiException carries no raw body tokens',
        () async {
          const sensitiveBody =
              '{"error": "DB error at https://internal.receitaws.com.br/admin",'
              ' "debug": "Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig",'
              ' "apiKey": "rws_sk_prod_abc123xyz"}';

          sut = ReceitaWsService(
            client: MockClient((_) async => http.Response(sensitiveBody, 500)),
          );

          final exception = await _capture(
            () => sut.fetchCompanyByCnpj('12345678000190'),
          );

          expect(exception, isA<ExternalApiException>());
          final str = exception.toString();
          expect(str, isNot(contains('Bearer')));
          expect(str, isNot(contains('apiKey')));
          expect(str, isNot(contains('internal.receitaws')));
        },
      );

      test(
        '[HTTP 400] ExternalApiException carries no internal URLs from body',
        () async {
          const leakyBody =
              '{"message": "Bad Request",'
              ' "internalEndpoint": "https://priv-api.receitaws.com.br/debug",'
              ' "secret": "prod-secret-2024"}';

          sut = ReceitaWsService(
            client: MockClient((_) async => http.Response(leakyBody, 400)),
          );

          final exception = await _capture(
            () => sut.fetchCompanyByCnpj('12345678000190'),
          );

          expect(exception, isA<ExternalApiException>());
          final str = exception.toString();
          expect(str, isNot(contains('priv-api')));
          expect(str, isNot(contains('prod-secret')));
        },
      );

      test(
        '[status=ERROR] InvalidCnpjException is opaque — no API message leaked',
        () async {
          sut = ReceitaWsService(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'status': 'ERROR',
                  'message': 'CNPJ 12345678000190 nao encontrado na base',
                }),
                200,
              ),
            ),
          );

          final exception = await _capture(
            () => sut.fetchCompanyByCnpj('12345678000190'),
          );

          expect(exception, isA<InvalidCnpjException>());
          // INV-26: API rejection message must not escape exception boundary.
          expect(
            exception.toString(),
            isNot(contains('nao encontrado na base')),
          );
          expect(exception.toString(), isNot(contains('12345678000190')));
        },
      );
    });

    // ── I: INTEGRITY ─────────────────────────────────────────────────────────
    // Parser must throw typed exceptions on dirty payloads; CNPJ sanitized.

    group('I — Integrity: Forensic Parsing & Input Sanitization', () {
      test(
        '[False Positive HTTP 200] status=ERROR → InvalidCnpjException',
        () async {
          sut = ReceitaWsService(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({'status': 'ERROR', 'message': 'CNPJ inválido'}),
                200,
              ),
            ),
          );

          expect(
            () => sut.fetchCompanyByCnpj('12345678000190'),
            throwsA(isA<InvalidCnpjException>()),
          );
        },
      );

      test(
        '[HTML Gateway Response] Cloudflare 502 HTML → DataParsingException',
        () async {
          const html =
              '<html><body><h1>502 Bad Gateway</h1>'
              '<p>nginx/cloudflare</p></body></html>';

          sut = ReceitaWsService(
            client: MockClient((_) async => http.Response(html, 200)),
          );

          await expectLater(
            () => sut.fetchCompanyByCnpj('12345678000190'),
            throwsA(isA<DataParsingException>()),
          );
        },
      );

      test('[Contract Drift] Truncated JSON → DataParsingException', () async {
        sut = ReceitaWsService(
          client: MockClient(
            (_) async => http.Response('{"status": "OK", "cnpj": "123"', 200),
          ),
        );

        await expectLater(
          () => sut.fetchCompanyByCnpj('12345678000190'),
          throwsA(isA<DataParsingException>()),
        );
      });

      test(
        '[Contract Drift] Empty JSON array instead of object → DataParsingException',
        () async {
          sut = ReceitaWsService(
            client: MockClient((_) async => http.Response('[]', 200)),
          );

          await expectLater(
            () => sut.fetchCompanyByCnpj('12345678000190'),
            throwsA(isA<DataParsingException>()),
          );
        },
      );

      test(
        '[Null Payload] Empty response body → DataParsingException',
        () async {
          sut = ReceitaWsService(
            client: MockClient((_) async => http.Response('', 200)),
          );

          await expectLater(
            () => sut.fetchCompanyByCnpj('12345678000190'),
            throwsA(isA<DataParsingException>()),
          );
        },
      );

      test(
        '[Input Sanitization] Short CNPJ after stripping → InvalidCnpjException',
        () async {
          sut = ReceitaWsService(
            client: MockClient(
              (_) async => throw AssertionError('must not reach network'),
            ),
          );

          await expectLater(
            () => sut.fetchCompanyByCnpj('12.345/01'),
            throwsA(isA<InvalidCnpjException>()),
          );
        },
      );

      test(
        '[Input Sanitization] Only digits reach URL — punctuation stripped',
        () async {
          Uri? capturedUri;

          sut = ReceitaWsService(
            client: MockClient((request) async {
              capturedUri = request.url;
              return http.Response(
                jsonEncode({
                  'status': 'OK',
                  'cnpj': '12.345.678/0001-99',
                  'nome': 'EMPRESA TESTE',
                  'fantasia': 'TESTE',
                }),
                200,
              );
            }),
          );

          await sut.fetchCompanyByCnpj('12.345.678/0001-99');

          expect(capturedUri, isNotNull);
          final segment = capturedUri!.pathSegments.last;
          expect(segment, equals('12345678000199'));
          expect(segment, isNot(contains('.')));
          expect(segment, isNot(contains('-')));
        },
      );

      test(
        '[Input Sanitization] Leading/trailing spaces stripped before URL',
        () async {
          Uri? capturedUri;

          sut = ReceitaWsService(
            client: MockClient((request) async {
              capturedUri = request.url;
              return http.Response(
                jsonEncode({
                  'status': 'OK',
                  'cnpj': '12345678000190',
                  'nome': 'EMPRESA TESTE',
                  'fantasia': 'TESTE',
                }),
                200,
              );
            }),
          );

          await sut.fetchCompanyByCnpj('  12345678000190  ');

          expect(capturedUri!.pathSegments.last, equals('12345678000190'));
        },
      );

      test(
        '[Schema Missing Fields] Absent nome/fantasia defaults to empty string',
        () async {
          sut = ReceitaWsService(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({'status': 'OK', 'cnpj': '12345678000190'}),
                200,
              ),
            ),
          );

          final result = await sut.fetchCompanyByCnpj('12345678000190');

          expect(result, isNotNull);
          expect(result?.nome, equals(''));
          expect(result?.fantasia, equals(''));
        },
      );
    });

    // ── A: AVAILABILITY ──────────────────────────────────────────────────────
    // Each network/HTTP failure maps to the correct typed exception.

    group('A — Availability: Network Resilience', () {
      test(
        '[Happy Path] Valid CNPJ maps to ReceitaCompanyData correctly',
        () async {
          sut = ReceitaWsService(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'status': 'OK',
                  'cnpj': '12.345.678/0001-90',
                  'nome': 'VIAÇÃO COMETA AZUL LTDA',
                  'fantasia': 'COMETA AZUL',
                }),
                200,
              ),
            ),
          );

          final result = await sut.fetchCompanyByCnpj('12345678000190');

          expect(result, isNotNull);
          expect(result?.cnpj, equals('12.345.678/0001-90'));
          expect(result?.nome, equals('VIAÇÃO COMETA AZUL LTDA'));
          expect(result?.fantasia, equals('COMETA AZUL'));
        },
      );

      test('[Timeout] TimeoutException → ServiceTimeoutException', () async {
        sut = ReceitaWsService(
          client: MockClient(
            (_) async => throw TimeoutException(
              'ReceitaWS did not respond',
              const Duration(seconds: 10),
            ),
          ),
        );

        await expectLater(
          () => sut.fetchCompanyByCnpj('12345678000190'),
          throwsA(isA<ServiceTimeoutException>()),
        );
      });

      test(
        '[SocketException] Network unreachable → ExternalApiException',
        () async {
          sut = ReceitaWsService(
            client: MockClient(
              (_) async =>
                  throw const SocketException('Network is unreachable'),
            ),
          );

          await expectLater(
            () => sut.fetchCompanyByCnpj('12345678000190'),
            throwsA(isA<ExternalApiException>()),
          );
        },
      );

      test('[HTTP 429] Rate limit → RateLimitExceededException', () async {
        sut = ReceitaWsService(
          client: MockClient(
            (_) async => http.Response('Too Many Requests', 429),
          ),
        );

        await expectLater(
          () => sut.fetchCompanyByCnpj('12345678000190'),
          throwsA(isA<RateLimitExceededException>()),
        );
      });

      test('[HTTP 503] Service unavailable → ExternalApiException', () async {
        sut = ReceitaWsService(
          client: MockClient(
            (_) async => http.Response('Service Unavailable', 503),
          ),
        );

        await expectLater(
          () => sut.fetchCompanyByCnpj('12345678000190'),
          throwsA(isA<ExternalApiException>()),
        );
      });

      test('[HTTP 301] Unexpected redirect → ExternalApiException', () async {
        sut = ReceitaWsService(
          client: MockClient(
            (_) async => http.Response('Moved Permanently', 301),
          ),
        );

        await expectLater(
          () => sut.fetchCompanyByCnpj('12345678000190'),
          throwsA(isA<ExternalApiException>()),
        );
      });

      test(
        '[All infrastructure errors] CnpjLookupException base catches all fault paths',
        () async {
          final scenarios = <Future<void> Function()>[
            () async => expectLater(
              () => ReceitaWsService(
                client: MockClient((_) async => http.Response('', 503)),
              ).fetchCompanyByCnpj('12345678000190'),
              throwsA(isA<CnpjLookupException>()),
            ),
            () async => expectLater(
              () => ReceitaWsService(
                client: MockClient(
                  (_) async => http.Response('Too Many Requests', 429),
                ),
              ).fetchCompanyByCnpj('12345678000190'),
              throwsA(isA<CnpjLookupException>()),
            ),
            () async => expectLater(
              () => ReceitaWsService(
                client: MockClient(
                  (_) async => throw const SocketException('err'),
                ),
              ).fetchCompanyByCnpj('12345678000190'),
              throwsA(isA<CnpjLookupException>()),
            ),
          ];

          for (final scenario in scenarios) {
            await scenario();
          }
        },
      );
    });
  });
}

/// Captures a thrown [CnpjLookupException] from [fn]. Fails the test if no
/// exception is thrown or if a different exception type is caught.
Future<CnpjLookupException> _capture(Future<Object?> Function() fn) async {
  try {
    await fn();
    fail('Expected CnpjLookupException but none was thrown');
  } on CnpjLookupException catch (e) {
    return e;
  }
}
