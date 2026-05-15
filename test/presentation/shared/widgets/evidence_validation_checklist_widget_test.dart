import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';
import 'package:veraprob/presentation/shared/ui/evidence_validation_checklist_widget.dart';

void main() {
  group('EvidenceValidationChecklistWidget — 3 Visible Forensic Steps', () {
    testWidgets('renders 3 distinct step labels in order', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvidenceValidationChecklistWidget(
              steps: [
                EvidenceValidationStep(
                  kind: EvidenceValidationStepKind.transfer,
                  status: EvidenceValidationStatus.running,
                ),
                EvidenceValidationStep(
                  kind: EvidenceValidationStepKind.digitalIdentity,
                  status: EvidenceValidationStatus.pending,
                ),
                EvidenceValidationStep(
                  kind: EvidenceValidationStepKind.probabilisticAudit,
                  status: EvidenceValidationStatus.pending,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('Transferência'), findsOneWidget);
      expect(find.textContaining('Identidade'), findsOneWidget);
      expect(find.textContaining('Auditoria'), findsOneWidget);
    });

    // ── Red Team Attack 1 — Evasion: stalls at "Auditoria Probabilística" ───
    testWidgets(
      'Red Team Attack 1: on ForensicViolationException, checklist stalls at '
      'Auditoria Probabilística and surfaces "não é uma foto original"',
      (tester) async {
        const violation = ForensicViolationException(
          message: 'Signature "<?php" found at offset 2831155',
          evidenceUrl: 'https://storage.example.com/evasion-27pct.png',
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EvidenceValidationChecklistWidget(
                steps: [
                  EvidenceValidationStep(
                    kind: EvidenceValidationStepKind.transfer,
                    status: EvidenceValidationStatus.completed,
                  ),
                  EvidenceValidationStep(
                    kind: EvidenceValidationStepKind.digitalIdentity,
                    status: EvidenceValidationStatus.completed,
                  ),
                  EvidenceValidationStep(
                    kind: EvidenceValidationStepKind.probabilisticAudit,
                    status: EvidenceValidationStatus.failed,
                    error: violation,
                  ),
                ],
              ),
            ),
          ),
        );

        expect(
          find.textContaining('não é uma foto original'),
          findsOneWidget,
          reason:
              'user must see actionable PT-BR message translated by '
              'ForensicErrorInterpreter, not the raw exception',
        );

        expect(
          find.byKey(const ValueKey('step-probabilisticAudit-failed')),
          findsOneWidget,
          reason: 'Probabilistic Audit must visually display failed state',
        );

        expect(
          find.byKey(const ValueKey('step-transfer-completed')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('step-digitalIdentity-completed')),
          findsOneWidget,
        );
      },
    );

    testWidgets('all steps completed → success indicators visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvidenceValidationChecklistWidget(
              steps: [
                EvidenceValidationStep(
                  kind: EvidenceValidationStepKind.transfer,
                  status: EvidenceValidationStatus.completed,
                ),
                EvidenceValidationStep(
                  kind: EvidenceValidationStepKind.digitalIdentity,
                  status: EvidenceValidationStatus.completed,
                ),
                EvidenceValidationStep(
                  kind: EvidenceValidationStepKind.probabilisticAudit,
                  status: EvidenceValidationStatus.completed,
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('step-transfer-completed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('step-digitalIdentity-completed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('step-probabilisticAudit-completed')),
        findsOneWidget,
      );
    });
  });
}
