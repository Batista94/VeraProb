import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/contractor_providers.dart';
import '../../../../state/providers/auth_providers.dart';
import 'package:veraprob/application/sla_audit/projections/contractor_view.dart';
import '../../../../application/sla_audit/delete_contractor_command.dart';
import '../widgets/contractor_form_dialog.dart';

/// Screen for managing Contractors (CRUD).
class ContractorManagementScreen extends ConsumerStatefulWidget {
  const ContractorManagementScreen({super.key});

  @override
  ConsumerState<ContractorManagementScreen> createState() =>
      _ContractorManagementScreenState();
}

class _ContractorManagementScreenState
    extends ConsumerState<ContractorManagementScreen> {
  String _searchQuery = '';

  List<ContractorView> _filterContractors(List<ContractorView> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              (c.taxId?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
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
                  color: VeraProbColors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Gestão de Contratantes',
                  style: VeraProbTypography.sectionTitle,
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo Contratante'),
                  onPressed: () => _showForm(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre as empresas que contratam seus serviços para fins de auditoria e SLA.',
              style: VeraProbTypography.bodyMedium.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('contractor_search_field'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Buscar por nome ou CNPJ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: contractorsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Erro ao carregar contratantes: $e',
                    style: const TextStyle(color: VeraProbColors.error),
                  ),
                ),
                data: (all) {
                  final contractors = _filterContractors(all);
                  if (all.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.handshake_outlined,
                            size: 64,
                            color: VeraProbColors.textDisabled.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum contratante cadastrado ainda.',
                            style: VeraProbTypography.bodyMedium.copyWith(
                              color: VeraProbColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => _showForm(context),
                            child: const Text('Cadastrar Primeiro'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (contractors.isEmpty) {
                    return Center(
                      child: Text(
                        'Nenhum resultado para "$_searchQuery".',
                        style: VeraProbTypography.bodyMedium.copyWith(
                          color: VeraProbColors.textSecondary,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: contractors.length,
                    separatorBuilder: (context, index) =>
                        const Divider(color: VeraProbColors.border),
                    itemBuilder: (context, index) {
                      final contractor = contractors[index];
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: VeraProbColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.business,
                            color: VeraProbColors.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          contractor.name,
                          style: VeraProbTypography.kpiLabel,
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
                                  _showForm(context, existing: contractor),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: VeraProbColors.error,
                                size: 20,
                              ),
                              tooltip: 'Deletar',
                              onPressed: () =>
                                  _confirmDelete(context, contractor),
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

  void _showForm(BuildContext context, {ContractorView? existing}) {
    showContractorFormDialog(context, existing: existing).then((saved) {
      if (saved != null) ref.invalidate(contractorListProvider);
    });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ContractorView contractor,
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
            style: TextButton.styleFrom(foregroundColor: VeraProbColors.error),
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
              backgroundColor: VeraProbColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: VeraProbColors.error,
            ),
          );
        }
      }
    }
  }
}
