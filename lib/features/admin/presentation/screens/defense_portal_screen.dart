import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/justification_providers.dart';
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
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar justificativas: $e',
                  style: const TextStyle(color: VeraProbColors.error),
                ),
              ),
              data: (rows) {
                final filtered = _applyFilters(rows);
                if (filtered.isEmpty) return const _EmptyState();
                return _JustificationTable(rows: filtered);
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> rows) {
    var result = rows;
    if (_filterStatus != null) {
      result = result
          .where((r) => r['status'] == _filterStatus!.dbValue)
          .toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where(
            (r) =>
                (r['contract_id'] as String? ?? '').toLowerCase().contains(q) ||
                (r['set_id'] as String? ?? '').toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends ConsumerStatefulWidget {
  final AsyncValue<List<Map<String, dynamic>>> listAsync;
  const _Header({required this.listAsync});

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  @override
  Widget build(BuildContext context) {
    final pendingCount = widget.listAsync.maybeWhen(
      data: (rows) => rows
          .where((r) => r['status'] == JustificationStatus.pending.dbValue)
          .length,
      orElse: () => 0,
    );

    return Row(
      children: [
        const Icon(Icons.shield_outlined, color: VeraProbColors.primary),
        const SizedBox(width: 12),
        Text('Portal Defesa', style: VeraProbTypography.sectionTitle),
        const SizedBox(width: 12),
        if (pendingCount > 0)
          Container(
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
        const Spacer(),
        FilledButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const JustificationSubmissionForm(),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Nova Justificativa'),
          style: FilledButton.styleFrom(
            backgroundColor: VeraProbColors.primary,
            foregroundColor: Colors.black,
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
  final List<Map<String, dynamic>> rows;
  const _JustificationTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
    );
  }

  DataRow _buildRow(BuildContext context, Map<String, dynamic> row) {
    final status = JustificationStatus.fromDb(row['status'] as String);
    final createdAt = DateTime.tryParse(
      row['created_at_utc'] as String? ?? '',
    )?.toLocal();
    final dateStr = createdAt != null
        ? '${createdAt.day.toString().padLeft(2, '0')}/'
              '${createdAt.month.toString().padLeft(2, '0')} '
              '${createdAt.hour.toString().padLeft(2, '0')}:'
              '${createdAt.minute.toString().padLeft(2, '0')}'
        : '-';

    final categoryRaw = (row['category'] as String? ?? '').toLowerCase();
    final categoryLabel = _categoryLabel(categoryRaw);

    return DataRow(
      onSelectChanged: (_) => showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fechar',
        barrierColor: Colors.black54,
        pageBuilder: (ctx, anim, secAnim) =>
            JustificationDetailDrawer(row: row),
      ),
      cells: [
        DataCell(
          Text(
            (row['contract_id'] as String? ?? '-').substring(
              0,
              (row['contract_id'] as String? ?? '-').length > 8
                  ? 8
                  : (row['contract_id'] as String? ?? '-').length,
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: VeraProbColors.textSecondary,
            ),
          ),
        ),
        DataCell(
          Text(
            row['set_id'] as String? ?? '-',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        DataCell(Text(categoryLabel, style: const TextStyle(fontSize: 13))),
        DataCell(Text(dateStr, style: const TextStyle(fontSize: 13))),
        DataCell(JustificationStatusBadge(status: status)),
      ],
    );
  }

  String _categoryLabel(String raw) {
    return switch (raw) {
      'mechanical' => 'Mecânico',
      'force_majeure' => 'Força Maior',
      'traffic' => 'Trânsito',
      'route_deviation' => 'Desvio de Rota',
      'communication' => 'Comunicação',
      _ => 'Outro',
    };
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
