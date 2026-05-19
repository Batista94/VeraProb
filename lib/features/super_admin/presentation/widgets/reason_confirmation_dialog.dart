import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class ReasonConfirmationDialog extends StatefulWidget {
  final String title;
  final String promptMessage;

  const ReasonConfirmationDialog({
    super.key,
    this.title = 'Justificativa',
    this.promptMessage =
        'Informe o motivo da alteração. '
        'Este registro será gravado no log de auditoria.',
  });

  @override
  State<ReasonConfirmationDialog> createState() =>
      _ReasonConfirmationDialogState();
}

class _ReasonConfirmationDialogState extends State<ReasonConfirmationDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _isValid => _reasonCtrl.text.trim().length >= 10;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.promptMessage,
              style: const TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo *',
                hintText: 'Mínimo 10 caracteres',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_reasonCtrl.text.trim())
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
