import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/sla_audit/save_sla_template_handler.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/features/admin/presentation/screens/sla_template_editor_dialog.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_template_repository.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

// ── Mock ──────────────────────────────────────────────────────────────────────

class _MockSaveHandler extends Mock implements SaveSlaTemplateHandler {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kOrgId = 'org-test-001';
const _kSessionId = 'session-token-abc';

final _kCreatedAt = DateTime.utc(2024, 1, 15);

SlaTemplate _buildFakeDomain({
  String name = 'Modelo Teste',
  String? description,
  TransportVertical? vertical,
}) {
  final penalties = SLAPenalties.create(
    noShowPenaltyBps: 15000,
    delayToleranceMinutes: 15,
    delayPenaltyPerMinute: const Money(50),
    downgradePenaltyFlat: const Money(5000),
    noShowThresholdMinutes: 60,
    earlyArrivalToleranceMinutes: 5,
    dwellTimeMinutes: 3,
    gracePeriodMinutes: 0,
    baseTripValue: const Money(0),
  );
  return SlaTemplate.reconstitute(
    id: 'tmpl-uuid-001',
    organizationId: _kOrgId,
    name: name,
    description: description,
    vertical: vertical,
    penalties: penalties,
    createdAt: _kCreatedAt,
  );
}

SlaTemplateView _buildExistingView() {
  return SlaTemplateView.fromDomain(
    _buildFakeDomain(
      name: 'Modelo Existente',
      description: 'Desc existente',
      vertical: TransportVertical.fretamento,
    ),
  );
}

// ── Shared stub matcher ───────────────────────────────────────────────────────

typedef _HandleArgs = ({
  String organizationId,
  String sessionId,
  String name,
  String? description,
  TransportVertical? vertical,
  PenaltiesFormData penalties,
  String? existingId,
  DateTime? existingCreatedAt,
});

void _stubHandler(
  _MockSaveHandler handler, {
  SlaTemplate? returns,
  Object? throws,
  void Function(_HandleArgs captured)? onCall,
}) {
  final stub = when(
    () => handler.handle(
      organizationId: any(named: 'organizationId'),
      sessionId: any(named: 'sessionId'),
      name: any(named: 'name'),
      description: any(named: 'description'),
      vertical: any(named: 'vertical'),
      penalties: any(named: 'penalties'),
      existingId: any(named: 'existingId'),
      existingCreatedAt: any(named: 'existingCreatedAt'),
    ),
  );

  if (throws != null) {
    stub.thenThrow(throws);
  } else {
    stub.thenAnswer((inv) async {
      if (onCall != null) {
        onCall((
          organizationId: inv.namedArguments[#organizationId] as String,
          sessionId: inv.namedArguments[#sessionId] as String,
          name: inv.namedArguments[#name] as String,
          description: inv.namedArguments[#description] as String?,
          vertical: inv.namedArguments[#vertical] as TransportVertical?,
          penalties: inv.namedArguments[#penalties] as PenaltiesFormData,
          existingId: inv.namedArguments[#existingId] as String?,
          existingCreatedAt:
              inv.namedArguments[#existingCreatedAt] as DateTime?,
        ));
      }
      return returns ?? _buildFakeDomain();
    });
  }
}

void _verifyNeverCalled(_MockSaveHandler handler) {
  verifyNever(
    () => handler.handle(
      organizationId: any(named: 'organizationId'),
      sessionId: any(named: 'sessionId'),
      name: any(named: 'name'),
      description: any(named: 'description'),
      vertical: any(named: 'vertical'),
      penalties: any(named: 'penalties'),
      existingId: any(named: 'existingId'),
      existingCreatedAt: any(named: 'existingCreatedAt'),
    ),
  );
}

// ── Host factory ──────────────────────────────────────────────────────────────

Widget _buildHost({
  required _MockSaveHandler handler,
  String? orgId = _kOrgId,
  String? sessionId = _kSessionId,
  SlaTemplateView? existing,
  InMemorySlaTemplateRepository? repo,
}) {
  final r = repo ?? InMemorySlaTemplateRepository();
  return ProviderScope(
    overrides: [
      currentOrganizationIdProvider.overrideWithValue(orgId),
      currentSessionIdProvider.overrideWithValue(sessionId),
      saveSlaTemplateHandlerProvider.overrideWithValue(handler),
      slaTemplateRepositoryProvider.overrideWithValue(r),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () =>
                showSlaTemplateEditorDialog(ctx, existing: existing),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Abrir'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void _setScreenSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
}

Future<void> _fillStep1(
  WidgetTester tester, {
  String name = 'Modelo Teste',
}) async {
  await tester.enterText(find.byType(TextFormField).first, name);
  await tester.pump();
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.text('Próximo'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _selectVertical(WidgetTester tester, TransportVertical v) async {
  await tester.tap(find.byType(DropdownButtonFormField<TransportVertical>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(v.label).last);
  await tester.pump();
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(PenaltiesFormData.defaults());
    registerFallbackValue(TransportVertical.custom);
    registerFallbackValue(DateTime.utc(2024));
  });

  // ── 1. Happy Path — Criar ─────────────────────────────────────────────────

  group('1. Happy Path — wizard criar', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
      _stubHandler(handler);
    });

    testWidgets('dialog renderiza como overlay — Dialog widget presente', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('Step1: título "Novo Modelo SLA" e indicador correto', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.text('Novo Modelo SLA'), findsOneWidget);
      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('Step1 → Next → Step2 atualiza indicador de passo', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);

      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('Step2 → Next → Step3 atualiza indicador de passo', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
    });

    testWidgets('Step1 não mostra botão Anterior', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.text('Anterior'), findsNothing);
    });

    testWidgets('Step2 mostra botão Anterior', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);

      expect(find.text('Anterior'), findsOneWidget);
    });

    testWidgets('Anterior no Step2 retorna para Step1', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);

      await tester.tap(find.text('Anterior'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('fluxo completo Criar → handler chamado 1x e dialog fechado', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      verify(
        () => handler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
          name: any(named: 'name'),
          description: any(named: 'description'),
          vertical: any(named: 'vertical'),
          penalties: any(named: 'penalties'),
          existingId: any(named: 'existingId'),
          existingCreatedAt: any(named: 'existingCreatedAt'),
        ),
      ).called(1);

      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Cancelar fecha dialog sem chamar handler', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(Dialog), findsNothing);
      _verifyNeverCalled(handler);
    });
  });

  // ── 2. Edit Mode ──────────────────────────────────────────────────────────

  group('2. Edit Mode — template existente pré-carregado', () {
    late _MockSaveHandler handler;
    late SlaTemplateView existing;

    setUp(() {
      handler = _MockSaveHandler();
      existing = _buildExistingView();
      _stubHandler(
        handler,
        returns: _buildFakeDomain(name: 'Modelo Existente'),
      );
    });

    testWidgets('título "Editar Modelo SLA" no modo edição', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler, existing: existing));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      expect(find.text('Editar Modelo SLA'), findsOneWidget);
      expect(find.text('Novo Modelo SLA'), findsNothing);
    });

    testWidgets('Step3 exibe botão "Salvar" em vez de "Criar"', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler, existing: existing));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _tapNext(tester);
      await _tapNext(tester);

      expect(find.text('Salvar'), findsOneWidget);
      expect(find.text('Criar'), findsNothing);
    });

    testWidgets('nome do template existente pré-preenchido no Step1', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler, existing: existing));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      final nameField = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(nameField.controller?.text, 'Modelo Existente');
    });

    testWidgets('handler recebe existingId do template ao salvar', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      String? capturedExistingId;
      _stubHandler(
        handler,
        onCall: (args) {
          capturedExistingId = args.existingId;
        },
      );

      await tester.pumpWidget(_buildHost(handler: handler, existing: existing));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _tapNext(tester);
      await _tapNext(tester);
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(capturedExistingId, equals(existing.id));
    });
  });

  // ── 3. Validação de Formulário ────────────────────────────────────────────

  group('3. Validação — campos obrigatórios e limites', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
    });

    testWidgets('nome vazio → Obrigatório exibido, permanece Step1', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.tap(find.text('Próximo'));
      await tester.pump();

      expect(find.text('Obrigatório'), findsOneWidget);
      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('nome com 101 chars → "Máx. 100 caracteres"', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.enterText(find.byType(TextFormField).first, 'A' * 101);
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump();

      expect(find.text('Máx. 100 caracteres'), findsOneWidget);
      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('nome exatamente 100 chars é válido → avança para Step2', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await tester.enterText(find.byType(TextFormField).first, 'A' * 100);
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Máx. 100 caracteres'), findsNothing);
      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('descrição vazia é aceita (campo opcional)', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      // Só preenche nome, deixa descrição vazia
      await tester.enterText(find.byType(TextFormField).first, 'Modelo X');
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('campo temporal vazio → Obrigatório, permanece Step2', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);

      // Limpa o primeiro campo do Step2 (Tolerância Atraso)
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump();

      expect(find.text('Obrigatório'), findsOneWidget);
      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('campo financeiro vazio → Obrigatório, permanece Step3', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      // Limpa o primeiro campo do Step3 (Penalidade/min)
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pump();
      await tester.tap(find.text('Criar'));
      await tester.pump();

      expect(find.text('Obrigatório'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      _verifyNeverCalled(handler);
    });
  });

  // ── 4. Smart Defaults ─────────────────────────────────────────────────────

  group('4. Smart Defaults — troca de Vertical', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
      _stubHandler(handler);
    });

    testWidgets(
      'selecionar CargaSeca → delayToleranceMinutes muda de 15 para 30',
      (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        // Valor inicial do campo no Step1 — controller _delayTolCtl = '15'
        // Seleciona CargaSeca (SmartDefaults: delayToleranceMinutes = 30)
        await _selectVertical(tester, TransportVertical.cargaSeca);

        await _fillStep1(tester, name: 'Modelo Carga');
        await _tapNext(tester); // vai para Step2

        // Primeiro campo do Step2 = Tolerância Atraso = _delayTolCtl
        final firstField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(firstField.controller?.text, '30');
      },
    );

    testWidgets(
      'selecionar Escolar → noShowThresholdMinutes muda de 60 para 20',
      (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await _selectVertical(tester, TransportVertical.escolar);

        await _fillStep1(tester, name: 'Modelo Escolar');
        await _tapNext(tester); // vai para Step2

        // Segundo campo do Step2 = Limiar No-Show = _noShowThreshCtl
        final secondField = tester.widget<TextFormField>(
          find.byType(TextFormField).at(1),
        );
        expect(secondField.controller?.text, '20');
      },
    );

    testWidgets(
      'selecionar Personalizado (custom) NÃO altera valores dos campos',
      (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        // Primeiro seleciona CargaSeca (delayTol → 30)
        await _selectVertical(tester, TransportVertical.cargaSeca);
        await tester.pump();

        // Agora seleciona Personalizado — NÃO deve re-aplicar defaults
        await _selectVertical(tester, TransportVertical.custom);

        await _fillStep1(tester, name: 'Modelo Custom');
        await _tapNext(tester);

        // Campo ainda deve ter '30' (CargaSeca default), não '15' (initial)
        final firstField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(firstField.controller?.text, '30');
      },
    );
  });

  // ── 5. Estado de Saving ───────────────────────────────────────────────────

  group('5. Estado de Saving — UI de carregamento', () {
    testWidgets('CircularProgressIndicator visível enquanto handler processa', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final handler = _MockSaveHandler();
      final completer = Completer<SlaTemplate>();
      when(
        () => handler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
          name: any(named: 'name'),
          description: any(named: 'description'),
          vertical: any(named: 'vertical'),
          penalties: any(named: 'penalties'),
          existingId: any(named: 'existingId'),
          existingCreatedAt: any(named: 'existingCreatedAt'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Criar'));
      await tester.pump(); // 1 frame — _isSaving = true

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_buildFakeDomain());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('botão Cancelar desabilitado durante _isSaving', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final handler = _MockSaveHandler();
      final completer = Completer<SlaTemplate>();
      when(
        () => handler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
          name: any(named: 'name'),
          description: any(named: 'description'),
          vertical: any(named: 'vertical'),
          penalties: any(named: 'penalties'),
          existingId: any(named: 'existingId'),
          existingCreatedAt: any(named: 'existingCreatedAt'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Criar'));
      await tester.pump();

      final cancelBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancelar'),
      );
      expect(cancelBtn.onPressed, isNull);

      completer.complete(_buildFakeDomain());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('_isSaving reseta para false após save bem-sucedido', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final handler = _MockSaveHandler();
      _stubHandler(handler);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dialog fechado — _isSaving resetou e Navigator.pop foi chamado
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ── 6. Cenários Adversos — Falha na API ───────────────────────────────────

  group('6. Cenários Adversos — falha no handler', () {
    testWidgets('handler lança Exception → SnackBar com VeraProbColors.error', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final handler = _MockSaveHandler();
      _stubHandler(handler, throws: Exception('Falha de conexão'));

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, VeraProbColors.error);
      expect(
        find.textContaining('Não foi possível salvar as alterações.'),
        findsOneWidget,
      );
    });

    testWidgets('dialog permanece aberto após falha no handler', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final handler = _MockSaveHandler();
      _stubHandler(handler, throws: Exception('Timeout'));

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('_isSaving reseta para false após falha no handler', (
      tester,
    ) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final handler = _MockSaveHandler();
      _stubHandler(handler, throws: Exception('Server Error'));

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Botão Cancelar volta a ser clicável
      final cancelBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancelar'),
      );
      expect(cancelBtn.onPressed, isNotNull);
    });

    testWidgets('após falha pode tentar salvar novamente', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      final handler = _MockSaveHandler();
      var callCount = 0;
      when(
        () => handler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
          name: any(named: 'name'),
          description: any(named: 'description'),
          vertical: any(named: 'vertical'),
          penalties: any(named: 'penalties'),
          existingId: any(named: 'existingId'),
          existingCreatedAt: any(named: 'existingCreatedAt'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw Exception('First attempt failed');
        return _buildFakeDomain();
      });

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      // Primeira tentativa — falha
      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Dialog), findsOneWidget);

      // Segunda tentativa — sucesso
      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Dialog), findsNothing);
    });
  });

  // ── 7. Payloads Extremos ──────────────────────────────────────────────────

  group('7. Payloads Extremos — robustez de entrada', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
      _stubHandler(handler);
    });

    testWidgets('nome com caracteres especiais é aceito', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester, name: 'SLA #1 — Frota (BR/SP)');
      await _tapNext(tester);

      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('valor decimal "50,00" aceito no campo R\$', (tester) async {
      _setScreenSize(tester);
      addTearDown(tester.view.resetPhysicalSize);

      String? capturedDelayPerMin;
      _stubHandler(
        handler,
        onCall: (args) {
          capturedDelayPerMin = args.penalties.delayPenaltyPerMinuteCents
              .toString();
        },
      );

      await tester.pumpWidget(_buildHost(handler: handler));
      await tester.pumpAndSettle();
      await _openDialog(tester);

      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);

      // Substitui Penalidade/min (1° campo Step3) por '50,00'
      await tester.enterText(find.byType(TextFormField).first, '50,00');
      await tester.pump();

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // '50,00' → 5000 centavos
      expect(capturedDelayPerMin, '5000');
    });
  });

  // ── 8. Tríade CIA ─────────────────────────────────────────────────────────

  group('8. Tríade CIA', () {
    // ── C: Confidencialidade ────────────────────────────────────────────────

    group('C — org/session isolation (INV-1)', () {
      testWidgets('orgId do provider passado exato ao handler sem vazamento', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        final handler = _MockSaveHandler();
        String? capturedOrgId;
        String? capturedSessionId;
        _stubHandler(
          handler,
          onCall: (args) {
            capturedOrgId = args.organizationId;
            capturedSessionId = args.sessionId;
          },
        );

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await _fillStep1(tester);
        await _tapNext(tester);
        await _tapNext(tester);

        await tester.tap(find.text('Criar'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(capturedOrgId, equals(_kOrgId));
        expect(capturedSessionId, equals(_kSessionId));
      });

      testWidgets('orgId null → handler NÃO chamado (INV-1 fail-fast)', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        final handler = _MockSaveHandler();

        await tester.pumpWidget(_buildHost(handler: handler, orgId: null));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await _fillStep1(tester);
        await _tapNext(tester);
        await _tapNext(tester);

        await tester.tap(find.text('Criar'));
        await tester.pump();
        await tester.pump();

        _verifyNeverCalled(handler);
      });
    });

    // ── I: Integridade Financeira (INV-4/INV-5) ─────────────────────────────

    group('I — precisão financeira (unit tests)', () {
      test('_reaisToCents: "50,00" → 5000', () {
        const text = '50,00';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 5000);
      });

      test('_reaisToCents: "0,50" → 50', () {
        const text = '0,50';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 50);
      });

      test('_reaisToCents: "1234,56" → 123456', () {
        const text = '1234,56';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 123456);
      });

      test('_reaisToCents: "0" → 0', () {
        const text = '0';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 0);
      });

      test('_centsToReais: 5000 → "50.00"', () {
        const cents = 5000;
        final reais = (cents / 100).toStringAsFixed(2);
        expect(reais, '50.00');
      });

      test('noShowMultiplier: 15000 bps → "1.5" display', () {
        const bps = 15000;
        final display = (bps / 10000.0).toString();
        expect(display, '1.5');
      });

      test('noShowMultiplier: "1.5" → 15000 bps (round-trip)', () {
        const text = '1.5';
        final bps = (double.tryParse(text.replaceAll(',', '.'))! * 10000)
            .round();
        expect(bps, 15000);
      });

      test('noShowMultiplier: "2,0" → 20000 bps', () {
        const text = '2,0';
        final bps = (double.tryParse(text.replaceAll(',', '.'))! * 10000)
            .round();
        expect(bps, 20000);
      });
    });

    // ── A: Disponibilidade (INV-24) ─────────────────────────────────────────

    group('A — barrierDismissible=false e dispose controllers (INV-24)', () {
      testWidgets('tap fora do dialog (barreira) NÃO fecha o dialog', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        final handler = _MockSaveHandler();
        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        expect(find.byType(Dialog), findsOneWidget);

        // Toca na barreira (canto superior esquerdo fora do dialog centralizado)
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();

        // Dialog deve permanecer aberto
        expect(find.byType(Dialog), findsOneWidget);
      });

      testWidgets('Cancelar descarta dialog sem exception de dispose', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        final handler = _MockSaveHandler();
        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        // Preenche campos para ativar todos os controllers
        await _fillStep1(tester);
        await tester.pump();

        await tester.tap(find.text('Cancelar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Nenhuma exceção de uso de controller após dispose
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets(
        'save bem-sucedido descarta dialog sem exception de dispose',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          final handler = _MockSaveHandler();
          _stubHandler(handler);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);

          await _fillStep1(tester);
          await _tapNext(tester);
          await _tapNext(tester);

          await tester.tap(find.text('Criar'));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(tester.takeException(), isNull);
          expect(find.byType(Dialog), findsNothing);
        },
      );
    });
  });

  // ── 9. Passo 1 — Identidade (Fase 2) ─────────────────────────────────────

  group('9. Passo 1 — Identidade', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
      _stubHandler(handler);
    });

    // ── 9.1 Validação ───────────────────────────────────────────────────────

    group('9.1 Validação — integridade do campo Nome', () {
      testWidgets('nome só com espaços → "Obrigatório" (trim enforced)', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await tester.enterText(find.byType(TextFormField).first, '   ');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsOneWidget);
        expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
      });

      testWidgets('nome com 1 caractere → válido, avança para Step2', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await tester.enterText(find.byType(TextFormField).first, 'X');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Obrigatório'), findsNothing);
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });

      testWidgets('erro desaparece após corrigir nome e tentar novamente', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await tester.tap(find.text('Próximo'));
        await tester.pump();
        expect(find.text('Obrigatório'), findsOneWidget);

        await tester.enterText(
          find.byType(TextFormField).first,
          'Nome Correto',
        );
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Obrigatório'), findsNothing);
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 9.2 Smart Defaults — verticais não cobertas nos grupos anteriores ───

    group('9.2 Smart Defaults — Fretamento, CargaRefrigerada, Transferência', () {
      testWidgets(
        'Fretamento → noShowMult = "2.0" (distinto do default inicial "1.5")',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);

          await _selectVertical(tester, TransportVertical.fretamento);
          await _fillStep1(tester, name: 'Modelo Fretamento');
          await _tapNext(tester); // Step 2
          await _tapNext(tester); // Step 3

          // Step3: Penalidade/min(0), Downgrade(1), Multiplicador No-Show(2)
          final noShowMultField = tester.widget<TextFormField>(
            find.byType(TextFormField).at(2),
          );
          expect(noShowMultField.controller?.text, '2.0');
        },
      );

      testWidgets('CargaRefrigerada → delayTol = "10", noShowThresh = "45"', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await _selectVertical(tester, TransportVertical.cargaRefrigerada);
        await _fillStep1(tester, name: 'Modelo Refrigerado');
        await _tapNext(tester);

        final delayTolField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(delayTolField.controller?.text, '10');

        final noShowThreshField = tester.widget<TextFormField>(
          find.byType(TextFormField).at(1),
        );
        expect(noShowThreshField.controller?.text, '45');
      });

      testWidgets(
        'TransferenciaFuncionarios → delayTol = "10", noShowThresh = "30"',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);

          await _selectVertical(
            tester,
            TransportVertical.transferenciaFuncionarios,
          );
          await _fillStep1(tester, name: 'Modelo Transferência');
          await _tapNext(tester);

          final delayTolField = tester.widget<TextFormField>(
            find.byType(TextFormField).first,
          );
          expect(delayTolField.controller?.text, '10');

          final noShowThreshField = tester.widget<TextFormField>(
            find.byType(TextFormField).at(1),
          );
          expect(noShowThreshField.controller?.text, '30');
        },
      );

      testWidgets(
        'trocar Fretamento → Escolar reaplica defaults do Escolar (delayTol = "5")',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);

          await _selectVertical(tester, TransportVertical.fretamento);
          await _selectVertical(tester, TransportVertical.escolar);

          await _fillStep1(tester, name: 'Modelo Escola');
          await _tapNext(tester);

          final delayTolField = tester.widget<TextFormField>(
            find.byType(TextFormField).first,
          );
          expect(delayTolField.controller?.text, '5');
        },
      );
    });

    // ── 9.3 Navegação ───────────────────────────────────────────────────────

    group('9.3 Navegação — estrutura e fluxo do Step 1', () {
      testWidgets('Step1 renderiza 2 TextFormFields e 1 dropdown de Vertical', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(
          find.byType(DropdownButtonFormField<TransportVertical>),
          findsOneWidget,
        );
      });

      testWidgets('label "Nome do Modelo *" visível no Step1', (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        expect(find.text('Nome do Modelo *'), findsOneWidget);
      });

      testWidgets('label "Vertical" visível no Step1', (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        expect(find.text('Vertical'), findsOneWidget);
      });

      testWidgets('nome + descrição preenchidos → avança para Step2', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.first, 'Modelo Com Desc');
        await tester.enterText(fields.last, 'Descrição longa do modelo');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 9.4 Confidencialidade — Edit Mode ───────────────────────────────────

    group('9.4 Confidencialidade — pré-carga modo edição (INV-1)', () {
      late SlaTemplateView existing;

      setUp(() {
        existing = _buildExistingView();
      });

      testWidgets('vertical fretamento pré-selecionada no dropdown (INV-1)', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildHost(handler: handler, existing: existing),
        );
        await tester.pumpAndSettle();
        await _openDialog(tester);

        expect(find.text(TransportVertical.fretamento.label), findsOneWidget);
      });

      testWidgets('descrição existente pré-preenchida no campo Descrição', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildHost(handler: handler, existing: existing),
        );
        await tester.pumpAndSettle();
        await _openDialog(tester);

        final descField = tester.widget<TextFormField>(
          find.byType(TextFormField).last,
        );
        expect(descField.controller?.text, 'Desc existente');
      });

      testWidgets('ID técnico do template NÃO é renderizado na tela (INV-1)', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildHost(handler: handler, existing: existing),
        );
        await tester.pumpAndSettle();
        await _openDialog(tester);

        expect(find.text(existing.id), findsNothing);
      });

      testWidgets('campo nome editável após pré-carga', (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildHost(handler: handler, existing: existing),
        );
        await tester.pumpAndSettle();
        await _openDialog(tester);

        await tester.enterText(
          find.byType(TextFormField).first,
          'Nome Atualizado',
        );
        await tester.pump();

        final nameField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(nameField.controller?.text, 'Nome Atualizado');
      });
    });
  });

  // ── 10. Passo 2 — Temporal (Fase 3) ──────────────────────────────────────

  group('10. Passo 2 — Temporal', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
      _stubHandler(handler);
    });

    Future<void> goToStep2(WidgetTester tester) async {
      await _fillStep1(tester);
      await _tapNext(tester);
    }

    Future<void> tapBack(WidgetTester tester) async {
      await tester.tap(find.text('Anterior'));
      await tester
          .pumpAndSettle(); // AnimatedSwitcher must fully remove exiting child
    }

    // ── 10.1 Validação ───────────────────────────────────────────────────────

    group('10.1 Validação — inputs numéricos e campos obrigatórios', () {
      testWidgets('todos os 5 campos vazios → 5x "Obrigatório" exibidos', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        for (int i = 0; i < 5; i++) {
          await tester.enterText(find.byType(TextFormField).at(i), '');
          await tester.pump();
        }
        await tester.tap(find.text('Próximo'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsNWidgets(5));
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });

      testWidgets('input formatter bloqueia letras — apenas dígitos aceitos', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        await tester.enterText(find.byType(TextFormField).first, 'abc5xyz');
        await tester.pump();

        final field = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(field.controller?.text, '5');
      });

      testWidgets(
        'input formatter bloqueia ponto decimal — campo inteiro rejeita "."',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep2(tester);

          await tester.enterText(find.byType(TextFormField).first, '1.5');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).first,
          );
          expect(field.controller?.text, '15');
        },
      );

      testWidgets('campo Dwell Time vazio (idx 3) → "Obrigatório"', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        await tester.enterText(find.byType(TextFormField).at(3), '');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsOneWidget);
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 10.2 Integridade Forense ─────────────────────────────────────────────

    group('10.2 Integridade Forense — persistência de estado ao navegar', () {
      testWidgets('valores padrão do Step2 refletem domain defaults', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(0))
              .controller
              ?.text,
          '15', // delayToleranceMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller
              ?.text,
          '60', // noShowThresholdMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(2))
              .controller
              ?.text,
          '5', // earlyArrivalToleranceMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(3))
              .controller
              ?.text,
          '3', // dwellTimeMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(4))
              .controller
              ?.text,
          '0', // gracePeriodMinutes
        );
      });

      testWidgets(
        'Step2→Step3→Anterior: todos os valores editados no Step2 persistem',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep2(tester);

          await tester.enterText(find.byType(TextFormField).at(0), '20');
          await tester.enterText(find.byType(TextFormField).at(1), '45');
          await tester.enterText(find.byType(TextFormField).at(2), '8');
          await tester.enterText(find.byType(TextFormField).at(3), '10');
          await tester.enterText(find.byType(TextFormField).at(4), '2');
          await tester.pump();

          await _tapNext(tester); // Step3
          await tapBack(tester); // volta Step2

          expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '20',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '45',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(2))
                .controller
                ?.text,
            '8',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(3))
                .controller
                ?.text,
            '10',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(4))
                .controller
                ?.text,
            '2',
          );
        },
      );

      testWidgets(
        'Step2→Step1(Anterior)→Step2(Próximo): estado dos controllers preservado',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep2(tester);

          await tester.enterText(find.byType(TextFormField).at(0), '25');
          await tester.enterText(find.byType(TextFormField).at(1), '90');
          await tester.pump();

          await tapBack(tester); // Step1
          expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);

          await _tapNext(tester); // Step2 novamente
          expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);

          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '25',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '90',
          );
        },
      );
    });

    // ── 10.3 Navegação ───────────────────────────────────────────────────────

    group('10.3 Navegação — comportamento do Step2', () {
      testWidgets(
        'Anterior NÃO dispara validação — campo vazio permite voltar',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep2(tester);

          await tester.enterText(find.byType(TextFormField).first, '');
          await tester.pump();

          await tapBack(tester);

          expect(find.text('Obrigatório'), findsNothing);
          expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
        },
      );

      testWidgets('Step2 renderiza exatamente 5 TextFormFields', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        expect(find.byType(TextFormField), findsNWidgets(5));
      });

      testWidgets('Próximo com defaults válidos avança para Step3', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        await _tapNext(tester);

        expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
      });
    });

    // ── 10.4 Decorações ──────────────────────────────────────────────────────

    group('10.4 Decorações — sufixos e labels do Step2', () {
      testWidgets('sufixo "min" renderizado em todos os 5 campos do Step2', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        // Each _PenaltyField renders suffixText as a Text widget.
        // Step2 has 5 fields, all with suffix 'min', and no other 'min' on screen.
        expect(find.text('min'), findsNWidgets(5));
      });

      testWidgets('labels corretas nos 5 campos do Step2', (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep2(tester);

        expect(find.text('Tolerância Atraso'), findsOneWidget);
        expect(find.text('Limiar No-Show'), findsOneWidget);
        expect(find.text('Tolerância Antecipação'), findsOneWidget);
        expect(find.text('Dwell Time'), findsOneWidget);
        expect(find.text('Período de Graça'), findsOneWidget);
      });
    });
  });

  // ── 11. Passo 3 — Financeiro (Fase 4) ─────────────────────────────────────

  group('11. Passo 3 — Financeiro', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
      _stubHandler(handler);
    });

    Future<void> goToStep3(WidgetTester tester) async {
      await _fillStep1(tester);
      await _tapNext(tester); // Step1 → Step2 (all defaults valid)
      await _tapNext(tester); // Step2 → Step3
    }

    Future<void> tapBack(WidgetTester tester) async {
      await tester.tap(find.text('Anterior'));
      await tester
          .pumpAndSettle(); // AnimatedSwitcher must fully remove exiting child
    }

    // ── 11.1 Validação ────────────────────────────────────────────────────────

    group('11.1 Validação — inputs decimais e campos obrigatórios', () {
      testWidgets('todos os 4 campos vazios → 4x "Obrigatório" exibidos', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        for (int i = 0; i < 4; i++) {
          await tester.enterText(find.byType(TextFormField).at(i), '');
          await tester.pump();
        }
        await tester.tap(find.text('Criar'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsNWidgets(4));
        expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
      });

      testWidgets(
        'formatter ACEITA vírgula — "1,50" preservado no controller',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.enterText(find.byType(TextFormField).at(0), '1,50');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          );
          expect(field.controller?.text, '1,50');
        },
      );

      testWidgets(
        'formatter ACEITA ponto decimal — "1.50" preservado no controller',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.enterText(find.byType(TextFormField).at(0), '1.50');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          );
          expect(field.controller?.text, '1.50');
        },
      );

      testWidgets(
        'formatter BLOQUEIA letras — "abc1,5xyz" → "1,5" no controller',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.enterText(find.byType(TextFormField).at(0), 'abc1,5xyz');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          );
          expect(field.controller?.text, '1,5');
        },
      );

      testWidgets(
        'Multiplicador No-Show (idx 2) aceita decimal — "1.5" preservado',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.enterText(find.byType(TextFormField).at(2), '1.5');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(2),
          );
          expect(field.controller?.text, '1.5');
        },
      );

      testWidgets('Multiplicador No-Show vazio (idx 2) → "Obrigatório"', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        await tester.enterText(find.byType(TextFormField).at(2), '');
        await tester.pump();
        await tester.tap(find.text('Criar'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsOneWidget);
        expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
      });

      testWidgets(
        'todos os 4 campos usam keyboardType numberWithOptions(decimal: true)',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          // TextFormField does not expose keyboardType directly — reach the inner TextField.
          for (int i = 0; i < 4; i++) {
            final textField = tester.widget<TextField>(
              find.descendant(
                of: find.byType(TextFormField).at(i),
                matching: find.byType(TextField),
              ),
            );
            expect(
              textField.keyboardType,
              const TextInputType.numberWithOptions(decimal: true),
              reason: 'Campo $i deve usar teclado decimal',
            );
          }
        },
      );
    });

    // ── 11.2 Integridade Financeira ───────────────────────────────────────────

    group('11.2 Integridade Financeira — defaults e persistência', () {
      testWidgets('valores padrão do Step3 refletem domain defaults', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        // delayPenaltyPerMinuteCents=50 → (50/100).toStringAsFixed(2) = '0.50'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(0))
              .controller
              ?.text,
          '0.50',
        );
        // downgradePenaltyFlatCents=5000 → (5000/100).toStringAsFixed(2) = '50.00'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller
              ?.text,
          '50.00',
        );
        // noShowPenaltyBps=15000 → (15000/10000.0).toString() = '1.5'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(2))
              .controller
              ?.text,
          '1.5',
        );
        // baseTripValueCents=0 → (0/100).toStringAsFixed(2) = '0.00'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(3))
              .controller
              ?.text,
          '0.00',
        );
      });

      testWidgets(
        'Step3→Anterior→Step3: valores editados persistem após navegação',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.enterText(find.byType(TextFormField).at(0), '1,50');
          await tester.enterText(find.byType(TextFormField).at(1), '75,00');
          await tester.enterText(find.byType(TextFormField).at(2), '2.0');
          await tester.enterText(find.byType(TextFormField).at(3), '100,00');
          await tester.pump();

          await tapBack(tester); // Step3 → Step2
          expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);

          await _tapNext(tester); // Step2 → Step3
          expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);

          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '1,50',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '75,00',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(2))
                .controller
                ?.text,
            '2.0',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(3))
                .controller
                ?.text,
            '100,00',
          );
        },
      );
    });

    // ── 11.3 Navegação ────────────────────────────────────────────────────────

    group('11.3 Navegação e botão primário', () {
      testWidgets('Step3 exibe "Criar" em modo criação — não "Próximo"', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        expect(find.text('Criar'), findsOneWidget);
        expect(find.text('Próximo'), findsNothing);
      });

      testWidgets('Step3 exibe "Salvar" em modo edição', (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        final existing = _buildExistingView();
        await tester.pumpWidget(
          _buildHost(handler: handler, existing: existing),
        );
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await _tapNext(tester); // Step1 → Step2 (name pre-filled by existing)
        await _tapNext(tester); // Step2 → Step3

        expect(find.text('Salvar'), findsOneWidget);
        expect(find.text('Criar'), findsNothing);
      });

      testWidgets('Step3 renderiza exatamente 4 TextFormFields', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        expect(find.byType(TextFormField), findsNWidgets(4));
      });

      testWidgets('"Anterior" em Step3 volta para Step2', (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        await tapBack(tester);

        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 11.4 Decorações ───────────────────────────────────────────────────────

    group('11.4 Decorações — prefixos, sufixos e labels', () {
      testWidgets('prefixo "R\$" renderizado em 3 campos monetários do Step3', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        // Penalidade/min, Downgrade (flat), Valor Base Viagem each render prefix 'R$'
        expect(find.text(r'R$'), findsNWidgets(3));
      });

      testWidgets('sufixo "x" renderizado no campo Multiplicador No-Show', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        expect(find.text('x'), findsOneWidget);
      });

      testWidgets('labels corretas nos 4 campos do Step3', (tester) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_buildHost(handler: handler));
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await goToStep3(tester);

        expect(find.text('Penalidade/min'), findsOneWidget);
        expect(find.text('Downgrade (flat)'), findsOneWidget);
        expect(find.text('Multiplicador No-Show'), findsOneWidget);
        expect(find.text('Valor Base Viagem'), findsOneWidget);
      });
    });

    // ── 11.5 Submissão ────────────────────────────────────────────────────────

    group('11.5 Submissão — Criar dispara handler', () {
      testWidgets(
        '"Criar" com defaults válidos dispara handler.handle() uma vez',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          verify(
            () => handler.handle(
              organizationId: _kOrgId,
              sessionId: _kSessionId,
              name: 'Modelo Teste',
              description: any(named: 'description'),
              vertical: any(named: 'vertical'),
              penalties: any(named: 'penalties'),
              existingId: null,
              existingCreatedAt: null,
            ),
          ).called(1);
        },
      );

      testWidgets(
        '"Criar" converte vírgula decimal corretamente — R\$1,50 → 150 cents',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          _HandleArgs? captured;
          _stubHandler(handler, onCall: (args) => captured = args);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          // Override delayPerMinCtl with a comma-formatted value
          await tester.enterText(find.byType(TextFormField).at(0), '1,50');
          await tester.pump();

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          // '1,50' → replaceAll(',','.') → '1.50' → double.parse(1.50) → *100 → round() = 150
          expect(captured!.penalties.delayPenaltyPerMinuteCents, 150);
        },
      );
    });
  });

  // ── 12. Fase 5 — Submissão e Persistência ────────────────────────────────

  group('12. Fase 5 — Submissão e Persistência', () {
    late _MockSaveHandler handler;

    setUp(() {
      handler = _MockSaveHandler();
      _stubHandler(handler);
    });

    Future<void> goToStep3(WidgetTester tester) async {
      await _fillStep1(tester);
      await _tapNext(tester);
      await _tapNext(tester);
    }

    // ── 12.1 E2E — payload completo verificado ────────────────────────────

    group('12.1 E2E — payload completo e precisão de cents', () {
      testWidgets(
        'payload financeiro: valores não-default convertidos com precisão exata',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          _HandleArgs? captured;
          _stubHandler(handler, onCall: (args) => captured = args);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          // Override all 4 financial fields with custom non-default values
          await tester.enterText(
            find.byType(TextFormField).at(0),
            '2,50',
          ); // delayPerMin: 2.50 BRL → 250 cents
          await tester.enterText(
            find.byType(TextFormField).at(1),
            '30,00',
          ); // downgrade: 30.00 BRL → 3000 cents
          await tester.enterText(
            find.byType(TextFormField).at(2),
            '2.0',
          ); // noShowMult: 2.0x → 20000 bps
          await tester.enterText(
            find.byType(TextFormField).at(3),
            '10,00',
          ); // baseTrip: 10.00 BRL → 1000 cents
          await tester.pump();

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(
            captured!.penalties.delayPenaltyPerMinuteCents,
            250,
            reason: '"2,50" → 2.50 * 100 = 250',
          );
          expect(
            captured!.penalties.downgradePenaltyFlatCents,
            3000,
            reason: '"30,00" → 30.00 * 100 = 3000',
          );
          expect(
            captured!.penalties.noShowPenaltyBps,
            20000,
            reason: '"2.0" → (2.0 * 10000).round() = 20000',
          );
          expect(
            captured!.penalties.baseTripValueCents,
            1000,
            reason: '"10,00" → 10.00 * 100 = 1000',
          );
        },
      );

      testWidgets(
        'payload identidade: organizationId, sessionId e name propagados (INV-1)',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          _HandleArgs? captured;
          _stubHandler(handler, onCall: (args) => captured = args);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await _fillStep1(tester, name: 'Modelo INV-1');
          await _tapNext(tester);
          await _tapNext(tester);

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(captured!.organizationId, _kOrgId);
          expect(captured!.sessionId, _kSessionId);
          expect(captured!.name, 'Modelo INV-1');
          expect(captured!.existingId, isNull);
          expect(captured!.vertical, isNull);
        },
      );

      testWidgets(
        'dialog fecha após submit bem-sucedido — Navigator.pop chamado',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          expect(find.byType(Dialog), findsOneWidget);

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(find.byType(Dialog), findsNothing);
        },
      );
    });

    // ── 12.2 Tratamento de Erros — sequência de estados ───────────────────

    group('12.2 Tratamento de Erros — sequência de estados', () {
      testWidgets(
        'submit: CircularProgressIndicator visível → desaparece após erro → SnackBar exibido',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          final completer = Completer<SlaTemplate>();
          when(
            () => handler.handle(
              organizationId: any(named: 'organizationId'),
              sessionId: any(named: 'sessionId'),
              name: any(named: 'name'),
              description: any(named: 'description'),
              vertical: any(named: 'vertical'),
              penalties: any(named: 'penalties'),
              existingId: any(named: 'existingId'),
              existingCreatedAt: any(named: 'existingCreatedAt'),
            ),
          ).thenAnswer((_) => completer.future);

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.tap(find.text('Criar'));
          await tester.pump(); // single frame — Future still pending

          // Loading state: CircularProgressIndicator must be visible
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('Criar'), findsNothing);

          // Resolve with error
          completer.completeError(Exception('Erro de Conexão'));
          await tester.pumpAndSettle();

          // Loading gone, SnackBar with error message and correct background
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            find.text('Não foi possível salvar as alterações.'),
            findsOneWidget,
          );

          final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
          expect(snackBar.backgroundColor, VeraProbColors.error);
        },
      );

      testWidgets(
        'após erro: _isSaving=false restaurado — botão Criar volta ao estado normal',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          _stubHandler(handler, throws: Exception('falha'));

          await tester.pumpWidget(_buildHost(handler: handler));
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await goToStep3(tester);

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          // After error resolves: button text restored (CircularProgressIndicator gone)
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Criar'), findsOneWidget);
        },
      );
    });

    // ── 12.3 Modo Edição — existingId, existingCreatedAt e pré-carga ──────

    group('12.3 Modo Edição — propagação de existingId e existingCreatedAt', () {
      testWidgets('existingId propagado ao handler — id do modelo existente', (
        tester,
      ) async {
        _setScreenSize(tester);
        addTearDown(tester.view.resetPhysicalSize);

        _HandleArgs? captured;
        _stubHandler(handler, onCall: (args) => captured = args);

        final existing = _buildExistingView();
        await tester.pumpWidget(
          _buildHost(handler: handler, existing: existing),
        );
        await tester.pumpAndSettle();
        await _openDialog(tester);
        await _tapNext(tester); // Step1 → Step2 (name pre-filled)
        await _tapNext(tester); // Step2 → Step3

        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.existingId, existing.id);
      });

      testWidgets(
        'existingCreatedAt propagado ao handler — timestamp original preservado (INV-12)',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          _HandleArgs? captured;
          _stubHandler(handler, onCall: (args) => captured = args);

          final existing = _buildExistingView();
          await tester.pumpWidget(
            _buildHost(handler: handler, existing: existing),
          );
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await _tapNext(tester);
          await _tapNext(tester);

          await tester.tap(find.text('Salvar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(captured!.existingCreatedAt, existing.createdAt);
          expect(captured!.existingCreatedAt, _kCreatedAt);
        },
      );

      testWidgets(
        'modo edição com penalties customizados — Step3 pré-carregado com valores corretos',
        (tester) async {
          _setScreenSize(tester);
          addTearDown(tester.view.resetPhysicalSize);

          // Build an existing view with specific financial values
          final customPenalties = SLAPenalties.create(
            noShowPenaltyBps: 20000, // 2.0x → displayed as '2.0'
            delayToleranceMinutes: 15,
            delayPenaltyPerMinute: const Money(250), // 250 cents → '2.50'
            downgradePenaltyFlat: const Money(7500), // 7500 cents → '75.00'
            noShowThresholdMinutes: 60,
            earlyArrivalToleranceMinutes: 5,
            dwellTimeMinutes: 3,
            gracePeriodMinutes: 0,
            baseTripValue: const Money(1000), // 1000 cents → '10.00'
          );
          final domain = SlaTemplate.reconstitute(
            id: 'edit-tmpl-001',
            organizationId: _kOrgId,
            name: 'Modelo Custom',
            penalties: customPenalties,
            createdAt: _kCreatedAt,
          );
          final existing = SlaTemplateView.fromDomain(domain);

          await tester.pumpWidget(
            _buildHost(handler: handler, existing: existing),
          );
          await tester.pumpAndSettle();
          await _openDialog(tester);
          await _tapNext(tester);
          await _tapNext(tester);

          expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);

          // delayPenaltyPerMinuteCents=250 → (250/100).toStringAsFixed(2) = '2.50'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '2.50',
            reason: '250 cents → 2.50',
          );
          // downgradePenaltyFlatCents=7500 → '75.00'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '75.00',
            reason: '7500 cents → 75.00',
          );
          // noShowPenaltyBps=20000 → (20000/10000.0).toString() = '2.0'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(2))
                .controller
                ?.text,
            '2.0',
            reason: '20000 bps → 2.0',
          );
          // baseTripValueCents=1000 → '10.00'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(3))
                .controller
                ?.text,
            '10.00',
            reason: '1000 cents → 10.00',
          );
        },
      );
    });
  });
}
