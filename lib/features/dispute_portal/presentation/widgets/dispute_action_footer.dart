import 'package:flutter/material.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_submission_notifier.dart';
import 'package:veraprob/core/theme/app_theme.dart';

const TextStyle _kCancelTextStyle = TextStyle(
  fontSize: 13,
  color: VeraProbColors.textSecondary,
);

class DisputeActionFooter extends StatelessWidget {
  final PortalSubmissionState state;
  final ValueChanged<String> onJustificationChanged;
  final VoidCallback onSubmit;
  final VoidCallback onAcknowledge;

  const DisputeActionFooter({
    super.key,
    required this.state,
    required this.onJustificationChanged,
    required this.onSubmit,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy =
        state is PortalSubmissionHashing ||
        state is PortalSubmissionUploading ||
        state is PortalSubmissionRetrying;

    bool canSubmit = false;
    String currentJustification = '';

    if (state is PortalSubmissionStaging) {
      canSubmit = (state as PortalSubmissionStaging).canSubmit;
      currentJustification = (state as PortalSubmissionStaging).justification;
    } else if (state is PortalSubmissionError) {
      canSubmit = (state as PortalSubmissionError).recoverable.canSubmit;
      currentJustification =
          (state as PortalSubmissionError).recoverable.justification;
    }

    // TextController could be managed by parent or locally, but since justification
    // is in the notifier state, we rely on the parent to pass initial value or
    // we use a localized controller synced with the initial state.
    // To avoid cursor jumping issues with rebuilding TextFields, we let the parent
    // or internal state manage the controller if needed, but for simplicity here we assume
    // we just use a TextFormField with initialValue or a controller.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Justificativa da Contestação (Obrigatória)',
          style: VeraProbTypography.fieldLabel,
        ),
        const SizedBox(height: VeraProbSpacing.xs),
        TextFormField(
          initialValue: currentJustification,
          enabled: !isBusy,
          maxLines: 4,
          minLines: 3,
          maxLength: 4000,
          onChanged: onJustificationChanged,
          decoration: const InputDecoration(
            hintText:
                'Descreva detalhadamente o motivo da contestação (mín. 20 caracteres)...',
          ),
        ),
        const SizedBox(height: VeraProbSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isBusy
                    ? null
                    : () => _showAcknowledgeConfirmation(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VeraProbColors.textPrimary,
                  side: const BorderSide(color: VeraProbColors.neutral),
                ),
                child: const Text('De Acordo — Aceitar'),
              ),
            ),
            const SizedBox(width: VeraProbSpacing.md),
            Expanded(
              child: ElevatedButton(
                onPressed: (!canSubmit || isBusy) ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VeraProbColors.primary,
                  disabledBackgroundColor: VeraProbColors.neutral.withValues(
                    alpha: 0.5,
                  ),
                ),
                child: isBusy
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: VeraProbColors.background,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Processando...'),
                        ],
                      )
                    : const Text('Enviar Contestação'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAcknowledgeConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmar Aceite'),
          content: const Text(
            'Ao clicar em "Aceitar Infração", você concorda com os dados '
            'apresentados e abre mão do direito à contestação. '
            'Esta ação é irreversível.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar', style: _kCancelTextStyle),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onAcknowledge();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: VeraProbColors.neutral,
              ),
              child: const Text('Aceitar Infração'),
            ),
          ],
        );
      },
    );
  }
}
