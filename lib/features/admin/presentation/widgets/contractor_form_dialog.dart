import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/sla_audit/contractor.dart';
import '../../../../application/sla_audit/save_contractor_command.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../state/providers/contractor_providers.dart';

Future<Contractor?> showContractorFormDialog(
  BuildContext context, {
  Contractor? existing,
  String? initialName,
}) {
  return showDialog<Contractor>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        ContractorFormDialog(existing: existing, initialName: initialName),
  );
}

class ContractorFormDialog extends ConsumerStatefulWidget {
  final Contractor? existing;
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
        constraints: const BoxConstraints(maxWidth: 500),
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
                    labelText: 'CNPJ / Tax ID',
                    hintText: '00.000.000/0001-00',
                  ),
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
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final callerRole = ref.read(currentUserRoleProvider);

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
            ),
          );

      if (mounted) Navigator.pop(context, newContractor);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
