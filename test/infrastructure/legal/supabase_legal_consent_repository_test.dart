import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/infrastructure/legal/supabase_legal_consent_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  final Future<dynamic> _future;

  FakePostgrestFilterBuilder.value(dynamic result)
    : _future = Future.value(result);
  FakePostgrestFilterBuilder.error(Object error)
    : _future = Future.error(error);

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic) onValue, {
    Function? onError,
  }) {
    return _future.then(onValue, onError: onError);
  }

  @override
  Future<dynamic> catchError(Function onError, {bool Function(Object)? test}) {
    return _future.catchError(onError, test: test);
  }
}

void main() {
  late _MockSupabaseClient mockClient;
  late SupabaseLegalConsentRepository repo;

  setUp(() {
    mockClient = _MockSupabaseClient();
    repo = SupabaseLegalConsentRepository(mockClient);
  });

  group('getConsentStatus', () {
    test('returns current state when RPC returns null/non-map', () async {
      when(
        () => mockClient.rpc<dynamic>('get_legal_consent_status'),
      ).thenAnswer((_) => FakePostgrestFilterBuilder.value(null));

      final status = await repo.getConsentStatus();

      expect(status.state, LegalConsentState.current);
      expect(status.document, isNull);
    });

    test(
      'returns pending state with document and all fields mapped correctly',
      () async {
        final docMap = {
          'id': 'doc-123',
          'doc_type': 'privacy_policy',
          'version': '1.0',
          'title': 'Privacy Policy',
          'body_markdown': 'Privacy Body',
          'content_sha256': 'sha256_hash',
          'changelog': 'Initial release',
          'published_at_utc': '2026-07-09T10:00:00Z',
        };
        final responseMap = {
          'status': 'pending',
          'prior_version': '0.9',
          'document': docMap,
        };

        when(
          () => mockClient.rpc<dynamic>('get_legal_consent_status'),
        ).thenAnswer((_) => FakePostgrestFilterBuilder.value(responseMap));

        final status = await repo.getConsentStatus();

        expect(status.state, LegalConsentState.pending);
        expect(status.document, isNotNull);

        final doc = status.document!;
        expect(doc.id, 'doc-123');
        expect(doc.title, 'Privacy Policy');
        expect(doc.bodyMarkdown, 'Privacy Body');
        expect(doc.changelog, 'Initial release');
      },
    );

    test('maps missing map fields to defaults in _documentFromMap', () async {
      final docMap = {
        'id': 'doc-999',
        // Missing many fields to trigger defaults
      };
      final responseMap = {'status': 'pending', 'document': docMap};

      when(
        () => mockClient.rpc<dynamic>('get_legal_consent_status'),
      ).thenAnswer((_) => FakePostgrestFilterBuilder.value(responseMap));

      final status = await repo.getConsentStatus();
      final doc = status.document!;

      expect(doc.id, 'doc-999');
      expect(doc.title, '', reason: 'Default fallback');
      expect(doc.bodyMarkdown, '', reason: 'Default fallback');
      expect(doc.changelog, isNull);
    });

    test('throws mapped error on PostgrestException', () async {
      const err = PostgrestException(message: 'Database error', code: 'P0001');
      when(
        () => mockClient.rpc<dynamic>('get_legal_consent_status'),
      ).thenAnswer((_) => FakePostgrestFilterBuilder.error(err));

      expect(repo.getConsentStatus(), throwsA(isA<Exception>()));
    });
  });

  group('acceptTerms', () {
    test('calls RPC correctly', () async {
      when(
        () => mockClient.rpc<dynamic>(
          'accept_legal_terms',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder.value(null));

      await repo.acceptTerms('doc-123');

      verify(
        () => mockClient.rpc<dynamic>(
          'accept_legal_terms',
          params: const {'p_document_id': 'doc-123'},
        ),
      ).called(1);
    });

    test('throws ResourceNotFoundException on P0002 code', () async {
      const err = PostgrestException(message: 'Some error', code: 'P0002');
      when(
        () => mockClient.rpc<dynamic>(
          'accept_legal_terms',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder.error(err));

      expect(
        repo.acceptTerms('doc-123'),
        throwsA(
          isA<ResourceNotFoundException>()
              .having((e) => e.resourceId, 'resourceId', 'doc-123')
              .having((e) => e.resourceType, 'resourceType', 'legal_document')
              .having((e) => e.message, 'message', 'Document not available'),
        ),
      );
    });

    test(
      'throws ResourceNotFoundException on document not available message',
      () async {
        const err = PostgrestException(
          message: 'ERROR: document not available for user',
          code: 'P0001',
        );
        when(
          () => mockClient.rpc<dynamic>(
            'accept_legal_terms',
            params: any(named: 'params'),
          ),
        ).thenAnswer((_) => FakePostgrestFilterBuilder.error(err));

        expect(
          repo.acceptTerms('doc-123'),
          throwsA(
            isA<ResourceNotFoundException>()
                .having((e) => e.resourceId, 'resourceId', 'doc-123')
                .having((e) => e.message, 'message', 'Document not available'),
          ),
        );
      },
    );

    test('throws DomainException for other Postgrest exceptions', () async {
      const err = PostgrestException(message: 'Other db error', code: 'P0001');
      when(
        () => mockClient.rpc<dynamic>(
          'accept_legal_terms',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder.error(err));

      expect(
        repo.acceptTerms('doc-123'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains('Document not available')),
          ),
        ),
      );
    });
  });
}
