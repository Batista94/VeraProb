import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/contractor_providers.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../domain/sla_audit/contractor.dart';
import '../../../../application/sla_audit/save_contractor_command.dart';
import '../../../../application/sla_audit/delete_contractor_command.dart';

/// Screen for managing Contractors (CRUD).
class ContractorManagementScreen extends ConsumerWidget {
  const ContractorManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractorsAsync = ref.watch(contractorListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.handshake_outlined,
                  size: 28,
                  color: PactaFlowColors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Gestão de Contratantes',
                  style: PactaFlowTypography.sectionTitle,
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo Contratante'),
                  onPressed: () => _showForm(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre as empresas que contratam seus serviços para fins de auditoria e SLA.',
              style: PactaFlowTypography.bodyMedium.copyWith(
                color: PactaFlowColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: contractorsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Erro ao carregar contratantes: $e',
                    style: const TextStyle(color: PactaFlowColors.error),
                  ),
                ),
                data: (contractors) {
                  if (contractors.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.handshake_outlined,
                            size: 64,
                            color: PactaFlowColors.textDisabled.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum contratante cadastrado ainda.',
                            style: PactaFlowTypography.bodyMedium.copyWith(
                              color: PactaFlowColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => _showForm(context, ref),
                            child: const Text('Cadastrar Primeiro'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: contractors.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: PactaFlowColors.border),
                    itemBuilder: (context, index) {
                      final contractor = contractors[index];
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: PactaFlowColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.business,
                            color: PactaFlowColors.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          contractor.name,
                          style: PactaFlowTypography.kpiLabel,
                        ),
                        subtitle: Text(
                          '${contractor.contactName} · ${contractor.primaryEmail}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Editar',
                              onPressed: () =>
                                  _showForm(context, ref, existing: contractor),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: PactaFlowColors.error,
                                size: 20,
                              ),
                              tooltip: 'Deletar',
                              onPressed: () =>
                                  _confirmDelete(context, ref, contractor),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, {Contractor? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ContractorFormDialog(existing: existing),
    ).then((saved) {
      if (saved == true) ref.invalidate(contractorListProvider);
    });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Contractor contractor,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Contratante'),
        content: Text(
          'Deseja realmente deletar o contratante "${contractor.name}"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: PactaFlowColors.error),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final orgId = ref.read(currentOrganizationIdProvider);
        final callerRole = ref.read(currentUserRoleProvider);

        await ref
            .read(deleteContractorHandlerProvider)
            .handle(
              DeleteContractorCommand(
                organizationId: orgId!,
                callerRole: callerRole,
                contractorId: contractor.id,
              ),
            );
        ref.invalidate(contractorListProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contratante removido.'),
              backgroundColor: PactaFlowColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: PactaFlowColors.error,
            ),
          );
        }
      }
    }
  }
}

class _ContractorFormDialog extends ConsumerStatefulWidget {
  final Contractor? existing;
  const _ContractorFormDialog({this.existing});

  @override
  ConsumerState<_ContractorFormDialog> createState() =>
      _ContractorFormDialogState();
}

class _ContractorFormDialogState extends ConsumerState<_ContractorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _taxIdController;
  late final TextEditingController _emailController;
  late final TextEditingController _contactController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
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
                  style: PactaFlowTypography.sectionTitle,
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

      await ref
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

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: PactaFlowColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
