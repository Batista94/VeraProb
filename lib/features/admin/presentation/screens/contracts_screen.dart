import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/sla_audit/clone_contract_command.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/core/theme/app_theme.dart';

import 'create_contract_form.dart';
import 'contract_detail_screen.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedContractIdProvider);

    if (selectedId != null) {
      return ContractDetailScreen(contractId: selectedId);
    }

    return const _ContractListView();
  }
}

class _ContractListView extends ConsumerWidget {
  const _ContractListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(contractListProvider);
    final activeFilter = ref.watch(contractStatusFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestão de Contratos',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: VeraProbColors.textPrimary,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'Controle de vigência e conformidade SLA',
                    style: TextStyle(
                      color: VeraProbColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Novo Contrato'),
                onPressed: () async {
                  final newContractId = await CreateContractForm.show(
                    context,
                    ref,
                  );
                  if (newContractId != null) {
                    ref.invalidate(contractListProvider);
                    ref.read(selectedContractIdProvider.notifier).state =
                        newContractId;
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 32),

          Wrap(
            spacing: 12,
            children: [
              _FilterChip(
                label: 'Todos',
                selected: activeFilter == null,
                onSelected: (_) =>
                    ref.read(contractStatusFilterProvider.notifier).state =
                        null,
              ),
              _FilterChip(
                label: 'Rascunhos',
                color: VeraProbColors.neutral,
                selected: activeFilter == ContractStatusView.draft,
                onSelected: (_) =>
                    ref.read(contractStatusFilterProvider.notifier).state =
                        ContractStatusView.draft,
              ),
              _FilterChip(
                label: 'Aguardando Aceite',
                color: VeraProbColors.info,
                selected:
                    activeFilter ==
                    ContractStatusView.awaitingContractorAcceptance,
                onSelected: (_) =>
                    ref.read(contractStatusFilterProvider.notifier).state =
                        ContractStatusView.awaitingContractorAcceptance,
              ),
              _FilterChip(
                label: 'Ativos',
                color: VeraProbColors.success,
                selected: activeFilter == ContractStatusView.active,
                onSelected: (_) =>
                    ref.read(contractStatusFilterProvider.notifier).state =
                        ContractStatusView.active,
              ),
              _FilterChip(
                label: 'Encerrados',
                color: VeraProbColors.error,
                selected: activeFilter == ContractStatusView.closed,
                onSelected: (_) =>
                    ref.read(contractStatusFilterProvider.notifier).state =
                        ContractStatusView.closed,
              ),
            ],
          ),
          const SizedBox(height: 24),

          Expanded(
            child: contractsAsync.when(
              data: (contracts) => contracts.isEmpty
                  ? const _EmptyState()
                  : _ContractTable(contracts: contracts),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar contratos: $e',
                  style: const TextStyle(color: VeraProbColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractTable extends ConsumerWidget {
  final List<ContractSummaryView> contracts;
  const _ContractTable({required this.contracts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                columnSpacing: 24,
                headingRowColor: WidgetStateProperty.all(
                  VeraProbColors.surfaceElevated,
                ),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: VeraProbColors.textSecondary,
                  letterSpacing: 0.5,
                ),
                dataRowMaxHeight: 64,
                rows: contracts.map((c) => _buildRow(context, ref, c)).toList(),
                columns: const [
                  DataColumn(label: Text('CONTRATO')),
                  DataColumn(label: Text('CONTRATANTE')),
                  DataColumn(label: Text('VIGÊNCIA')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('SAÚDE SLA')),
                  DataColumn(label: Text('')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(
    BuildContext context,
    WidgetRef ref,
    ContractSummaryView c,
  ) {
    final vigencia =
        '${_dateFormat.format(c.validFromUtc.toLocal())} – ${_dateFormat.format(c.validUntilUtc.toLocal())}';

    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: VeraProbColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (c.activePlanVersion > 0)
                Text(
                  'Plano v${c.activePlanVersion}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: VeraProbColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        DataCell(
          Text(
            c.contractorName,
            style: const TextStyle(color: VeraProbColors.textPrimary),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        DataCell(
          Text(
            vigencia,
            style: const TextStyle(
              fontSize: 12,
              color: VeraProbColors.textSecondary,
            ),
          ),
        ),
        DataCell(_StatusChip(status: c.status)),
        DataCell(_SlaHealthBar(percentage: c.slaHealthPercentage)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: 'Clonar contrato',
                onPressed: () => _showCloneDialog(context, ref, c),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(selectedContractIdProvider.notifier).state = c.id;
                },
                icon: const Icon(Icons.chevron_right, size: 16),
                label: const Text('Gerenciar'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCloneDialog(
    BuildContext context,
    WidgetRef ref,
    ContractSummaryView c,
  ) async {
    final nameController = TextEditingController(text: '${c.name} (Cópia)');
    DateTime? validFrom;
    DateTime? validUntil;
    String? errorMsg;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickDate({required bool isFrom}) async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) {
              setDialogState(() {
                if (isFrom) {
                  validFrom = picked;
                } else {
                  validUntil = picked;
                }
                errorMsg = null;
              });
            }
          }

          return AlertDialog(
            title: const Text('Clonar Contrato'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do novo contrato',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            validFrom != null
                                ? _dateFormat.format(validFrom!)
                                : 'Início da vigência *',
                            style: TextStyle(
                              color: validFrom != null
                                  ? VeraProbColors.textPrimary
                                  : VeraProbColors.textSecondary,
                            ),
                          ),
                          onPressed: () => pickDate(isFrom: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            validUntil != null
                                ? _dateFormat.format(validUntil!)
                                : 'Fim da vigência *',
                            style: TextStyle(
                              color: validUntil != null
                                  ? VeraProbColors.textPrimary
                                  : VeraProbColors.textSecondary,
                            ),
                          ),
                          onPressed: () => pickDate(isFrom: false),
                        ),
                      ),
                    ],
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMsg!,
                      style: const TextStyle(
                        color: VeraProbColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) {
                          setDialogState(
                            () => errorMsg = 'Informe o nome do contrato.',
                          );
                          return;
                        }
                        if (validFrom == null || validUntil == null) {
                          setDialogState(
                            () => errorMsg = 'Defina as datas de início e fim.',
                          );
                          return;
                        }
                        if (!validUntil!.isAfter(validFrom!)) {
                          setDialogState(
                            () => errorMsg =
                                'A data de fim deve ser após o início.',
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        try {
                          final orgId = ref.read(currentOrganizationIdProvider);
                          if (orgId == null) {
                            throw const DomainException(
                              'Sessão expirada. Faça login novamente.',
                            );
                          }
                          final cmd = CloneContractCommand(
                            organizationId: orgId,
                            sourceContractId: c.id,
                            name: nameController.text.trim(),
                            contractorName: c.contractorName,
                            description: null,
                          );
                          final handler = ref.read(
                            cloneContractHandlerProvider,
                          );
                          final newContract = await handler.handle(
                            cmd,
                            validFromUtc: validFrom!.toUtc(),
                            validUntilUtc: validUntil!.toUtc(),
                          );
                          ref.invalidate(contractListProvider);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          ref.read(selectedContractIdProvider.notifier).state =
                              newContract.id;
                        } on DomainException catch (e) {
                          setDialogState(() {
                            errorMsg = e.message;
                            isSubmitting = false;
                          });
                        } catch (e) {
                          setDialogState(() {
                            errorMsg = 'Erro inesperado: $e';
                            isSubmitting = false;
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Clonar'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final ValueChanged<bool> onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? VeraProbColors.primary;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: effectiveColor.withValues(alpha: 0.2),
      checkmarkColor: effectiveColor,
      labelStyle: TextStyle(
        color: selected ? effectiveColor : VeraProbColors.textSecondary,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selected ? effectiveColor : VeraProbColors.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ContractStatusView status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ContractStatusView.draft => ('RASCUNHO', VeraProbColors.neutral),
      ContractStatusView.awaitingContractorAcceptance => (
        'AGUARDANDO ACEITE',
        VeraProbColors.info,
      ),
      ContractStatusView.active => ('ATIVO', VeraProbColors.success),
      ContractStatusView.closed => ('ENCERRADO', VeraProbColors.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SlaHealthBar extends StatelessWidget {
  final double percentage;
  const _SlaHealthBar({required this.percentage});

  @override
  Widget build(BuildContext context) {
    final pct = percentage.clamp(0.0, 100.0);
    final color = pct >= 90
        ? VeraProbColors.success
        : pct >= 70
        ? VeraProbColors.warning
        : VeraProbColors.error;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 4,
                  backgroundColor: VeraProbColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 80,
            color: VeraProbColors.border,
          ),
          SizedBox(height: 24),
          Text(
            'Nenhum contrato encontrado',
            style: TextStyle(
              color: VeraProbColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Crie um novo contrato para iniciar a auditoria de SLA.',
            style: TextStyle(color: VeraProbColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
