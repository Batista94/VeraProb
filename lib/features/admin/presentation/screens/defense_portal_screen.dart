import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/sla_audit/justification/justification_summary.dart';
import 'package:veraprob/state/providers/justification_providers.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'justification_detail_drawer.dart';
import 'justification_submission_form.dart';
import 'widgets/justification_status_badge.dart';

/// Defense Portal — operator/admin review queue for contractor justifications.
///
/// Lists all [contractor_justifications] for the organisation via Supabase
/// Realtime. Filter chips narrow by status. Row tap opens
/// [JustificationDetailDrawer] for approve/reject actions (INV-24).
class DefensePortalScreen extends ConsumerStatefulWidget {
  const DefensePortalScreen({super.key});

  @override
  ConsumerState<DefensePortalScreen> createState() =>
      _DefensePortalScreenState();
}

class _DefensePortalScreenState extends ConsumerState<DefensePortalScreen> {
  JustificationStatus? _filterStatus;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(justificationListStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(listAsync: listAsync),
          const SizedBox(height: 16),
          _FilterBar(
            selected: _filterStatus,
            onChanged: (s) => setState(() => _filterStatus = s),
            searchController: _searchController,
            onSearch: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AsyncValueWidget(
              asyncValue: listAsync,
              loading: () => const SkeletonListLoader(),
              data: (value) {
                final filtered = _applyFilters(value);
                if (filtered.isEmpty) return const _EmptyState();
                return _JustificationTable(rows: filtered);
              },
            ),
          ),
        ],
      ),
    );
  }

  List<JustificationSummary> _applyFilters(List<JustificationSummary> rows) {
    var result = rows;
    if (_filterStatus != null) {
      result = result.where((j) => j.status == _filterStatus).toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where(
            (j) =>
                (j.contractId ?? '').toLowerCase().contains(q) ||
                (j.setId ?? '').toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends ConsumerStatefulWidget {
  final AsyncValue<List<JustificationSummary>> listAsync;
  const _Header({required this.listAsync});

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  @override
  Widget build(BuildContext context) {
    final pendingCount = switch (widget.listAsync) {
      AsyncData(:final value) => value.where((j) => j.isPending).length,
      AsyncError() => 0,
      AsyncLoading() => 0,
    };

    return VeraProbHeader(
      icon: Icons.shield_outlined,
      title: 'Portal Defesa',
      actions: [
        if (pendingCount > 0)
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$pendingCount pendente${pendingCount > 1 ? 's' : ''}',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.warning,
              ),
            ),
          ),
        FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const JustificationSubmissionForm(),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Nova Justificativa'),
          // ACCENT-FILL-CONTRAST: dark fg on fill.
          style: FilledButton.styleFrom(
            backgroundColor: VeraProbColors.primary,
            foregroundColor: VeraProbColors.background,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }
}

// ── Filter Bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final JustificationStatus? selected;
  final ValueChanged<JustificationStatus?> onChanged;
  final TextEditingController searchController;
  final VoidCallback onSearch;

  const _FilterBar({
    required this.selected,
    required this.onChanged,
    required this.searchController,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(null, 'Todos'),
        const SizedBox(width: 8),
        _chip(JustificationStatus.pending, 'Pendentes'),
        const SizedBox(width: 8),
        _chip(JustificationStatus.approved, 'Aprovadas'),
        const SizedBox(width: 8),
        _chip(JustificationStatus.rejected, 'Rejeitadas'),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: searchController,
              onChanged: (_) => onSearch(),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por contrato ou SET ID...',
                prefixIcon: const Icon(Icons.search, size: 16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: VeraProbColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: VeraProbColors.border),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(JustificationStatus? value, String label) {
    final isSelected = selected == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => onChanged(value),
      selectedColor: VeraProbColors.primary.withValues(alpha: 0.2),
      checkmarkColor: VeraProbColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _JustificationTable extends StatelessWidget {
  final List<JustificationSummary> rows;
  const _JustificationTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return PanelContainer(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: DataTable(
          headingTextStyle: VeraProbTypography.caption.copyWith(
            color: VeraProbColors.textSecondary,
            letterSpacing: 1.1,
          ),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 48,
          columns: const [
            DataColumn(label: Text('CONTRATO')),
            DataColumn(label: Text('SET ID')),
            DataColumn(label: Text('CATEGORIA')),
            DataColumn(label: Text('ENVIADO EM')),
            DataColumn(label: Text('STATUS')),
          ],
          rows: rows.map((r) => _buildRow(context, r)).toList(),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, JustificationSummary row) {
    final createdAt = row.createdAtUtc?.toLocal();
    final dateStr = createdAt != null
        ? '${createdAt.day.toString().padLeft(2, '0')}/'
              '${createdAt.month.toString().padLeft(2, '0')} '
              '${createdAt.hour.toString().padLeft(2, '0')}:'
              '${createdAt.minute.toString().padLeft(2, '0')}'
        : '-';

    final contractId = row.contractId ?? '-';

    return DataRow(
      onSelectChanged: (_) => showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fechar',
        barrierColor: Colors.black54,
        pageBuilder: (ctx, anim, secAnim) =>
            JustificationDetailDrawer(summary: row),
      ),
      cells: [
        DataCell(
          Text(
            contractId.substring(
              0,
              contractId.length > 8 ? 8 : contractId.length,
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: VeraProbColors.textSecondary,
            ),
          ),
        ),
        DataCell(Text(row.setId ?? '-', style: const TextStyle(fontSize: 13))),
        DataCell(Text(row.categoryLabel, style: const TextStyle(fontSize: 13))),
        DataCell(Text(dateStr, style: const TextStyle(fontSize: 13))),
        DataCell(JustificationStatusBadge(status: row.status)),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 56,
            color: VeraProbColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma justificativa encontrada',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nenhuma contestação foi submetida para este período.',
            style: TextStyle(color: VeraProbColors.textDisabled),
          ),
        ],
      ),
    );
  }
}
