import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';

// Standalone SUT — EvidenceValidationService has no dependency on the
// JustificationTestHarness, so this suite stays pure: a single local mock,
// no shared-helper import, fast isolated run.
class MockEvidenceLinkChecker extends Mock implements EvidenceLinkChecker {}

/// Link-reachability behavior for [EvidenceValidationService]: how it maps the
/// underlying [EvidenceLinkChecker] results to validation outcomes, preserves
/// order, and short-circuits on empty input.
void main() {
  late MockEvidenceLinkChecker mockChecker;
  late EvidenceValidationService validationService;

  setUp(() {
    mockChecker = MockEvidenceLinkChecker();
    validationService = EvidenceValidationService(mockChecker);
  });

  test('returns available status for reachable URL', () async {
    when(() => mockChecker.checkLink(any())).thenAnswer(
      (invocation) async => EvidenceValidationResult(
        url: invocation.positionalArguments[0] as String,
        status: EvidenceLinkStatus.available,
        httpStatusCode: 200,
      ),
    );

    final results = await validationService.validateLinks([
      'https://storage.supabase.co/evidence/photo1.jpg',
    ]);

    expect(results, hasLength(1));
    expect(results.first.status, EvidenceLinkStatus.available);
    expect(results.first.httpStatusCode, 200);
  });

  test('returns missing status for 404 URL', () async {
    when(() => mockChecker.checkLink(any())).thenAnswer(
      (_) async => const EvidenceValidationResult(
        url: 'https://storage.supabase.co/evidence/deleted.jpg',
        status: EvidenceLinkStatus.missing,
        httpStatusCode: 404,
      ),
    );

    final results = await validationService.validateLinks([
      'https://storage.supabase.co/evidence/deleted.jpg',
    ]);

    expect(results.first.status, EvidenceLinkStatus.missing);
  });

  test('returns forbidden status for 403 URL', () async {
    when(() => mockChecker.checkLink(any())).thenAnswer(
      (_) async => const EvidenceValidationResult(
        url: 'https://storage.supabase.co/evidence/restricted.jpg',
        status: EvidenceLinkStatus.forbidden,
        httpStatusCode: 403,
      ),
    );

    final results = await validationService.validateLinks([
      'https://storage.supabase.co/evidence/restricted.jpg',
    ]);

    expect(results.first.status, EvidenceLinkStatus.forbidden);
  });

  test('validates all URLs in parallel and preserves order', () async {
    final urls = [
      'https://storage.supabase.co/evidence/a.jpg',
      'https://storage.supabase.co/evidence/b.jpg',
      'https://storage.supabase.co/evidence/c.jpg',
    ];

    var callIndex = 0;
    final statuses = [
      EvidenceLinkStatus.available,
      EvidenceLinkStatus.missing,
      EvidenceLinkStatus.forbidden,
    ];

    when(() => mockChecker.checkLink(any())).thenAnswer((invocation) async {
      final idx = callIndex++;
      return EvidenceValidationResult(
        url: invocation.positionalArguments[0] as String,
        status: statuses[idx],
      );
    });

    final results = await validationService.validateLinks(urls);

    expect(results, hasLength(3));
    expect(results[0].status, EvidenceLinkStatus.available);
    expect(results[1].status, EvidenceLinkStatus.missing);
    expect(results[2].status, EvidenceLinkStatus.forbidden);
  });

  test('returns empty list for empty URL input', () async {
    final results = await validationService.validateLinks([]);
    expect(results, isEmpty);
    verifyNever(() => mockChecker.checkLink(any()));
  });

  test(
    'returns error status when checker encounters network failure',
    () async {
      when(() => mockChecker.checkLink(any())).thenAnswer(
        (_) async => const EvidenceValidationResult(
          url: 'https://storage.supabase.co/evidence/unreachable.jpg',
          status: EvidenceLinkStatus.error,
          httpStatusCode: null,
        ),
      );

      final results = await validationService.validateLinks([
        'https://storage.supabase.co/evidence/unreachable.jpg',
      ]);

      expect(results.first.status, EvidenceLinkStatus.error);
      expect(results.first.httpStatusCode, isNull);
    },
  );
}
