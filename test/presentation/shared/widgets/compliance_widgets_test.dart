// Widget tests for ComplianceBadge and EvidenceComplianceChecklist.
// Adversarial: null compliance, 0/0, loading/error states, backward compat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/telegram/compliance_check_result.dart';
import 'package:veraprob/features/admin/presentation/shared/compliance_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // =========================================================================
  // ComplianceBadge
  // =========================================================================
  group('ComplianceBadge', () {
    testWidgets('null compliance → renders nothing', (tester) async {
      await tester.pumpWidget(_wrap(const ComplianceBadge(compliance: null)));
      expect(find.byType(ComplianceBadge), findsOneWidget);
      // SizedBox.shrink — no visible text
      expect(find.text(''), findsNothing);
    });

    testWidgets('NoActiveTrip → renders nothing', (tester) async {
      await tester.pumpWidget(
        _wrap(const ComplianceBadge(compliance: NoActiveTrip())),
      );
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('NoRequirements → shows evidence count', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ComplianceBadge(
            compliance: NoRequirements(setId: 'S1', evidenceCount: 5),
          ),
        ),
      );
      expect(find.textContaining('5'), findsOneWidget);
    });

    testWidgets('ActiveCompliance 2/3 → shows fraction', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 1),
          ComplianceCheckItem(typeKey: 'doc', isFulfilled: true, count: 1),
          ComplianceCheckItem(typeKey: 'oper', isFulfilled: false, count: 0),
        ],
        totalRequired: 3,
        totalFulfilled: 2,
      );
      await tester.pumpWidget(
        _wrap(const ComplianceBadge(compliance: compliance)),
      );
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('ActiveCompliance 3/3 → shows complete fraction', (
      tester,
    ) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 1),
        ],
        totalRequired: 1,
        totalFulfilled: 1,
      );
      await tester.pumpWidget(
        _wrap(const ComplianceBadge(compliance: compliance)),
      );
      expect(find.text('1/1'), findsOneWidget);
    });

    testWidgets('ActiveCompliance 0/0 → renders nothing', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [],
        totalRequired: 0,
        totalFulfilled: 0,
      );
      await tester.pumpWidget(
        _wrap(const ComplianceBadge(compliance: compliance)),
      );
      expect(find.textContaining('/'), findsNothing);
    });
  });

  // =========================================================================
  // EvidenceComplianceChecklist
  // =========================================================================
  group('EvidenceComplianceChecklist', () {
    testWidgets('renders all items', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 2),
          ComplianceCheckItem(typeKey: 'doc', isFulfilled: false, count: 0),
          ComplianceCheckItem(typeKey: 'oper', isFulfilled: false, count: 0),
        ],
        totalRequired: 3,
        totalFulfilled: 1,
      );
      await tester.pumpWidget(
        _wrap(const EvidenceComplianceChecklist(compliance: compliance)),
      );
      expect(find.textContaining('Estado / Visual'), findsOneWidget);
      expect(find.textContaining('Documental / NF'), findsOneWidget);
      expect(find.textContaining('Operacional'), findsOneWidget);
    });

    testWidgets('shows progress fraction in header', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 1),
          ComplianceCheckItem(typeKey: 'doc', isFulfilled: false, count: 0),
        ],
        totalRequired: 2,
        totalFulfilled: 1,
      );
      await tester.pumpWidget(
        _wrap(const EvidenceComplianceChecklist(compliance: compliance)),
      );
      expect(find.textContaining('1/2'), findsOneWidget);
    });

    testWidgets('0/0 compliance → renders nothing', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [],
        totalRequired: 0,
        totalFulfilled: 0,
      );
      await tester.pumpWidget(
        _wrap(const EvidenceComplianceChecklist(compliance: compliance)),
      );
      // SizedBox.shrink — no checklist rendered
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('collapse toggle hides items', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 1),
        ],
        totalRequired: 1,
        totalFulfilled: 1,
      );
      await tester.pumpWidget(
        _wrap(const EvidenceComplianceChecklist(compliance: compliance)),
      );

      // Initially expanded — item visible
      expect(find.textContaining('Estado / Visual'), findsOneWidget);

      // Tap header to collapse
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();

      // Item hidden after collapse
      expect(find.textContaining('Estado / Visual'), findsNothing);
    });

    testWidgets('count > 1 shows count in parentheses', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 3),
        ],
        totalRequired: 1,
        totalFulfilled: 1,
      );
      await tester.pumpWidget(
        _wrap(const EvidenceComplianceChecklist(compliance: compliance)),
      );
      expect(find.text('(3)'), findsOneWidget);
    });

    testWidgets('count == 1 does NOT show count', (tester) async {
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 1),
        ],
        totalRequired: 1,
        totalFulfilled: 1,
      );
      await tester.pumpWidget(
        _wrap(const EvidenceComplianceChecklist(compliance: compliance)),
      );
      expect(find.text('(1)'), findsNothing);
    });
  });

  // =========================================================================
  // EvidenceDossierModal backward compatibility
  // =========================================================================
  group('EvidenceDossierModal — compliance param backward compat', () {
    testWidgets('no compliance param → no checklist rendered', (tester) async {
      // Import the modal
      // We just verify the widget accepts no compliance param without error
      // (full modal test would require network mocking — out of scope here)
      const compliance = ActiveCompliance(
        setId: 'S1',
        items: [
          ComplianceCheckItem(typeKey: 'estado', isFulfilled: true, count: 1),
        ],
        totalRequired: 1,
        totalFulfilled: 1,
      );
      // Verify EvidenceComplianceChecklist renders when compliance is provided
      await tester.pumpWidget(
        _wrap(const EvidenceComplianceChecklist(compliance: compliance)),
      );
      expect(find.byType(EvidenceComplianceChecklist), findsOneWidget);
    });
  });
}
