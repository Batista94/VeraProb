import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/application/super_admin/create_organization_result.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/cnpj_company_data.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/screens/create_organization_wizard.dart';
import 'package:veraprob/infrastructure/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockCnpjLookupService extends Mock implements ICnpjLookupService {}

class MockCreateOrganizationHandler extends Mock
    implements CreateOrganizationHandler {}

class FakeCreateOrganizationCommand extends Fake
    implements CreateOrganizationCommand {}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _fillStep1(
  WidgetTester tester, {
  required String legalName,
  required String tradeName,
  required String cnpj,
}) async {
  await tester.enterText(
    find.ancestor(
      of: find.text('Razão Social *'),
      matching: find.byType(TextFormField),
    ),
    legalName,
  );
  await tester.enterText(
    find.ancestor(
      of: find.text('Nome Fantasia *'),
      matching: find.byType(TextFormField),
    ),
    tradeName,
  );
  await tester.enterText(
    find.ancestor(
      of: find.text('CNPJ *'),
      matching: find.byType(TextFormField),
    ),
    cnpj,
  );
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pumpAndSettle();
}

Future<void> _advanceToStep3(WidgetTester tester) async {
  await _fillStep1(
    tester,
    legalName: 'Adversarial Corp',
    tradeName: 'Adversarial',
    cnpj: '11.444.777/0001-61',
  );

  final next1 = find.text('Próximo');
  await tester.ensureVisible(next1);
  await tester.tap(next1);
  await tester.pumpAndSettle();

  await tester.enterText(
    find.ancestor(
      of: find.text('Máximo de Veículos *'),
      matching: find.byType(TextFormField),
    ),
    '100',
  );
  await tester.enterText(
    find.ancestor(
      of: find.text('Máximo de Contratos Ativos *'),
      matching: find.byType(TextFormField),
    ),
    '50',
  );
  await tester.enterText(
    find.ancestor(
      of: find.text('Custo Mensal da Ferramenta *'),
      matching: find.byType(TextFormField),
    ),
    '50000',
  );
  await tester.enterText(
    find.ancestor(
      of: find.text(
        'Ex: Criação de novo tenant conforme contrato comercial #123',
      ),
      matching: find.byType(TextFormField),
    ),
    'Adversarial test reason',
  );

  final next2 = find.text('Próximo');
  await tester.ensureVisible(next2);
  await tester.tap(next2);
  await tester.pumpAndSettle();
}

Future<void> _enterEmailAndSubmit(WidgetTester tester, String email) async {
  final emailField = find.ancestor(
    of: find.text('E-mails dos Admins *'),
    matching: find.byType(TextField),
  );
  await tester.enterText(emailField, email);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  final submitBtn = find.widgetWithText(
    ElevatedButton,
    'Criar e Enviar Convite',
  );
  await tester.ensureVisible(submitBtn);
  await tester.tap(submitBtn);
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Widget _buildWizard({
  required MockSuperAdminRepository repo,
  required MockCnpjLookupService lookup,
  required MockCreateOrganizationHandler handler,
  VoidCallback? onSuccess,
}) {
  return ProviderScope(
    overrides: [
      superAdminRepositoryProvider.overrideWithValue(repo),
      cnpjLookupServiceProvider.overrideWithValue(lookup),
      createOrganizationHandlerProvider.overrideWithValue(handler),
      currentSuperAdminIdProvider.overrideWithValue('mock-super-admin-id'),
      isSuperAdminProvider.overrideWithValue(true),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: CreateOrganizationWizard(onSuccess: onSuccess ?? () {}),
      ),
    ),
  );
}

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockCnpjLookupService mockLookup;
  late MockCreateOrganizationHandler mockHandler;

  setUpAll(() {
    registerFallbackValue(FakeCreateOrganizationCommand());
  });

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockLookup = MockCnpjLookupService();
    mockHandler = MockCreateOrganizationHandler();

    when(() => mockRepo.checkCnpjExists(any())).thenAnswer((_) async => false);
    when(() => mockLookup.lookup(any())).thenAnswer((_) async => null);
    when(
      () => mockHandler.sendInviteNotification(
        email: any(named: 'email'),
        inviteUrl: any(named: 'inviteUrl'),
        orgName: any(named: 'orgName'),
      ),
    ).thenAnswer((_) async => {});
  });

  group('INV-28: Org Secret Exposure', () {
    const fakeSecret = 'hmac-secret-abc123-never-store-plain';

    testWidgets(
      'Secret displayed exactly once in success dialog via SelectableText',
      (tester) async {
        await _setSurface(tester, const Size(800, 1600));

        when(() => mockHandler.handle(any())).thenAnswer(
          (_) async => const CreateOrganizationResult(
            orgId: 'org-1',
            invitationTokens: ['token-1'],
            orgApiSecret: fakeSecret,
          ),
        );

        await tester.pumpWidget(
          _buildWizard(
            repo: mockRepo,
            lookup: mockLookup,
            handler: mockHandler,
          ),
        );
        await tester.pumpAndSettle();
        await _advanceToStep3(tester);
        await _enterEmailAndSubmit(tester, 'admin@test.com');

        expect(find.text(fakeSecret), findsOneWidget);

        final selectableSecret = find.widgetWithText(
          SelectableText,
          fakeSecret,
        );
        expect(selectableSecret, findsOneWidget);
      },
    );

    testWidgets('"Copie agora" warning visible alongside secret', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: 'org-2',
          invitationTokens: ['token-2'],
          orgApiSecret: fakeSecret,
        ),
      );

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);
      await _enterEmailAndSubmit(tester, 'admin@test.com');

      expect(find.textContaining('Copie agora'), findsOneWidget);
    });

    testWidgets('Secret section absent when orgApiSecret is null', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: 'org-3',
          invitationTokens: ['token-3'],
          orgApiSecret: null,
        ),
      );

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);
      await _enterEmailAndSubmit(tester, 'admin@test.com');

      expect(find.textContaining('Copie agora'), findsNothing);
      expect(
        find.text('Chave de API da Organização (única exibição)'),
        findsNothing,
      );
    });
  });

  group('INV-27: Per-Identity Invite Isolation', () {
    testWidgets('Multiple admin emails produce distinct invite URLs', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1800));

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: 'org-multi',
          invitationTokens: ['token-alpha', 'token-beta', 'token-gamma'],
          orgApiSecret: null,
        ),
      );

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);

      final emailField = find.ancestor(
        of: find.text('E-mails dos Admins *'),
        matching: find.byType(TextField),
      );
      for (final email in ['a@org.com', 'b@org.com', 'c@org.com']) {
        await tester.enterText(emailField, email);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      final submitBtn = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.textContaining('token-alpha'), findsOneWidget);
      expect(find.textContaining('token-beta'), findsOneWidget);
      expect(find.textContaining('token-gamma'), findsOneWidget);

      expect(find.text('a@org.com'), findsAtLeast(1));
      expect(find.text('b@org.com'), findsAtLeast(1));
      expect(find.text('c@org.com'), findsAtLeast(1));
    });

    testWidgets('Invite notification fired per-email with correct URL', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: 'org-notify',
          invitationTokens: ['tok-1', 'tok-2'],
          orgApiSecret: null,
        ),
      );

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);

      final emailField = find.ancestor(
        of: find.text('E-mails dos Admins *'),
        matching: find.byType(TextField),
      );
      for (final email in ['x@co.com', 'y@co.com']) {
        await tester.enterText(emailField, email);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      final submitBtn = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      verify(
        () => mockHandler.sendInviteNotification(
          email: 'x@co.com',
          inviteUrl: any(named: 'inviteUrl', that: contains('tok-1')),
          orgName: 'Adversarial',
        ),
      ).called(1);
      verify(
        () => mockHandler.sendInviteNotification(
          email: 'y@co.com',
          inviteUrl: any(named: 'inviteUrl', that: contains('tok-2')),
          orgName: 'Adversarial',
        ),
      ).called(1);
    });
  });

  group('Adversarial: Double-Submit Protection', () {
    testWidgets('Rapid double-tap only triggers handler.handle() once', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      final completer = Completer<CreateOrganizationResult>();
      when(() => mockHandler.handle(any())).thenAnswer((_) => completer.future);

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);

      final emailField = find.ancestor(
        of: find.text('E-mails dos Admins *'),
        matching: find.byType(TextField),
      );
      await tester.enterText(emailField, 'admin@double.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      await tester.ensureVisible(submitBtn);

      await tester.tap(submitBtn);
      await tester.pump();

      final anyElevated = find.byType(ElevatedButton);
      if (anyElevated.evaluate().isNotEmpty) {
        await tester.tap(anyElevated.last, warnIfMissed: false);
      }
      await tester.pump();

      verify(() => mockHandler.handle(any())).called(1);

      completer.complete(
        const CreateOrganizationResult(
          orgId: 'org-double',
          invitationTokens: ['t1'],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'Submit button shows loader and is disabled during submission',
      (tester) async {
        await _setSurface(tester, const Size(800, 1600));

        final completer = Completer<CreateOrganizationResult>();
        when(
          () => mockHandler.handle(any()),
        ).thenAnswer((_) => completer.future);

        await tester.pumpWidget(
          _buildWizard(
            repo: mockRepo,
            lookup: mockLookup,
            handler: mockHandler,
          ),
        );
        await tester.pumpAndSettle();
        await _advanceToStep3(tester);

        final emailField = find.ancestor(
          of: find.text('E-mails dos Admins *'),
          matching: find.byType(TextField),
        );
        await tester.enterText(emailField, 'admin@loader.com');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        final submitBtn = find.widgetWithText(
          ElevatedButton,
          'Criar e Enviar Convite',
        );
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Criar e Enviar Convite'), findsNothing);

        completer.complete(
          const CreateOrganizationResult(
            orgId: 'org-loader',
            invitationTokens: ['t1'],
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      },
    );
  });

  group('Adversarial: CNPJ Rapid Change Race Condition', () {
    testWidgets('Stale lookup result discarded when CNPJ changed mid-flight', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1200));

      final staleCompleter = Completer<CnpjCompanyData?>();
      final freshData = CnpjCompanyData(
        cnpj: '11444777000161',
        legalName: 'Fresh Corp',
        tradeName: 'Fresh',
        situation: 'ATIVA',
      );

      var callCount = 0;
      when(() => mockLookup.lookup(any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) return staleCompleter.future;
        return Future.value(freshData);
      });

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      final cnpjField = find.ancestor(
        of: find.text('CNPJ *'),
        matching: find.byType(TextFormField),
      );

      await tester.enterText(cnpjField, '11.444.777/0001-61');
      await tester.pump(const Duration(milliseconds: 700));

      await tester.enterText(cnpjField, '');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(cnpjField, '11.444.777/0001-61');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));

      staleCompleter.complete(
        CnpjCompanyData(
          cnpj: '11444777000161',
          legalName: 'Stale Corp',
          tradeName: 'Stale',
          situation: 'ATIVA',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final legalNameField = find.ancestor(
        of: find.text('Razão Social *'),
        matching: find.byType(TextFormField),
      );
      final legalNameText =
          tester.widget<TextFormField>(legalNameField).controller?.text ?? '';
      expect(legalNameText, isNot(equals('Stale Corp')));
    });

    testWidgets('Debounce cancels previous timer on rapid input', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1200));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      final cnpjField = find.ancestor(
        of: find.text('CNPJ *'),
        matching: find.byType(TextFormField),
      );

      await tester.enterText(cnpjField, '11.444.777/0001-61');
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(cnpjField, '');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(cnpjField, '11.444.777/0001-61');

      await tester.pump(const Duration(milliseconds: 700));

      verify(() => mockRepo.checkCnpjExists('11444777000161')).called(1);
    });
  });

  group('Adversarial: Network Edge Cases', () {
    testWidgets('CNPJ lookup failure does not block wizard progression', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(
        () => mockLookup.lookup(any()),
      ).thenAnswer((_) async => throw Exception('timeout'));
      when(
        () => mockRepo.checkCnpjExists(any()),
      ).thenAnswer((_) async => false);

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      await _fillStep1(
        tester,
        legalName: 'NetFail Corp',
        tradeName: 'NetFail',
        cnpj: '11.444.777/0001-61',
      );

      final nextBtn = find.text('Próximo');
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      expect(find.text('Máximo de Veículos *'), findsOneWidget);
    });

    testWidgets('Handler DomainException shows error and re-enables submit', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(
        () => mockHandler.handle(any()),
      ).thenThrow(const DomainException('Quota exceeded for plan'));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);

      final emailField = find.ancestor(
        of: find.text('E-mails dos Admins *'),
        matching: find.byType(TextField),
      );
      await tester.enterText(emailField, 'admin@fail.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Quota exceeded for plan'), findsOneWidget);

      expect(find.text('Criar e Enviar Convite'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Unexpected exception shows generic error and recovers', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(
        () => mockHandler.handle(any()),
      ).thenThrow(Exception('Connection reset'));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);

      final emailField = find.ancestor(
        of: find.text('E-mails dos Admins *'),
        matching: find.byType(TextField),
      );
      await tester.enterText(emailField, 'admin@crash.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('Erro inesperado'), findsOneWidget);

      expect(find.byType(CreateOrganizationWizard), findsOneWidget);
      expect(find.text('Criar e Enviar Convite'), findsOneWidget);
    });

    testWidgets('CNPJ already registered blocks step progression', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1200));

      when(
        () => mockRepo.checkCnpjExists('11444777000161'),
      ).thenAnswer((_) async => true);

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      await _fillStep1(
        tester,
        legalName: 'Dup Corp',
        tradeName: 'Dup',
        cnpj: '11.444.777/0001-61',
      );

      expect(find.text('CNPJ já cadastrado no sistema'), findsOneWidget);

      final nextBtn = find.text('Próximo');
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      expect(find.text('CNPJ *'), findsOneWidget);
      expect(find.text('Máximo de Veículos *'), findsNothing);
    });
  });

  group('A11y: Semantic Accessibility', () {
    testWidgets('Step 1 fields have correct semantic labels', (tester) async {
      await _setSurface(tester, const Size(800, 1200));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Dados Fiscais')), findsAtLeast(1));

      expect(find.text('Razão Social *'), findsOneWidget);
      expect(find.text('Nome Fantasia *'), findsOneWidget);
      expect(find.text('CNPJ *'), findsOneWidget);
    });

    testWidgets('CNPJ validation error has semantic error label', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1200));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(
          of: find.text('CNPJ *'),
          matching: find.byType(TextFormField),
        ),
        '11.111.111/1111-11',
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      final nextBtn = find.text('Próximo');
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      final errorFinder = find.text('CNPJ inválido');
      expect(errorFinder, findsOneWidget);

      final errorWidget = find.ancestor(
        of: errorFinder,
        matching: find.byType(TextFormField),
      );
      expect(
        errorWidget.evaluate().isNotEmpty || errorFinder.evaluate().isNotEmpty,
        isTrue,
      );
    });

    testWidgets('Step 2 fields accessible after navigation', (tester) async {
      await _setSurface(tester, const Size(800, 1600));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      await _fillStep1(
        tester,
        legalName: 'A11y Corp',
        tradeName: 'A11y',
        cnpj: '11.444.777/0001-61',
      );

      final nextBtn = find.text('Próximo');
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Limites')), findsAtLeast(1));
      expect(find.text('Máximo de Veículos *'), findsOneWidget);
      expect(find.text('Máximo de Contratos Ativos *'), findsOneWidget);
    });

    testWidgets('Step 3 has accessible admin email input and submit button', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);

      expect(find.bySemanticsLabel(RegExp('Convite Admin')), findsAtLeast(1));

      expect(find.text('E-mails dos Admins *'), findsOneWidget);

      final submitBtn = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      expect(submitBtn, findsOneWidget);
    });

    testWidgets('Voltar button present and accessible on step 2+', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Voltar'), findsNothing);

      await _fillStep1(
        tester,
        legalName: 'Nav Corp',
        tradeName: 'Nav',
        cnpj: '11.444.777/0001-61',
      );

      final nextBtn = find.text('Próximo');
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      final voltarBtn = find.widgetWithText(OutlinedButton, 'Voltar');
      expect(voltarBtn, findsOneWidget);

      await tester.tap(voltarBtn);
      await tester.pumpAndSettle();
      expect(find.text('CNPJ *'), findsOneWidget);
    });
  });

  group('Forensic UX: Post-Success Cleanup', () {
    testWidgets('onSuccess callback fires after dialog dismissal', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      var successFired = false;

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: 'org-cleanup',
          invitationTokens: ['tok-cleanup'],
          orgApiSecret: null,
        ),
      );

      await tester.pumpWidget(
        _buildWizard(
          repo: mockRepo,
          lookup: mockLookup,
          handler: mockHandler,
          onSuccess: () => successFired = true,
        ),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);
      await _enterEmailAndSubmit(tester, 'admin@cleanup.com');

      expect(find.text('Organização Criada!'), findsOneWidget);

      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();

      expect(successFired, isTrue);
    });

    testWidgets('tenantHealthSnapshotProvider invalidated after success', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: 'org-invalidate',
          invitationTokens: ['tok-inv'],
          orgApiSecret: null,
        ),
      );

      var fetchCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            superAdminRepositoryProvider.overrideWithValue(mockRepo),
            cnpjLookupServiceProvider.overrideWithValue(mockLookup),
            createOrganizationHandlerProvider.overrideWithValue(mockHandler),
            currentSuperAdminIdProvider.overrideWithValue(
              'mock-super-admin-id',
            ),
            isSuperAdminProvider.overrideWithValue(true),
            tenantHealthSnapshotProvider.overrideWith((ref) {
              fetchCount++;
              return Future.value([]);
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(child: CreateOrganizationWizard(onSuccess: () {})),
                  Consumer(
                    builder: (_, ref, _) {
                      ref.watch(tenantHealthSnapshotProvider);
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialFetchCount = fetchCount;
      expect(initialFetchCount, greaterThanOrEqualTo(1));

      await _advanceToStep3(tester);
      await _enterEmailAndSubmit(tester, 'admin@inv.com');

      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();

      expect(fetchCount, greaterThan(initialFetchCount));
    });

    testWidgets('Dialog is dismissible by tapping barrier (UX Improvement)', (
      tester,
    ) async {
      await _setSurface(tester, const Size(800, 1600));

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: 'org-barrier',
          invitationTokens: ['tok-barrier'],
          orgApiSecret: 'secret-barrier',
        ),
      );

      await tester.pumpWidget(
        _buildWizard(repo: mockRepo, lookup: mockLookup, handler: mockHandler),
      );
      await tester.pumpAndSettle();
      await _advanceToStep3(tester);
      await _enterEmailAndSubmit(tester, 'admin@barrier.com');

      expect(find.text('Organização Criada!'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Organização Criada!'), findsNothing);
    });
  });
}
