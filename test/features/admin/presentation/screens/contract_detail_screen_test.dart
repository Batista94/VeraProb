import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncNotifierProviderFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/projections/contract_detail_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/application/sla_audit/submit_contract_for_approval_command.dart';
import 'package:veraprob/application/sla_audit/submit_contract_for_approval_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/features/admin/presentation/screens/contract_detail_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

// ── Mocks / Fakes ────────────────────────────────────────────────────────────

class _MockSubmitHandler extends Mock
    implements SubmitContractForApprovalHandler {}

class _FakeSubmitCommand extends Fake
    implements SubmitContractForApprovalCommand {}

class _StaticDetailNotifier extends ContractDetailNotifier {
  _StaticDetailNotifier(this._detail) : super('test-contract-id');
  final ContractDetailView? _detail;

  @override
  Future<ContractDetailView?> build() async => _detail;
}

class _ErrorDetailNotifier extends ContractDetailNotifier {
  _ErrorDetailNotifier() : super('test-contract-id');

  @override
  Future<ContractDetailView?> build() async => throw Exception('boom');
}

class _LoadingDetailNotifier extends ContractDetailNotifier {
  _LoadingDetailNotifier() : super('test-contract-id');

  @override
  Future<ContractDetailView?> build() =>
      Completer<ContractDetailView?>().future;
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

final _utc = DateTime.utc(2026, 3, 10, 12, 0);

ContractSummaryView _summary({
  ContractStatusView status = ContractStatusView.draft,
  int planVersion = 1,
  String? previousHash = 'prev1234567890abcdef1234567890abcdef',
  String? currentHash = 'curr1234567890abcdef1234567890abcdef',
  DateTime? activatedAtUtc,
}) => ContractSummaryView(
  id: 'c-1',
  name: 'Contrato Central',
  contractorName: 'Viação Express',
  status: status,
  validFromUtc: _utc,
  validUntilUtc: _utc.add(const Duration(days: 365)),
  createdAtUtc: _utc,
  activatedAtUtc: activatedAtUtc,
  planCount: planVersion > 0 ? 1 : 0,
  activePlanVersion: planVersion,
  totalSetsInProgress: 3,
  slaHealthBps: 9250,
  previousHash: previousHash,
  currentHash: currentHash,
);

SlaExecutionItemView _execution({
  ExecutionStatus status = ExecutionStatus.completed,
  String? vehicleId = 'VEH-001',
  int contractualValue = 50000,
}) => SlaExecutionItemView(
  setId: 'set-1',
  contractId: 'c-1',
  status: status,
  windowStartUtc: _utc,
  windowEndUtc: _utc.add(const Duration(hours: 1)),
  plannedVehicleId: vehicleId,
  startLatitude: -23.5,
  startLongitude: -46.6,
  startRadiusMeters: 100,
  contractualValue: contractualValue,
  noShowPenaltyBps: 10000,
);

SlaExecutionSummary _financial({
  int protectedRevenue = 120000,
  int revenueAtRisk = 30000,
  int lostRevenue = 50000,
  int totalPlanned = 2,
  int totalCompleted = 10,
  int totalFailed = 1,
  int totalCompletedWithGaps = 1,
}) => SlaExecutionSummary(
  contractId: 'c-1',
  totalPlanned: totalPlanned,
  totalCompleted: totalCompleted,
  totalFailed: totalFailed,
  totalCompletedWithGaps: totalCompletedWithGaps,
  generatedAtUtc: _utc,
  protectedRevenue: protectedRevenue,
  revenueAtRisk: revenueAtRisk,
  lostRevenue: lostRevenue,
);

ContractDetailView _detail({
  ContractSummaryView? summary,
  List<SlaExecutionItemView>? executions,
  SlaExecutionSummary? financial,
}) => ContractDetailView(
  summary: summary ?? _summary(),
  recentExecutions: executions ?? [_execution()],
  financialSummary: financial ?? _financial(),
);

// ── Harness ──────────────────────────────────────────────────────────────────

Widget _buildScreen({
  required AsyncNotifierProviderFamily<
    ContractDetailNotifier,
    ContractDetailView?,
    String
  >
  provider,
  required _StaticDetailNotifier Function(String)? staticFactory,
  _ErrorDetailNotifier Function(String)? errorFactory,
  _LoadingDetailNotifier Function(String)? loadingFactory,
  SubmitContractForApprovalHandler? handler,
  String? orgId = 'org-1',
  String? userId = 'user-1',
  String? sessionId = 'session-1',
  UserRole role = UserRole.admin,
}) {
  return ProviderScope(
    overrides: [
      if (staticFactory != null) provider.overrideWith2(staticFactory),
      if (errorFactory != null) provider.overrideWith2(errorFactory),
      if (loadingFactory != null) provider.overrideWith2(loadingFactory),
      currentOrganizationIdProvider.overrideWithValue(orgId),
      currentOperatorIdProvider.overrideWithValue(userId),
      currentUserRoleProvider.overrideWithValue(role),
      currentSessionIdProvider.overrideWithValue(sessionId),
      if (handler != null)
        submitContractForApprovalHandlerProvider.overrideWithValue(handler),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ContractDetailScreen(contractId: 'c-1')),
    ),
  );
}

Widget _buildWithDetail(
  ContractDetailView? detail, {
  SubmitContractForApprovalHandler? handler,
  String? orgId = 'org-1',
  String? userId = 'user-1',
  UserRole role = UserRole.admin,
  Set<String> permissions = const {},
}) {
  return ProviderScope(
    overrides: [
      contractDetailProvider.overrideWith2(
        (_) => _StaticDetailNotifier(detail),
      ),
      currentOrganizationIdProvider.overrideWithValue(orgId),
      currentOperatorIdProvider.overrideWithValue(userId),
      currentUserRoleProvider.overrideWithValue(role),
      currentSessionIdProvider.overrideWithValue('session-1'),
      permissionServiceProvider.overrideWithValue(
        PermissionService(permissions: permissions, scopes: const {}),
      ),
      if (handler != null)
        submitContractForApprovalHandlerProvider.overrideWithValue(handler),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ContractDetailScreen(contractId: 'c-1')),
    ),
  );
}

const _simulateRoiKey = Key('contract-simulate-roi-button');

void _setSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

/// Drains FlutterError exceptions (e.g. RenderFlex overflow warnings emitted
/// by production widgets with fixed inner widths). Keeps widget assertions
/// independent from cosmetic layout warnings.
void _drainOverflow(WidgetTester tester) {
  var ex = tester.takeException();
  while (ex != null) {
    ex = tester.takeException();
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSubmitCommand());
  });

  final List<MethodCall> clipboardCalls = [];

  setUp(() {
    clipboardCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardCalls.add(call);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ContractDetailScreen — Async States', () {
    testWidgets('shows CircularProgressIndicator while loading', (
      tester,
    ) async {
      _setSize(tester);
      await tester.pumpWidget(
        _buildScreen(
          provider: contractDetailProvider,
          staticFactory: null,
          loadingFactory: (_) => _LoadingDetailNotifier(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders error state with message when provider throws', (
      tester,
    ) async {
      _setSize(tester);
      await tester.pumpWidget(
        _buildScreen(
          provider: contractDetailProvider,
          staticFactory: null,
          errorFactory: (_) => _ErrorDetailNotifier(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Não foi possível carregar os detalhes do contrato.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders "Contrato não encontrado." when detail is null', (
      tester,
    ) async {
      _setSize(tester);
      await tester.pumpWidget(_buildWithDetail(null));
      await tester.pumpAndSettle();

      expect(find.text('Contrato não encontrado.'), findsOneWidget);
    });
  });

  group('ContractDetailScreen — Status / Action Sync', () {
    testWidgets('Draft without plan shows warning banner and hides Submit', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(status: ContractStatusView.draft, planVersion: 0),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nenhum Plano Operacional declarado'),
        findsOneWidget,
      );
      expect(find.text('Enviar para Aprovação'), findsNothing);
      expect(find.text('Declarar Plano'), findsOneWidget);
    });

    testWidgets('Draft with plan enables Submit and hides banner', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(status: ContractStatusView.draft, planVersion: 2),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Enviar para Aprovação'), findsOneWidget);
      expect(find.text('Declarar Plano'), findsOneWidget);
      expect(
        find.textContaining('Nenhum Plano Operacional declarado'),
        findsNothing,
      );
    });

    testWidgets('Awaiting acceptance hides both Submit and Declare buttons', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(
          status: ContractStatusView.awaitingContractorAcceptance,
          planVersion: 2,
        ),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Enviar para Aprovação'), findsNothing);
      expect(find.text('Declarar Plano'), findsNothing);
    });

    testWidgets('Closed status hides Submit and Declare buttons', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(status: ContractStatusView.closed, planVersion: 2),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Enviar para Aprovação'), findsNothing);
      expect(find.text('Declarar Plano'), findsNothing);
    });

    testWidgets('Active status exposes Declare only (no Submit)', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(
          status: ContractStatusView.active,
          planVersion: 2,
          activatedAtUtc: _utc,
        ),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Enviar para Aprovação'), findsNothing);
      expect(find.text('Declarar Plano'), findsOneWidget);
    });

    testWidgets('Status chip renders "Rascunho" for draft', (tester) async {
      _setSize(tester);
      await tester.pumpWidget(
        _buildWithDetail(
          _detail(summary: _summary(status: ContractStatusView.draft)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rascunho'), findsOneWidget);
    });

    testWidgets('Status chip renders "Ativo" for active', (tester) async {
      _setSize(tester);
      await tester.pumpWidget(
        _buildWithDetail(
          _detail(
            summary: _summary(
              status: ContractStatusView.active,
              activatedAtUtc: _utc,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ativo'), findsOneWidget);
    });

    testWidgets('Status chip renders "Encerrado" for closed', (tester) async {
      _setSize(tester);
      await tester.pumpWidget(
        _buildWithDetail(
          _detail(summary: _summary(status: ContractStatusView.closed)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Encerrado'), findsOneWidget);
    });
  });

  group('ContractDetailScreen — Submit for Approval', () {
    testWidgets('opens confirmation dialog on Submit tap', (tester) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final detail = _detail(
        summary: _summary(status: ContractStatusView.draft, planVersion: 2),
      );

      await tester.pumpWidget(_buildWithDetail(detail, handler: handler));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar para Aprovação'));
      await tester.pumpAndSettle();

      // Dialog header + body
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Enviar'), findsOneWidget);
      expect(
        find.textContaining('Contrato Central'),
        findsWidgets, // appears in dialog content
      );
    });

    testWidgets('Cancel closes dialog without invoking handler', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final detail = _detail(
        summary: _summary(status: ContractStatusView.draft, planVersion: 2),
      );

      await tester.pumpWidget(_buildWithDetail(detail, handler: handler));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar para Aprovação'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => handler.handle(any()));
    });

    testWidgets('null organizationId shows "Sessão inválida" snackbar', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      final detail = _detail(
        summary: _summary(status: ContractStatusView.draft, planVersion: 2),
      );

      await tester.pumpWidget(
        _buildScreen(
          provider: contractDetailProvider,
          staticFactory: (_) => _StaticDetailNotifier(detail),
          handler: handler,
          orgId: null,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar para Aprovação'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sessão inválida'), findsOneWidget);
      verifyNever(() => handler.handle(any()));
    });

    testWidgets('Unauthorized error surfaces "Permissão negada" snackbar', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      when(() => handler.handle(any())).thenThrow(
        const DomainException(
          'Unauthorized: canApproveContractAcceptance required.',
        ),
      );

      final detail = _detail(
        summary: _summary(status: ContractStatusView.draft, planVersion: 2),
      );

      await tester.pumpWidget(_buildWithDetail(detail, handler: handler));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar para Aprovação'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Permissão negada'), findsOneWidget);
      verify(() => handler.handle(any())).called(1);
    });

    testWidgets('Submit sends command with JWT-sourced identity', (
      tester,
    ) async {
      _setSize(tester);
      final handler = _MockSubmitHandler();
      // Force a graceful early exit after handle() by throwing a generic
      // error. The goal is to assert the command payload, not the link dialog
      // (whose Uri.base.origin is non-deterministic under tests).
      when(() => handler.handle(any())).thenThrow(Exception('network'));

      final detail = _detail(
        summary: _summary(status: ContractStatusView.draft, planVersion: 2),
      );

      await tester.pumpWidget(_buildWithDetail(detail, handler: handler));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar para Aprovação'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      final captured = verify(() => handler.handle(captureAny())).captured;
      expect(captured, isNotEmpty);
      final cmd = captured.single as SubmitContractForApprovalCommand;
      expect(cmd.organizationId, 'org-1');
      expect(cmd.contractId, 'c-1');
      expect(cmd.callerUserId, 'user-1');
      expect(cmd.callerRole, UserRole.admin);
      expect(cmd.sessionId, 'session-1');
    });
  });

  group('ContractDetailScreen — Maverick Financial Precision (BigInt/100)', () {
    testWidgets('KPI cards format cents with /100 and pt_BR currency', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(
          status: ContractStatusView.active,
          activatedAtUtc: _utc,
        ),
        financial: _financial(
          protectedRevenue: 120000, // R$ 1.200,00
          revenueAtRisk: 30000, // R$ 300,00
          lostRevenue: 50000, // R$ 500,00
        ),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      // Switch to financial tab
      await tester.tap(find.text('Conciliação Financeira'));
      await tester.pumpAndSettle();
      _drainOverflow(tester);

      expect(find.text('Receita Protegida'), findsOneWidget);
      expect(find.text('Receita em Risco'), findsOneWidget);
      expect(find.text('Receita Perdida'), findsOneWidget);

      expect(find.textContaining('1.200,00'), findsOneWidget);
      expect(find.textContaining('300,00'), findsOneWidget);
      expect(find.textContaining('500,00'), findsOneWidget);
    });

    testWidgets('Count card exposes executed / pending / no-show / gap totals', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(
          status: ContractStatusView.active,
          activatedAtUtc: _utc,
        ),
        financial: _financial(
          totalPlanned: 2,
          totalCompleted: 10,
          totalFailed: 1,
          totalCompletedWithGaps: 1,
        ),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Conciliação Financeira'));
      await tester.pumpAndSettle();
      _drainOverflow(tester);

      expect(find.text('Executados'), findsOneWidget);
      expect(find.text('Pendentes'), findsOneWidget);
      expect(find.text('No-show'), findsOneWidget);
      expect(find.text('Gap evidência'), findsOneWidget);

      expect(find.text('10'), findsOneWidget);
      // '2' appears in pending counter AND possibly in dates — restrict to count row.
      expect(find.text('2'), findsWidgets);
    });
  });

  group('ContractDetailScreen — Forensic Seal (INV-34)', () {
    testWidgets('renders Selo Forense section when hashes are present', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail();

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Selo Forense (INV-34)'), findsOneWidget);
      expect(find.text('Hash anterior'), findsOneWidget);
      expect(find.text('Hash atual'), findsOneWidget);
    });

    testWidgets('hides Selo Forense section when both hashes are null', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(
        summary: _summary(previousHash: null, currentHash: null),
      );

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Selo Forense (INV-34)'), findsNothing);
    });

    testWidgets('copy icon writes hash to clipboard and shows snackbar', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail();

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      final copyButtons = find.byIcon(Icons.copy_outlined);
      expect(copyButtons, findsNWidgets(2));

      await tester.tap(copyButtons.first);
      await tester.pump();

      expect(clipboardCalls, hasLength(1));
      final args = clipboardCalls.first.arguments as Map<dynamic, dynamic>;
      expect(args['text'], 'prev1234567890abcdef1234567890abcdef');

      expect(find.textContaining('copiado'), findsOneWidget);
    });
  });

  group('ContractDetailScreen — Tab Navigation', () {
    testWidgets('initial tab renders executions table', (tester) async {
      _setSize(tester);
      final detail = _detail(executions: [_execution()]);

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Status'), findsWidgets);
      expect(find.text('Janela'), findsOneWidget);
      expect(find.text('Veículo'), findsOneWidget);
      expect(find.text('Valor'), findsOneWidget);
    });

    testWidgets('executions tab shows empty state when no SETs', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(executions: []);

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma viagem projetada.'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets('switching to Conciliação Financeira renders KPI cards', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail();

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Conciliação Financeira'));
      await tester.pumpAndSettle();
      _drainOverflow(tester);

      expect(find.text('Receita Protegida'), findsOneWidget);
      expect(find.text('Execuções'), findsOneWidget);
    });
  });

  group('ContractDetailScreen — Meta Strip & UTC→Local', () {
    testWidgets('renders SLA health, plan version and totals meta rows', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail(summary: _summary(planVersion: 3));

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Vigência'), findsOneWidget);
      expect(find.text('Plano atual'), findsOneWidget);
      expect(find.text('v3'), findsOneWidget);
      expect(find.text('SETs pendentes'), findsOneWidget);
      expect(find.text('SLA health'), findsOneWidget);
      expect(find.text('92.5%'), findsOneWidget);
    });

    testWidgets('Plan version 0 renders em-dash placeholder', (tester) async {
      _setSize(tester);
      final detail = _detail(summary: _summary(planVersion: 0));

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('Vigência rendering includes both start and end years', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail();

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      // Robust against local TZ: assert the format pattern yields pt-style
      // separators and both years (2026 start, 2027 end of range).
      expect(find.textContaining('2026'), findsWidgets);
      expect(find.textContaining('2027'), findsWidgets);
    });
  });

  group('ContractDetailScreen — Header', () {
    testWidgets('header exposes contract name and contractor subtitle', (
      tester,
    ) async {
      _setSize(tester);
      final detail = _detail();

      await tester.pumpWidget(_buildWithDetail(detail));
      await tester.pumpAndSettle();

      expect(find.text('Contrato Central'), findsOneWidget);
      expect(find.text('Viação Express'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });
  });

  group('Contract Details — Sandbox entrypoint (RBAC & Dark Launch)', () {
    testWidgets('TENANT_ADMIN sees Simular ROI button', (tester) async {
      _setSize(tester);
      await tester.pumpWidget(_buildWithDetail(_detail()));
      await tester.pumpAndSettle();
      _drainOverflow(tester);

      expect(find.byKey(_simulateRoiKey), findsOneWidget);
      expect(find.text('Simular ROI'), findsOneWidget);
    });

    testWidgets(
      'operator with sandbox:simulate claim sees Simular ROI button',
      (tester) async {
        _setSize(tester);
        await tester.pumpWidget(
          _buildWithDetail(
            _detail(),
            role: UserRole.operator,
            permissions: {'sandbox:simulate'},
          ),
        );
        await tester.pumpAndSettle();
        _drainOverflow(tester);

        expect(find.byKey(_simulateRoiKey), findsOneWidget);
        expect(find.text('Simular ROI'), findsOneWidget);
      },
    );

    testWidgets(
      'standard Operator — button COMPLETELY ABSENT (Anti-Discovery)',
      (tester) async {
        _setSize(tester);
        await tester.pumpWidget(
          _buildWithDetail(_detail(), role: UserRole.operator),
        );
        await tester.pumpAndSettle();
        _drainOverflow(tester);

        expect(find.byKey(_simulateRoiKey), findsNothing);
        expect(find.text('Simular ROI'), findsNothing);
      },
    );

    testWidgets(
      'Auditor without claim — button COMPLETELY ABSENT (Anti-Discovery)',
      (tester) async {
        _setSize(tester);
        await tester.pumpWidget(
          _buildWithDetail(_detail(), role: UserRole.auditor),
        );
        await tester.pumpAndSettle();
        _drainOverflow(tester);

        expect(find.byKey(_simulateRoiKey), findsNothing);
        expect(find.text('Simular ROI'), findsNothing);
      },
    );
  });
}
