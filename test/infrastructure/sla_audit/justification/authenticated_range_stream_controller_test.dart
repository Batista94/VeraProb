import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/authenticated_range_stream_controller.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('AuthenticatedRangeStreamController — 206 Kill-Stream Enforcement', () {
    late MockHttpClient mockClient;
    late AuthenticatedRangeStreamController controller;
    var clientClosed = false;

    setUp(() {
      mockClient = MockHttpClient();
      clientClosed = false;

      // Track close() calls without actually closing
      when(() => mockClient.close()).thenAnswer((_) {
        clientClosed = true;
      });

      controller = AuthenticatedRangeStreamController(
        bearerTokenFactory: () => 'Bearer test-token',
        clientFactory: () => mockClient,
      );
    });

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(<String, String>{});
    });

    test('returns bytes on 206 Partial Content', () async {
      final payload = [1, 2, 3, 4, 5];
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response.bytes(payload, 206));

      final result = await controller.fetchRange(
        url: 'https://storage.example.com/file.png',
        start: 0,
        length: 5,
      );

      expect(result, equals(payload));
      verifyNever(() => mockClient.close());
    });

    test(
      'kill-stream: calls client.close() immediately on non-206 — no bytes buffered',
      () async {
        when(
          () => mockClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('', 200));

        await expectLater(
          () => controller.fetchRange(
            url: 'https://storage.example.com/huge-500mb.png',
            start: 0,
            length: 128 * 1024,
          ),
          throwsA(isA<DomainException>()),
        );

        expect(
          clientClosed,
          isTrue,
          reason: 'client.close() must be called on non-206',
        );
      },
    );

    test('kill-stream: error message contains 206 and URL', () async {
      const url = 'https://storage.example.com/no-range-support.png';
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('', 200));

      await expectLater(
        () => controller.fetchRange(url: url, start: 0, length: 1024),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(contains('206'), contains(url)),
          ),
        ),
      );
    });

    test('kill-stream: calls client.close() on 404 response', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('Not Found', 404));

      await expectLater(
        () => controller.fetchRange(
          url: 'https://storage.example.com/missing.png',
          start: 0,
          length: 1024,
        ),
        throwsA(isA<DomainException>()),
      );

      expect(clientClosed, isTrue);
    });

    test('sends correct Range header', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response.bytes([0, 1], 206));

      await controller.fetchRange(
        url: 'https://storage.example.com/file.png',
        start: 1000,
        length: 500,
      );

      final captured = verify(
        () => mockClient.get(any(), headers: captureAny(named: 'headers')),
      ).captured;
      final headers = captured.first as Map<String, String>;
      expect(headers['Range'], equals('bytes=1000-1499'));
      expect(headers['Authorization'], equals('Bearer test-token'));
    });
  });
}
