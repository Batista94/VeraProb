import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_delta.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';
import 'package:veraprob/presentation/sandbox/widgets/dashboard/sandbox_delta_bps.dart';
import 'package:veraprob/presentation/sandbox/widgets/dashboard/sandbox_results_dashboard.dart';
import 'package:veraprob/presentation/theme/sandbox_theme_extension.dart';

SandboxSimulationSession _session({
  int baseline = 8420000,
  int simulated = 7157000,
  int deltaCents = 1263000,
  int? deltaBps = 1500,
}) {
  return SandboxSimulationSession.reconstitute(
    id: 'sess-1',
    organizationId: 'org-1',
    contractId: 'ct-1',
    sessionLabel: 'Teste Tolerância 15min',
    periodStartUtc: DateTime.utc(2026, 1, 1),
    periodEndUtc: DateTime.utc(2026, 6, 30),
    overridesSnapshot: const SandboxSimulationOverrides(),
    baselineTotalFines: Money(baseline),
    simulatedTotalFines: Money(simulated),
    deltaCents: deltaCents,
    deltaBps: deltaBps,
    baselineEventCount: 847,
    simulatedCappedEventCount: 18,
    createdByUserId: 'user-1',
    createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    expiresAtUtc: DateTime.utc(2026, 7, 31, 10),
  );
}

List<SandboxSimulationResult> _results() {
  SandboxSimulationResult row({
    required String id,
    required String type,
    required int baseline,
    required int simulated,
  }) {
    return SandboxSimulationResult.reconstitute(
      id: id,
      sessionId: 'sess-1',
      organizationId: 'org-1',
      sourceLedgerEntryId: 'led-$id',
      sourceEventType: type,
      occurredAtUtc: DateTime.utc(2026, 3, 1),
      baselineFine: Money(baseline),
      baselineRuleSnapshot: const {},
      simulatedFine: Money(simulated),
      simulatedRuleApplied: const {},
      wasOverrideApplied: true,
      createdAtUtc: DateTime.utc(2026, 7, 1),
    );
  }

  return [
    row(
      id: '1',
      type: 'SANCTION_RECOMMENDED',
      baseline: 4210000,
      simulated: 3548500,
    ),
    row(
      id: '2',
      type: 'NO_SHOW_PENALTY',
      baseline: 2840000,
      simulated: 2414000,
    ),
    row(
      id: '3',
      type: 'SANCTION_RECOMMENDED',
      baseline: 1370000,
      simulated: 1194500,
    ),
  ];
}

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [SandboxThemeExtension.defaults()],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('SandboxDeltaBps — INV-5 symmetric rounding', () {
    test('exact 15% savings → 1500 bps', () {
      expect(
        SandboxDeltaBps.compute(
          baselineCents: 8420000,
          simulatedCents: 7157000,
        ),
        1500,
      );
    });

    test('symmetric rounding at half-up boundary', () {
      // numer/den would truncate below .5 without half-bias.
      expect(
        SandboxDeltaBps.compute(baselineCents: 3, simulatedCents: 1),
        6667, // (2*10000 + 1) ~/ 3 with half = 6667
      );
    });

    test('cost increase yields negative bps', () {
      expect(
        SandboxDeltaBps.compute(
          baselineCents: 1000000,
          simulatedCents: 1150000,
        ),
        -1500,
      );
    });

    test('zero baseline returns null', () {
      expect(
        SandboxDeltaBps.compute(baselineCents: 0, simulatedCents: 100),
        isNull,
      );
    });
  });

  group('SandboxResultsDashboard — A/B render', () {
    testWidgets('simulated fines show ~ prefix and textSecondary color', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: _session(),
            results: _results(),
            isLoading: false,
            onExit: () {},
          ),
        ),
      );

      expect(find.text('~R\$ 71.570,00'), findsWidgets);

      final simulatedTexts = tester.widgetList<Text>(
        find.text('~R\$ 71.570,00'),
      );
      for (final text in simulatedTexts) {
        expect(text.style?.color, VeraProbColors.textSecondary);
      }
    });

    testWidgets('delta BPS is shown with symmetric precision', (tester) async {
      final session = _session();
      final bps = SandboxDeltaBps.compute(
        baselineCents: session.baselineTotalFines.cents,
        simulatedCents: session.simulatedTotalFines.cents,
      );
      expect(bps, 1500);

      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: session,
            results: _results(),
            isLoading: false,
            onExit: () {},
          ),
        ),
      );

      expect(find.textContaining('1.500'), findsWidgets);
      expect(find.textContaining('bps'), findsWidgets);
    });

    testWidgets('savings delta uses success/green style', (tester) async {
      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: _session(),
            results: _results(),
            isLoading: false,
            onExit: () {},
          ),
        ),
      );

      final delta = SandboxSimulationDelta.fromSession(_session());
      expect(delta.direction, SandboxDeltaDirection.savings);

      final impact = find.byKey(const Key('sandbox-delta-impact'));
      expect(impact, findsOneWidget);
      final container = tester.widget<DecoratedBox>(
        find.descendant(of: impact, matching: find.byType(DecoratedBox)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, VeraProbColors.success.withValues(alpha: 0.12));
    });

    testWidgets('cost increase delta uses warning/alert style', (tester) async {
      final worse = _session(
        baseline: 7000000,
        simulated: 8400000,
        deltaCents: -1400000,
        deltaBps: -2000,
      );

      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: worse,
            results: const [],
            isLoading: false,
            onExit: () {},
          ),
        ),
      );

      expect(
        SandboxSimulationDelta.fromSession(worse).direction,
        SandboxDeltaDirection.increase,
      );

      final impact = find.byKey(const Key('sandbox-delta-impact'));
      final container = tester.widget<DecoratedBox>(
        find.descendant(of: impact, matching: find.byType(DecoratedBox)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, VeraProbColors.warning.withValues(alpha: 0.12));
    });

    testWidgets('Exportar PDF present but disabled while loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: _session(),
            results: _results(),
            isLoading: true,
            onExit: () {},
          ),
        ),
      );

      expect(find.text('Exportar PDF'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportar PDF'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Exportar PDF enabled when not loading', (tester) async {
      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: _session(),
            results: _results(),
            isLoading: false,
            onExit: () {},
          ),
        ),
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportar PDF'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Sair do Modo Simulação invokes onExit', (tester) async {
      var exited = false;
      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: _session(),
            results: _results(),
            isLoading: false,
            onExit: () => exited = true,
          ),
        ),
      );

      await tester.tap(find.text('Sair do Modo Simulação'));
      await tester.pump();
      expect(exited, isTrue);
    });

    testWidgets('shows A/B cards and rule-type breakdown labels', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SandboxResultsDashboard(
            session: _session(),
            results: _results(),
            isLoading: false,
            onExit: () {},
          ),
        ),
      );

      expect(find.textContaining('BASELINE'), findsOneWidget);
      expect(find.textContaining('SIMULADO'), findsOneWidget);
      expect(find.textContaining('NO_SHOW_PENALTY'), findsOneWidget);
      expect(find.textContaining('SANCTION_RECOMMENDED'), findsOneWidget);
    });
  });
}
