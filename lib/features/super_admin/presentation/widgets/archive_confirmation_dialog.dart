import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Modal dialog for archiving an organization.
///
/// Enforces CIA Availability (non-dismissible barrier),
/// CIA Integrity (min 10-char reason), and A11y (autofocus + semantics).
class ArchiveConfirmationDialog extends StatefulWidget {
  const ArchiveConfirmationDialog({super.key});

  /// Canonical entry point. Enforces [barrierDismissible: false] to guarantee
  /// CIA-Availability (user MUST make a conscious decision).
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ArchiveConfirmationDialog(),
    );
  }

  @override
  State<ArchiveConfirmationDialog> createState() =>
      _ArchiveConfirmationDialogState();
}

class _ArchiveConfirmationDialogState extends State<ArchiveConfirmationDialog> {
  final _reasonCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(
            Icons.archive_outlined,
            color: VeraProbColors.error,
            size: 20,
            semanticLabel: 'Ícone de arquivamento',
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Arquivar Organização',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta ação irá arquivar a organização. Todos os segredos de API '
                'serão revogados imediatamente. A organização não poderá mais '
                'receber telemetria ou gerar novos contratos.',
                style: TextStyle(
                  fontSize: 13,
                  color: VeraProbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  hintText: 'Mínimo 10 caracteres',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'Motivo obrigatório.';
                  if (val.length < 10) return 'Mínimo 10 caracteres.';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: VeraProbColors.error),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_reasonCtrl.text.trim());
            }
          },
          child: const Text('Confirmar Arquivamento'),
        ),
      ],
    );
  }
}
