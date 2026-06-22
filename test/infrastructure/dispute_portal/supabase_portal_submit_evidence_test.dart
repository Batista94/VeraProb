import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_dispute_gateway.dart';

/// Unit coverage for [SupabasePortalDisputeGateway.submitEvidence]. The real
/// `functions.invoke` returns a 2xx [FunctionResponse] or THROWS
/// [FunctionException] for any non-2xx; these tests drive that contract through
/// the [EdgeFunctionInvoker] seam (the gateway's only previously-untested path).
void main() {
  const portalToken = 'a0000000-0000-4000-8000-000000000000';
  const validJustification = 'Justificativa de contestacao valida e completa.';

  final staged = StagedFile(
    name: 'evidence.pdf',
    sizeBytes: 4,
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3, 4]),
  );

  // SupabaseClient is unused on the seam path; a throwing stub guards against any
  // accidental real call leaking past the injected invoker.
  final SupabaseClient client = _UnusableClient();

  SupabasePortalDisputeGateway gateway({
    required EdgeFunctionInvoker invoke,
    http.Client? httpClient,
  }) => SupabasePortalDisputeGateway(
    client,
    httpClient: httpClient,
    invoker: invoke,
  );

  MockClient putOk() => MockClient((_) async => http.Response('', 200));

  group('submitEvidence — infra vs business classification', () {
    test('phase-1 503 → retryable PortalDisputeException', () async {
      final g = gateway(
        invoke: (name, {body}) async =>
            throw const FunctionException(status: 503),
      );
      await expectLater(
        g.submitEvidence(
          token: portalToken,
          justification: validJustification,
          file: null,
          sha256Client: null,
        ),
        throwsA(
          isA<PortalDisputeException>().having(
            (e) => e.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
    });

    test(
      'phase-1 404 → NON-retryable PortalDisputeException (INV-26)',
      () async {
        final g = gateway(
          invoke: (name, {body}) async =>
              throw const FunctionException(status: 404),
        );
        await expectLater(
          g.submitEvidence(
            token: portalToken,
            justification: validJustification,
            file: null,
            sha256Client: null,
          ),
          throwsA(
            isA<PortalDisputeException>().having(
              (e) => e.retryable,
              'retryable',
              isFalse,
            ),
          ),
        );
      },
    );
  });

  group('submitEvidence — finalize outcome mapping', () {
    Future<FunctionResponse> Function(String, {Object? body}) twoPhase(
      Future<FunctionResponse> Function() finalize,
    ) {
      return (name, {body}) {
        if (name == 'portal-submit-request') {
          return Future.value(
            FunctionResponse(
              data: {'submissionId': 'sub-1', 'signedUrl': null},
              status: 200,
            ),
          );
        }
        return finalize();
      };
    }

    test('finalize 200 → pendingAudit', () async {
      final g = gateway(
        invoke: twoPhase(
          () async => FunctionResponse(data: {'ok': true}, status: 200),
        ),
      );
      expect(
        await g.submitEvidence(
          token: portalToken,
          justification: validJustification,
          file: null,
          sha256Client: null,
        ),
        PortalSubmissionOutcome.pendingAudit,
      );
    });

    test('finalize 422 hash mismatch → hashMismatch', () async {
      final g = gateway(
        invoke: twoPhase(
          () async => throw const FunctionException(
            status: 422,
            details: {'error': 'Hash mismatch'},
          ),
        ),
      );
      expect(
        await g.submitEvidence(
          token: portalToken,
          justification: validJustification,
          file: null,
          sha256Client: null,
        ),
        PortalSubmissionOutcome.hashMismatch,
      );
    });

    test('finalize 422 content-type mismatch → mimeMismatch', () async {
      final g = gateway(
        invoke: twoPhase(
          () async => throw const FunctionException(
            status: 422,
            details: {'error': 'Content type mismatch'},
          ),
        ),
      );
      expect(
        await g.submitEvidence(
          token: portalToken,
          justification: validJustification,
          file: null,
          sha256Client: null,
        ),
        PortalSubmissionOutcome.mimeMismatch,
      );
    });

    test(
      'finalize 404 → pendingAudit (idempotent: already promoted)',
      () async {
        final g = gateway(
          invoke: twoPhase(
            () async => throw const FunctionException(status: 404),
          ),
        );
        expect(
          await g.submitEvidence(
            token: portalToken,
            justification: validJustification,
            file: null,
            sha256Client: null,
          ),
          PortalSubmissionOutcome.pendingAudit,
        );
      },
    );
  });

  test('happy path with file: phase-1 200 + PUT 200 + finalize 200 → '
      'pendingAudit', () async {
    final g = gateway(
      httpClient: putOk(),
      invoke: (name, {body}) async {
        if (name == 'portal-submit-request') {
          return FunctionResponse(
            data: {
              'submissionId': 'sub-1',
              'signedUrl': 'http://127.0.0.1:54321/storage/v1/upload/sub-1',
            },
            status: 200,
          );
        }
        return FunctionResponse(data: {'ok': true}, status: 200);
      },
    );
    final sha = base64Url.encode(List<int>.filled(32, 7));
    expect(
      await g.submitEvidence(
        token: portalToken,
        justification: validJustification,
        file: staged,
        sha256Client: sha,
      ),
      PortalSubmissionOutcome.pendingAudit,
    );
  });
}

/// Throws on any member access — proves the seam never falls through to a real
/// Supabase call in these tests.
class _UnusableClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('real SupabaseClient must not be used in this test');
}
