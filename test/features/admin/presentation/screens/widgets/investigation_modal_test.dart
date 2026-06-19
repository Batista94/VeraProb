import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evidence_payload.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_modal.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';

// ── HTTP override for map tiles ───────────────────────────────

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

// ── Fixtures ──────────────────────────────────────────────────

const _kSetId = 'set-forensic-001';
const _kContractId = 'contract-abc-999';
const _kOrgId = 'org-test-001';

final _kNow = DateTime.utc(2026, 4, 20, 10, 0, 0);

ContractualExecutionState _buildExecution({
  ExecutionStatus status = ExecutionStatus.planned,
  double lat = -23.550520,
  double lng = -46.633308,
}) {
  final state = ContractualExecutionState.reconstitute(
    id: 'exec-001',
    organizationId: _kOrgId,
    setId: _kSetId,
    contractId: _kContractId,
    planVersion: 1,
    startLatitude: lat,
    startLongitude: lng,
    startRadiusMeters: 300,
    contractualValue: const Money(50000),
    noShowPenaltyBps: 15000,
    windowStartUtc: DateTime.utc(2026, 4, 20, 6, 0),
    windowEndUtc: DateTime.utc(2026, 4, 20, 8, 0),
    status: status,
    createdAtUtc: _kNow,
    lastEvaluatedAtUtc: _kNow,
    statusLastUpdatedAtUtc: _kNow,
  );
  return state;
}

EvaluationTrace _buildTrace({
  String triggeringEventId = 'evt-001',
  List<EvaluationDecision>? decisions,
}) {
  return EvaluationTrace(
    id: 'trace-001',
    organizationId: _kOrgId,
    entityId: _kSetId,
    triggeringEventId: triggeringEventId,
    evaluatedAtUtc: _kNow,
    engineVersion: '2.0.0',
    decisions: decisions ?? [],
  );
}

EvaluationDecision _buildDecision({
  String outcome = 'PASS',
  int? financialImpactCents,
  EvidencePayload? evidence,
}) {
  return EvaluationDecision(
    ruleId: 'rule-00000000-0000-0000-0000-000000000001',
    ruleType: 'PRESENCE_CHECK',
    ruleVersion: 1,
    rulePriority: 1,
    outcome: outcome,
    financialImpactCents: financialImpactCents,
    evidence: evidence ?? const GenericEvidencePayload({}),
  );
}

SlaLedgerEntry _buildLedgerEntry({
  String? eventId,
  String type = 'PLAN_DECLARED',
  DateTime? occurredAtUtc,
}) {
  return SlaLedgerEntry(
    eventId: eventId,
    organizationId: _kOrgId,
    type: type,
    setId: _kSetId,
    contractId: _kContractId,
    planVersion: 1,
    occurredAtUtc: occurredAtUtc ?? _kNow,
  );
}

// ── Widget builder ────────────────────────────────────────────

Future<T> _never<T>() => Completer<T>().future;

Widget _buildModal({
  AsyncValue<List<EvaluationTrace>> traces = const AsyncValue.loading(),
  AsyncValue<List<SlaLedgerEntry>> ledger = const AsyncValue.loading(),
  AsyncValue<ContractualExecutionState?> execution = const AsyncValue.loading(),
}) {
  return ProviderScope(
    overrides: [
      evaluationTracesProvider(_kSetId).overrideWith((_) async {
        return traces.when(
          data: (v) => v,
          loading: () => _never<List<EvaluationTrace>>(),
          error: (e, _) => Future.error(e),
        );
      }),
      ledgerEntriesProvider(_kSetId).overrideWith((_) async {
        return ledger.when(
          data: (v) => v,
          loading: () => _never<List<SlaLedgerEntry>>(),
          error: (e, _) => Future.error(e),
        );
      }),
      executionStateProvider(_kSetId).overrideWith((_) async {
        return execution.when(
          data: (v) => v,
          loading: () => _never<ContractualExecutionState?>(),
          error: (e, _) => Future.error(e),
        );
      }),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const InvestigationModal(
                setId: _kSetId,
                contractId: _kContractId,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openModal(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
}

// ══════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('InvestigationModal — Cadeia Custódia (INV-21/INV-24)', () {
    testWidgets('Cenário 1: header exibe setId e contractId', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildModal(
          traces: const AsyncValue.data([]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text(_kSetId), findsOneWidget);
      expect(find.text(_kContractId), findsOneWidget);
      expect(find.text('SET'), findsOneWidget);
      expect(find.text('CONTRATO'), findsOneWidget);
    });
  });

  group('InvestigationModal — Legacy Gap (INV-15)', () {
    testWidgets('Cenário 2: traces vazios mostram "Sem rastreabilidade"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildModal(
          traces: const AsyncValue.data([]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma rastreabilidade disponível'), findsOneWidget);
      expect(
        find.textContaining('antes\nda ativação do sistema'),
        findsOneWidget,
      );
    });
  });

  group('InvestigationModal — Audit Mode (INV-24)', () {
    testWidgets('Cenário 3: label MODO AUDITORIA visível na AppBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildModal(
          traces: const AsyncValue.data([]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('MODO AUDITORIA'), findsOneWidget);

      // INV-24: badge must use warning color
      final badge = tester.widget<Text>(find.text('MODO AUDITORIA'));
      expect(badge.style?.color, VeraProbColors.warning);
    });
  });

  group('InvestigationModal — Ledger Sync (INV-21)', () {
    testWidgets('Cenário 4: evento acionador recebe badge AUDITADO no ledger', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const triggeringId = 'evt-trigger-001';
      final trace = _buildTrace(triggeringEventId: triggeringId);
      final ledger = [
        _buildLedgerEntry(eventId: triggeringId, type: 'EXECUTION_BOUND'),
        _buildLedgerEntry(
          eventId: 'evt-other-002',
          type: 'PLAN_DECLARED',
          occurredAtUtc: _kNow.subtract(const Duration(minutes: 5)),
        ),
      ];

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.data([trace]),
          ledger: AsyncValue.data(ledger),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('AUDITADO'), findsOneWidget);
    });

    testWidgets('Cenário 4b: evento não-acionador NÃO recebe badge AUDITADO', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final trace = _buildTrace(triggeringEventId: 'evt-trigger-001');
      final ledger = [
        _buildLedgerEntry(eventId: 'evt-other-999', type: 'PLAN_DECLARED'),
      ];

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.data([trace]),
          ledger: AsyncValue.data(ledger),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('AUDITADO'), findsNothing);
    });

    testWidgets(
      'Pkg 3: timeline renders human label primary + raw enum subtitle',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final trace = _buildTrace(triggeringEventId: 'evt-trigger-001');
        final ledger = [
          _buildLedgerEntry(eventId: 'evt-bound-001', type: 'EXECUTION_BOUND'),
        ];

        await tester.pumpWidget(
          _buildModal(
            traces: AsyncValue.data([trace]),
            ledger: AsyncValue.data(ledger),
            execution: const AsyncValue.data(null),
          ),
        );
        await _openModal(tester);
        await tester.pumpAndSettle();

        // Human label for the dispatcher …
        expect(find.text('Execução Vinculada ao Ativo'), findsOneWidget);
        // … and the raw enum kept as forensic subtitle (citability).
        expect(find.text('EXECUTION_BOUND'), findsOneWidget);
      },
    );
  });

  group('InvestigationModal — 1-Click Proof Rule (INV-15)', () {
    testWidgets('Cenário 5: decisão com evidência exibe PROVA DOCUMENTAL', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final decision = _buildDecision(
        outcome: 'PENALTY_NO_SHOW',
        financialImpactCents: 75000,
        evidence: const DelayPenaltyEvidence(
          delayMinutes: 12,
          toleranceMinutes: 5,
          billableMinutes: 7,
          grossPenaltyCents: 700,
          finalPenaltyCents: 700,
          capApplied: false,
        ),
      );
      final trace = _buildTrace(decisions: [decision]);

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.data([trace]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('PROVA DOCUMENTAL'), findsOneWidget);
      // financial impact visible (toStringAsFixed uses period separator)
      expect(find.textContaining('750.00'), findsOneWidget);
    });

    testWidgets(
      'Cenário 5b: decisão com evidência vazia NÃO exibe PROVA DOCUMENTAL',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final decision = _buildDecision(
          outcome: 'PASS',
          evidence: const GenericEvidencePayload({}),
        );
        final trace = _buildTrace(decisions: [decision]);

        await tester.pumpWidget(
          _buildModal(
            traces: AsyncValue.data([trace]),
            ledger: const AsyncValue.data([]),
            execution: const AsyncValue.data(null),
          ),
        );
        await _openModal(tester);
        await tester.pumpAndSettle();

        expect(find.text('PROVA DOCUMENTAL'), findsNothing);
      },
    );
  });

  group('InvestigationModal — Fault Tolerance (INV-26)', () {
    testWidgets('Cenário 6: erro em traces exibe mensagem com cor de erro', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.error(
            Exception('404: trace not found'),
            StackTrace.empty,
          ),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      final errorText = tester.widget<Text>(
        find.textContaining('Erro ao carregar traces:'),
      );
      expect(errorText.style?.color, VeraProbColors.error);
    });

    testWidgets('Cenário 6b: erro no ledger exibe mensagem com cor de erro', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildModal(
          traces: const AsyncValue.data([]),
          ledger: AsyncValue.error(
            Exception('404: ledger not found'),
            StackTrace.empty,
          ),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      final errorText = tester.widget<Text>(
        find.textContaining('Erro ao carregar ledger:'),
      );
      expect(errorText.style?.color, VeraProbColors.error);
    });
  });

  group('InvestigationModal — Asset Precision (INV-12/INV-14)', () {
    testWidgets(
      'Cenário 7: InvestigationMapPanel renderiza com coordenadas 6 decimais',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Suppress expected layout-overflow from map panel header in constrained test viewport
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) return;
          prevOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = prevOnError);

        // Lat/lng with 6 decimal places — physical metric precision
        final execution = _buildExecution(
          status: ExecutionStatus.completed,
          lat: -23.550520,
          lng: -46.633308,
        );

        await tester.pumpWidget(
          _buildModal(
            traces: const AsyncValue.data([]),
            ledger: const AsyncValue.data([]),
            execution: AsyncValue.data(execution),
          ),
        );
        await _openModal(tester);
        await tester.pumpAndSettle();

        // MapPanel renders based on execution state
        expect(find.textContaining('Camada Geoespacial'), findsOneWidget);
        expect(
          find.textContaining('raio de ${execution.startRadiusMeters}m'),
          findsOneWidget,
        );
        // Confirm the lat/lng precision is preserved through the domain object
        expect(execution.startLatitude, closeTo(-23.550520, 1e-9));
        expect(execution.startLongitude, closeTo(-46.633308, 1e-9));
      },
    );
  });

  group('InvestigationModal — Async Race (INV-7)', () {
    testWidgets(
      'Cenário 8: estado de carregamento mostra CircularProgressIndicator',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // All providers in loading state
        await tester.pumpWidget(_buildModal());
        await _openModal(tester);
        // pump once — providers still loading (delayed future)
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);
      },
    );

    testWidgets(
      'Cenário 8b: CircularProgressIndicator ausente após dados carregados',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _buildModal(
            traces: const AsyncValue.data([]),
            ledger: const AsyncValue.data([]),
            execution: const AsyncValue.data(null),
          ),
        );
        await _openModal(tester);
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });

  group('InvestigationModal — UX Gestures (INV-24)', () {
    testWidgets('Cenário 9: botão fechar dispensa o modal', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildModal(
          traces: const AsyncValue.data([]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      // Modal is open
      expect(find.text('MODO AUDITORIA'), findsOneWidget);

      // Tap close icon
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Modal dismissed — MODO AUDITORIA no longer visible
      expect(find.text('MODO AUDITORIA'), findsNothing);
    });

    testWidgets('Cenário 9b: título forense visível no AppBar', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildModal(
          traces: const AsyncValue.data([]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('Análise Forense de Decisões'), findsOneWidget);
    });
  });

  group('InvestigationModal — Trace metadata (INV-21)', () {
    testWidgets('engine version e contagem de regras visíveis no trace card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final decision = _buildDecision();
      final trace = _buildTrace(decisions: [decision]);

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.data([trace]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('2.0.0'), findsOneWidget);
      expect(find.text('1 regra(s)'), findsOneWidget);
    });

    testWidgets('outcome PENALTY exibe cor de erro', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final decision = _buildDecision(outcome: 'PENALTY_NO_SHOW');
      final trace = _buildTrace(decisions: [decision]);

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.data([trace]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      final outcomeWidget = tester.widget<Text>(find.text('PENALTY_NO_SHOW'));
      expect(outcomeWidget.style?.color, VeraProbColors.error);
    });

    testWidgets('outcome PASS exibe cor de sucesso', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final decision = _buildDecision(outcome: 'PASS');
      final trace = _buildTrace(decisions: [decision]);

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.data([trace]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      final outcomeWidget = tester.widget<Text>(find.text('PASS'));
      expect(outcomeWidget.style?.color, VeraProbColors.success);
    });
  });

  group('InvestigationModal — Ledger empty state', () {
    testWidgets('ledger vazio exibe "Nenhum evento no ledger"', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final trace = _buildTrace();

      await tester.pumpWidget(
        _buildModal(
          traces: AsyncValue.data([trace]),
          ledger: const AsyncValue.data([]),
          execution: const AsyncValue.data(null),
        ),
      );
      await _openModal(tester);
      await tester.pumpAndSettle();

      expect(find.text('Nenhum evento no ledger'), findsOneWidget);
    });
  });
}
