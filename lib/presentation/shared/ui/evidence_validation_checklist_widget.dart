/// Forensic Audit Signature: CX-05-v2.3 / UX-Integrity
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb UX/Ops
///
/// Visible, truthful checklist of the 3 forensic validation steps run for
/// every evidence upload:
///   1. Transferência da Evidência           (bytes moved, server-received)
///   2. Verificação de Identidade Digital    (SHA-256 seal — INV-9)
///   3. Auditoria Probabilística (128 KB)    (N=7 adaptive probes — CX-05-v2.3)
///
/// On failure, surfaces the PT-BR message translated by
/// [ForensicErrorInterpreter] — never a raw stack trace (INV-10).
library;

import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/justification/forensic_error_interpreter.dart';
import 'package:veraprob/core/theme/app_theme.dart';

enum EvidenceValidationStepKind {
  transfer,
  digitalIdentity,
  probabilisticAudit,
}

enum EvidenceValidationStatus { pending, running, completed, failed }

class EvidenceValidationStep {
  final EvidenceValidationStepKind kind;
  final EvidenceValidationStatus status;
  final Object? error;

  const EvidenceValidationStep({
    required this.kind,
    required this.status,
    this.error,
  });
}

class EvidenceValidationChecklistWidget extends StatelessWidget {
  final List<EvidenceValidationStep> steps;
  final ForensicErrorInterpreter interpreter;

  const EvidenceValidationChecklistWidget({
    super.key,
    required this.steps,
    this.interpreter = const ForensicErrorInterpreter(),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VeraProbSpacing.md),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        border: Border.all(color: VeraProbColors.border),
        borderRadius: VeraProbRadii.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'VALIDAÇÃO FORENSE',
            style: TextStyle(
              color: VeraProbColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: VeraProbSpacing.sm),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: VeraProbSpacing.xs),
              child: _StepTile(step: step, interpreter: interpreter),
            ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final EvidenceValidationStep step;
  final ForensicErrorInterpreter interpreter;

  const _StepTile({required this.step, required this.interpreter});

  @override
  Widget build(BuildContext context) {
    final title = _titleFor(step.kind);
    final subtitle = _subtitleFor(step.kind);

    return Row(
      key: ValueKey('step-${step.kind.name}-${step.status.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusIcon(status: step.status),
        const SizedBox(width: VeraProbSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: VeraProbColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: VeraProbColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              if (step.status == EvidenceValidationStatus.failed &&
                  step.error != null) ...[
                const SizedBox(height: VeraProbSpacing.xs),
                _FailureBlock(interpreted: interpreter.interpret(step.error!)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _titleFor(EvidenceValidationStepKind kind) {
    return switch (kind) {
      EvidenceValidationStepKind.transfer => 'Transferência da Evidência',
      EvidenceValidationStepKind.digitalIdentity =>
        'Verificação de Identidade Digital',
      EvidenceValidationStepKind.probabilisticAudit =>
        'Auditoria Probabilística',
    };
  }

  String _subtitleFor(EvidenceValidationStepKind kind) {
    return switch (kind) {
      EvidenceValidationStepKind.transfer =>
        'Transmitindo bytes ao armazenamento seguro.',
      EvidenceValidationStepKind.digitalIdentity =>
        'Gerando selo SHA-256 do arquivo original (INV-9).',
      EvidenceValidationStepKind.probabilisticAudit =>
        'Inspeção aleatória em 7 janelas de 128 KB contra conteúdo executável.',
    };
  }
}

class _StatusIcon extends StatelessWidget {
  final EvidenceValidationStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case EvidenceValidationStatus.pending:
        return const Icon(
          Icons.radio_button_unchecked,
          size: 18,
          color: VeraProbColors.textDisabled,
        );
      case EvidenceValidationStatus.running:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: VeraProbColors.primary,
          ),
        );
      case EvidenceValidationStatus.completed:
        return const Icon(
          Icons.check_circle,
          size: 18,
          color: VeraProbColors.success,
        );
      case EvidenceValidationStatus.failed:
        return const Icon(Icons.cancel, size: 18, color: VeraProbColors.error);
    }
  }
}

class _FailureBlock extends StatelessWidget {
  final InterpretedForensicError interpreted;
  const _FailureBlock({required this.interpreted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VeraProbSpacing.sm),
      decoration: BoxDecoration(
        color: VeraProbColors.error.withValues(alpha: 0.12),
        border: Border.all(color: VeraProbColors.error.withValues(alpha: 0.4)),
        borderRadius: VeraProbRadii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            interpreted.userMessage,
            style: const TextStyle(
              color: VeraProbColors.error,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            interpreted.suggestedAction,
            style: const TextStyle(
              color: VeraProbColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
