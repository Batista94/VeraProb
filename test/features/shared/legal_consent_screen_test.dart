import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/legal/i_legal_consent_repository.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/domain/legal/legal_document.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/features/shared/presentation/legal_consent_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/legal_consent_providers.dart';

class _FakeLegalRepo extends Mock implements ILegalConsentRepository {}

class _FakeAuthRepo extends Mock implements IAuthRepository {}

LegalDocument get _doc => const LegalDocument(
  id: 'doc-1',
  title: 'Termos de Uso e Contrato de Custódia de Dados',
  bodyMarkdown: 'Corpo dos termos LGPD — custódia de dados.',
  changelog: 'Atualização de transparência Telegram.',
);

void main() {
  late _FakeLegalRepo legalRepo;
  late _FakeAuthRepo authRepo;

  setUpAll(() {
    registerFallbackValue('doc-1');
  });

  setUp(() {
    legalRepo = _FakeLegalRepo();
    authRepo = _FakeAuthRepo();
    when(() => legalRepo.getConsentStatus()).thenAnswer(
      (_) async =>
          LegalConsentStatus(state: LegalConsentState.pending, document: _doc),
    );
    when(() => legalRepo.acceptTerms(any())).thenAnswer((_) async {});
    when(() => authRepo.signOut()).thenAnswer((_) async {});
  });

  Widget buildSubject({LegalConsentStatus? statusOverride}) {
    return ProviderScope(
      overrides: [
        legalConsentRepositoryProvider.overrideWithValue(legalRepo),
        legalConsentStatusProvider.overrideWith(
          (ref) async =>
              statusOverride ??
              LegalConsentStatus(
                state: LegalConsentState.pending,
                document: _doc,
              ),
        ),
        authRepositoryProvider.overrideWithValue(authRepo),
      ],
      child: const MaterialApp(home: LegalConsentScreen()),
    );
  }

  group('happy path', () {
    testWidgets('renders title, body, and changelog', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('Termos de Uso'), findsWidgets);
      expect(find.textContaining('Corpo dos termos LGPD'), findsOneWidget);
      expect(find.text('O que mudou nesta versão'), findsOneWidget);
      expect(
        find.textContaining('Atualização de transparência Telegram'),
        findsOneWidget,
      );
    });

    testWidgets('Accept disabled until checkbox checked', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      final acceptFinder = find.widgetWithText(FilledButton, 'Aceitar');
      expect(tester.widget<FilledButton>(acceptFinder).onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      expect(tester.widget<FilledButton>(acceptFinder).onPressed, isNotNull);
    });

    testWidgets('Accept calls repository with document id', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Aceitar'));
      await tester.pumpAndSettle();

      verify(() => legalRepo.acceptTerms('doc-1')).called(1);
    });
  });

  group('adverse', () {
    testWidgets('accept failure shows domain error — never raw exception', (
      tester,
    ) async {
      when(() => legalRepo.acceptTerms(any())).thenThrow(
        const ResourceNotFoundException(
          resourceType: 'legal_document',
          message: 'Document not available',
        ),
      );

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Aceitar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Não foi possível registrar seu aceite'),
        findsWidgets,
      );
      expect(find.textContaining('ResourceNotFoundException'), findsNothing);
      expect(find.textContaining('Document not available'), findsNothing);
    });

    testWidgets('missing document shows load error — no raw stack', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          statusOverride: const LegalConsentStatus(
            state: LegalConsentState.pending,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Não foi possível carregar os Termos'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('Decline cancel does not signOut', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Recusar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => authRepo.signOut());
    });
  });

  group('security / consent integrity', () {
    testWidgets('Decline confirm triggers signOut (no silent stay)', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Recusar'));
      await tester.pumpAndSettle();
      expect(find.text('Recusar e sair'), findsOneWidget);
      await tester.tap(find.text('Recusar e sair'));
      await tester.pumpAndSettle();

      verify(() => authRepo.signOut()).called(1);
    });

    testWidgets('checkbox label references LGPD (informed accept)', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('LGPD'), findsWidgets);
      expect(find.textContaining('13.709'), findsOneWidget);
    });

    testWidgets('header omits SHA chip to reduce cognitive load', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('SHA '), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('first-time pending hides changelog callout', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          statusOverride: const LegalConsentStatus(
            state: LegalConsentState.pending,
            document: LegalDocument(
              id: 'doc-1',
              title: 'Termos de Uso e Contrato de Custódia de Dados',
              bodyMarkdown: 'Corpo dos termos LGPD — custódia de dados.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('O que mudou nesta versão'), findsNothing);
    });
  });
}
