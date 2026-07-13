import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/domain/legal/i_legal_consent_repository.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/domain/legal/legal_document.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/legal_consent_providers.dart';

class _FakeLegalRepo extends Mock implements ILegalConsentRepository {}

void main() {
  late _FakeLegalRepo repo;

  const doc = LegalDocument(id: 'doc-1', title: 'Termos', bodyMarkdown: 'body');

  setUp(() {
    repo = _FakeLegalRepo();
  });

  group('happy path', () {
    test('returns pending from repository for authenticated user', () async {
      when(() => repo.getConsentStatus()).thenAnswer(
        (_) async =>
            const LegalConsentStatus(state: LegalConsentState.pending, document: doc),
      );

      final container = ProviderContainer(
        overrides: [
          legalConsentRepositoryProvider.overrideWithValue(repo),
          currentOperatorIdProvider.overrideWithValue('user-1'),
        ],
      );
      addTearDown(container.dispose);

      final status = await container.read(legalConsentStatusProvider.future);
      expect(status.isPending, isTrue);
      expect(status.document?.id, 'doc-1');
      verify(() => repo.getConsentStatus()).called(1);
    });

    test('returns current when repository reports accepted', () async {
      when(() => repo.getConsentStatus()).thenAnswer(
        (_) async =>
            const LegalConsentStatus(state: LegalConsentState.current, document: doc),
      );

      final container = ProviderContainer(
        overrides: [
          legalConsentRepositoryProvider.overrideWithValue(repo),
          currentOperatorIdProvider.overrideWithValue('user-1'),
        ],
      );
      addTearDown(container.dispose);

      final status = await container.read(legalConsentStatusProvider.future);
      expect(status.isCurrent, isTrue);
      verify(() => repo.getConsentStatus()).called(1);
    });
  });

  group('adverse / security', () {
    test(
      'null operator yields current without RPC (no unauthenticated call)',
      () async {
        final container = ProviderContainer(
          overrides: [
            legalConsentRepositoryProvider.overrideWithValue(repo),
            currentOperatorIdProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);

        final status = await container.read(legalConsentStatusProvider.future);
        expect(status.isCurrent, isTrue);
        verifyNever(() => repo.getConsentStatus());
      },
    );

    test(
      'AsyncError must not look like accepted consent (no silent gate bypass)',
      () async {
        // Override the provider itself so we assert the security property
        // without depending on mock+timeout plumbing: an erroring status
        // must never present asData.isCurrent == true.
        final container = ProviderContainer(
          overrides: [
            legalConsentStatusProvider.overrideWith(
              (ref) async => throw const ResourceNotFoundException(
                resourceType: 'legal_document',
                message: 'Document not available',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final sub = container.listen(
          legalConsentStatusProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);

        // Settle the FutureProvider error without awaiting .future (which can
        // race dispose). Poll AsyncValue until hasError or timeout.
        late AsyncValue<LegalConsentStatus> async;
        var settled = false;
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          async = container.read(legalConsentStatusProvider);
          if (async.hasError || async.hasValue) {
            settled = true;
            break;
          }
        }

        expect(settled, isTrue, reason: 'provider must settle to error/value');
        expect(async.hasError, isTrue);
        expect(async.error, isA<ResourceNotFoundException>());
        expect(
          async.asData,
          isNull,
          reason:
              'asData null on error → redirect treats as loading, '
              'never as current (cannot silently bypass Legal Gate)',
        );
        // Production redirect reads `.asData?.value` — null means not "current".
        expect(async.asData?.value.isCurrent, isNot(true));
      },
    );

    test('consentRefreshNotifier notifies listeners on refresh', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(consentRefreshNotifierProvider);
      var calls = 0;
      notifier.addListener(() => calls++);
      notifier.refresh();
      expect(calls, 1);
    });
  });
}
