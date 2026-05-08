import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class ReasonConfirmationDialog extends StatefulWidget {
  const ReasonConfirmationDialog({super.key});

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
      title: const Text('Justificativa'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Informe o motivo da alteracao de capabilities. '
              'Este registro sera gravado no log de auditoria.',
              style: TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo *',
                hintText: 'Minimo 10 caracteres',
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
