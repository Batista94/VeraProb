import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sanction_simulation_service.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue_screen.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

// ── Fake simulation service ───────────────────────────────────────────────────

class _FakeSimulationService extends SanctionSimulationService {
  final Object? _toThrow;

  _FakeSimulationService({Object? toThrow})
    : _toThrow = toThrow,
      super(
        ledger: InMemorySlaAuditLedgerRepository(),
        contracts: InMemoryContractRepository(),
        clock: FakeDateTimeProvider(DateTime.utc(2026, 1, 1)),
      );

  @override
  Future<void> simulateSpeedViolation({
    required String organizationId,
    required String vehiclePlate,
    String operatorName = 'Motorista Teste',
    double speed = 88.5,
    double limit = 80.0,
  }) async {
    if (_toThrow != null) throw _toThrow;
  }
}

// ── HTTP mock ─────────────────────────────────────────────────────────────────

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

class _MockSealedNotifier extends SealedSanctionsNotifier {
  final SealedSanctionsState mockState;
  _MockSealedNotifier(this.mockState);

  @override
  SealedSanctionsState build() => mockState;

  @override
  Future<void> fetchNextPage({bool clear = false}) async {}
}

final mockSealedState = SealedSanctionsState(
  items: const [],
  isLoading: false,
  hasMore: false,
  startDate: DateTime.utc(2026, 1, 1),
  endDate: DateTime.utc(2026, 1, 8),
);

Widget _buildScreen({List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      pendingSanctionsStreamProvider.overrideWith((ref) => Stream.value([])),
      sealedSanctionsNotifierProvider.overrideWith(
        () => _MockSealedNotifier(mockSealedState),
      ),
      disputedSanctionsStreamProvider.overrideWith((ref) => Stream.value([])),
      ...extraOverrides,
    ],
    child: const MaterialApp(home: AuditorQueueScreen()),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('AuditorQueueScreen', () {
    testWidgets('renders header title and SegmentedButton tabs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Tribunal de Auditoria'), findsOneWidget);
      expect(find.textContaining('Pendentes'), findsOneWidget);
      expect(find.text('Concluídos'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows empty state when no pending sanctions', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Nenhum veredito pendente'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets(
      'toggling to Concluídos shows DateFilterBar and sealed empty state',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        // Tap on the "Concluídos" tab segment
        final seladosTab = find.text('Concluídos');
        await tester.ensureVisible(seladosTab);
        await tester.tap(seladosTab);
        await tester.pumpAndSettle();

        // Date range filter bar must render
        expect(find.textContaining('Período:'), findsOneWidget);
        expect(
          find.text('Nenhum veredito selado encontrado neste período.'),
          findsOneWidget,
        );

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });

  // ── Simulation SnackBar contract ──────────────────────────────────────────

  group('_SimulateButton SnackBar contract', () {
    testWidgets(
      'shows success SnackBar when simulation completes without error',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          _buildScreen(
            extraOverrides: [
              currentOrganizationIdProvider.overrideWithValue('org-test'),
              sanctionSimulationServiceProvider.overrideWithValue(
                _FakeSimulationService(),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Gerar Sanção de Teste').first);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila.',
          ),
          findsOneWidget,
        );

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      'shows error SnackBar on unexpected exception — never shows success',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          _buildScreen(
            extraOverrides: [
              currentOrganizationIdProvider.overrideWithValue('org-test'),
              sanctionSimulationServiceProvider.overrideWithValue(
                _FakeSimulationService(
                  toThrow: Exception('DB trigger failure'),
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Gerar Sanção de Teste').first);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila.',
          ),
          findsNothing,
        );
        expect(
          find.text(
            'Não foi possível simular a sanção. Verifique se há contratos ativos.',
          ),
          findsOneWidget,
        );

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });
}
