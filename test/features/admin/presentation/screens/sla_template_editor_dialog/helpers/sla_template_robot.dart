import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/sla_audit/save_sla_template_handler.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/features/admin/presentation/screens/sla_template_editor_dialog.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_template_repository.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

class MockSaveHandler extends Mock implements SaveSlaTemplateHandler {}

/// Robot Pattern (Page Object Model) para o SlaTemplateEditorDialog.
/// Encapsula a complexidade de injeção de dependências, navegação de UI,
/// e setup de View/Domain, eliminando a duplicação em massa de código de teste.
class SlaTemplateRobot {
  final WidgetTester tester;
  final MockSaveHandler handler;

  static const String defaultOrgId = 'org-test-001';
  static const String defaultSessionId = 'session-token-abc';
  static final DateTime defaultCreatedAt = DateTime.utc(2024, 1, 15);

  SlaTemplateRobot(this.tester, this.handler);

  // ─── Fixtures de Domínio ─────────────────────────────────────────────────────

  static SlaTemplate buildFakeDomain({
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
      organizationId: defaultOrgId,
      name: name,
      description: description,
      vertical: vertical,
      penalties: penalties,
      createdAt: defaultCreatedAt,
    );
  }

  static SlaTemplateView buildExistingView() {
    return SlaTemplateView.fromDomain(
      buildFakeDomain(
        name: 'Modelo Existente',
        description: 'Desc existente',
        vertical: TransportVertical.fretamento,
      ),
    );
  }

  // ─── Setup e Mocks ──────────────────────────────────────────────────────────

  static void stubHandler(
    MockSaveHandler handler, {
    SlaTemplate? returns,
    Object? throws,
    void Function(dynamic captured)? onCall,
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
        return returns ?? buildFakeDomain();
      });
    }
  }

  static void verifyNeverCalled(MockSaveHandler handler) {
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

  Widget buildHost({
    String? orgId = defaultOrgId,
    String? sessionId = defaultSessionId,
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

  // ─── Ações de UI ────────────────────────────────────────────────────────────

  void setScreenSize() {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
  }

  Future<void> openDialog() async {
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> bootstrapWizard({
    SlaTemplateView? existing,
    String? orgId = defaultOrgId,
    String? sessionId = defaultSessionId,
  }) async {
    setScreenSize();
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      buildHost(existing: existing, orgId: orgId, sessionId: sessionId),
    );
    await tester.pumpAndSettle();
    await openDialog();
  }

  Future<void> bootstrapWithCustomHost(Widget host) async {
    setScreenSize();
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(host);
    await tester.pumpAndSettle();
    await openDialog();
  }

  Future<void> fillStep1({String name = 'Modelo Teste'}) async {
    await tester.enterText(find.byType(TextFormField).first, name);
    await tester.pump();
  }

  Future<void> tapNext() async {
    await tester.tap(find.text('Próximo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> selectVertical(TransportVertical v) async {
    await tester.tap(find.byType(DropdownButtonFormField<TransportVertical>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(v.label).last);
    await tester.pump();
  }
}
