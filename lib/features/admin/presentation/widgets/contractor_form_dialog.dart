import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/presentation/shared/formatters/cnpj_input_formatter.dart';
import 'package:veraprob/shared/utils/cnpj_validator.dart';
import 'package:veraprob/application/sla_audit/projections/contractor_view.dart';
import 'package:veraprob/application/sla_audit/save_contractor_command.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';

Future<ContractorView?> showContractorFormDialog(
  BuildContext context, {
  ContractorView? existing,
  String? initialName,
}) {
  return showDialog<ContractorView>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        ContractorFormDialog(existing: existing, initialName: initialName),
  );
}

class ContractorFormDialog extends ConsumerStatefulWidget {
  final ContractorView? existing;
  final String? initialName;

  const ContractorFormDialog({super.key, this.existing, this.initialName});

  @override
  ConsumerState<ContractorFormDialog> createState() =>
      _ContractorFormDialogState();
}

class _ContractorFormDialogState extends ConsumerState<ContractorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _taxIdController;
  late final TextEditingController _emailController;
  late final TextEditingController _contactController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?.name ?? widget.initialName ?? '',
    );
    _taxIdController = TextEditingController(
      text: widget.existing?.taxId ?? '',
    );
    _emailController = TextEditingController(
      text: widget.existing?.primaryEmail ?? '',
    );
    _contactController = TextEditingController(
      text: widget.existing?.contactName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _taxIdController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.92).clamp(
            300.0,
            540.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Editar Contratante' : 'Novo Contratante',
                  style: VeraProbTypography.sectionTitle,
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: VeraProbColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: VeraProbColors.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: VeraProbColors.error,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _errorMessage!,
                            style: VeraProbTypography.bodyMedium.copyWith(
                              color: VeraProbColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome da Empresa *',
                    hintText: 'Ex: Vale S.A.',
                  ),
                  validator: (v) => v?.isEmpty ?? true ? 'Obrigatório' : null,
                  autofocus: !isEdit,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _taxIdController,
                  decoration: const InputDecoration(
                    labelText: 'CNPJ / Tax ID *',
                    hintText: '00.000.000/0001-00',
                  ),
                  inputFormatters: [CnpjInputFormatter()],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório';
                    final digits = v.replaceAll(RegExp(r'\D'), '');
                    if (digits.length != 14) return 'CNPJ incompleto';
                    if (!CnpjValidator.isValid(digits)) return 'CNPJ inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contactController,
                  decoration: const InputDecoration(
                    labelText: 'Pessoa de Contato *',
                    hintText: 'Ex: João Silva',
                  ),
                  validator: (v) => v?.isEmpty ?? true ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Primário *',
                    hintText: 'contato@empresa.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v?.isEmpty ?? true ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Salvar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    // Synchronous field write — visible to any concurrent CanvasKit event
    // before setState schedules a rebuild. This closes the double-fire window
    // where PointerUp + synthetic click both pass the _isSaving check.
    if (_isSaving) return;
    _isSaving = true;
    _errorMessage = null;

    if (!(_formKey.currentState?.validate() ?? false)) {
      _isSaving = false;
      return;
    }

    // Capture context-dependent refs before first await (Lesson #8).
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {});
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final callerRole = ref.read(currentUserRoleProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final newContractor = await ref
          .read(saveContractorHandlerProvider)
          .handle(
            SaveContractorCommand(
              organizationId: orgId!,
              callerRole: callerRole,
              id: widget.existing?.id,
              name: _nameController.text.trim(),
              taxId: _taxIdController.text.trim().isEmpty
                  ? null
                  : _taxIdController.text.trim(),
              primaryEmail: _emailController.text.trim(),
              contactName: _contactController.text.trim(),
              sessionId: sessionId,
            ),
          );

      if (mounted) navigator.pop(ContractorView.fromDomain(newContractor));
    } catch (e) {
      if (mounted) {
        final msg = e is IntegrityException
            ? e.message
            : 'Erro ao salvar. Tente novamente.';
        _errorMessage = msg;
        messenger.showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: VeraProbColors.error),
        );
      }
    } finally {
      _isSaving = false;
      if (mounted) setState(() {});
    }
  }
}
