import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:busflow/application/sla_audit/projections/contract_summary_view.dart';
import 'package:busflow/domain/sla_audit/contract_status.dart';
import 'package:busflow/state/providers/contract_providers.dart';

import 'create_contract_form.dart';
import 'contract_detail_screen.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedContractIdProvider);

    // When a contract is selected, show its detail screen.
    if (selectedId != null) {
      return ContractDetailScreen(contractId: selectedId);
    }

    return const _ContractListView();
  }
}

// ── List View ─────────────────────────────────────────────────────────────────

class _ContractListView extends ConsumerWidget {
  const _ContractListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(contractListProvider);
    final activeFilter = ref.watch(contractStatusFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────
          Row(
            children: [
              const Text(
                'Contratos',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo Contrato'),
                onPressed: () async {
                  final created = await CreateContractForm.show(context, ref);
                  if (created == true) {
                    ref.invalidate(contractListProvider);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Status filter chips ──────────────────────────────
          Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                label: 'Todos',
                selected: activeFilter == null,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = null,
              ),
              _FilterChip(
                label: 'Rascunho',
                color: Colors.blueGrey,
                selected: activeFilter == ContractStatus.draft,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = ContractStatus.draft,
              ),
              _FilterChip(
                label: 'Ativo',
                color: Colors.green,
                selected: activeFilter == ContractStatus.active,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = ContractStatus.active,
              ),
              _FilterChip(
                label: 'Encerrado',
                color: Colors.red,
                selected: activeFilter == ContractStatus.closed,
                onSelected: (_) => ref
                    .read(contractStatusFilterProvider.notifier)
                    .state = ContractStatus.closed,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Contract table ───────────────────────────────────
          Expanded(
            child: contractsAsync.when(
              data: (contracts) => contracts.isEmpty
                  ? const _EmptyState()
                  : _ContractTable(contracts: contracts),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar contratos: $e',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _ContractTable extends ConsumerWidget {
  final List<ContractSummaryView> contracts;

  const _ContractTable({required this.contracts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          columns: const [
            DataColumn(label: Text('Contrato')),
            DataColumn(label: Text('Contratante')),
            DataColumn(label: Text('Vigência')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Plano')),
            DataColumn(label: Text('SETs')),
            DataColumn(label: Text('SLA %')),
            DataColumn(label: Text('')),
          ],
          rows: contracts.map((c) => _buildRow(context, ref, c)).toList(),
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
          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        DataCell(Text(c.contractorName)),
        DataCell(Text(vigencia, style: const TextStyle(fontSize: 12))),
        DataCell(_StatusChip(status: c.status)),
        DataCell(
          Text(
            c.activePlanVersion > 0 ? 'v${c.activePlanVersion}' : '—',
          ),
        ),
        DataCell(Text('${c.totalSetsInProgress} pendentes')),
        DataCell(_SlaHealthBar(percentage: c.slaHealthPercentage)),
        DataCell(
          TextButton(
            onPressed: () {
              ref.read(selectedContractIdProvider.notifier).state = c.id;
            },
            child: const Text('Detalhes'),
          ),
        ),
      ],
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

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
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: (color ?? Theme.of(context).colorScheme.primary)
          .withValues(alpha: 0.2),
      onSelected: onSelected,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ContractStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ContractStatus.draft => ('Rascunho', Colors.blueGrey),
      ContractStatus.active => ('Ativo', Colors.green),
      ContractStatus.closed => ('Encerrado', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
    final color = pct >= 80
        ? Colors.green
        : pct >= 50
            ? Colors.orange
            : Colors.red;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${pct.toStringAsFixed(0)}%',
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum contrato encontrado.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'Clique em "Novo Contrato" para começar.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
