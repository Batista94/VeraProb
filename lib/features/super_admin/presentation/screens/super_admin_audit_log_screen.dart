import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/super_admin/presentation/screens/widgets/audit_payload_diff_view.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

const _kSeverities = ['debug', 'info', 'warning', 'error', 'critical'];

/// System Audit Log screen for SuperAdmin.
///
/// Displays entries from `system_audit_log` with filters:
/// org dropdown, severity chips, date range.
class SuperAdminAuditLogScreen extends ConsumerStatefulWidget {
  const SuperAdminAuditLogScreen({super.key});

  @override
  ConsumerState<SuperAdminAuditLogScreen> createState() =>
      _SuperAdminAuditLogScreenState();
}

class _SuperAdminAuditLogScreenState
    extends ConsumerState<SuperAdminAuditLogScreen> {
  String? _selectedOrgId;
  String? _selectedSeverity;
  DateTimeRange? _dateRange;

  @override
  Widget build(BuildContext context) {
    final params = auditLogParams(
      organizationId: _selectedOrgId,
      severity: _selectedSeverity,
      fromDate: _dateRange?.start,
      toDate: _dateRange?.end,
    );

    final logsAsync = ref.watch(systemAuditLogProvider(params));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterBar(
          selectedSeverity: _selectedSeverity,
          dateRange: _dateRange,
          onSeverityChanged: (s) => setState(() => _selectedSeverity = s),
          onDateRangeChanged: (r) => setState(() => _dateRange = r),
          onClearFilters: () => setState(() {
            _selectedSeverity = null;
            _dateRange = null;
            _selectedOrgId = null;
          }),
        ),
        Expanded(
          child: switch (logsAsync) {
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
            AsyncError(:final error) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: VeraProbColors.error,
                  ),
                  const SizedBox(height: 12),
                  Text('Erro ao carregar logs: $error'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.invalidate(systemAuditLogProvider(params)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
            AsyncData(:final value) => _LogList(logs: value),
          },
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String? selectedSeverity;
  final DateTimeRange? dateRange;
  final ValueChanged<String?> onSeverityChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final VoidCallback onClearFilters;

  const _FilterBar({
    required this.selectedSeverity,
    required this.dateRange,
    required this.onSeverityChanged,
    required this.onDateRangeChanged,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text('Filtros:', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 12),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _kSeverities.map((s) {
                final isSelected = selectedSeverity == s;
                return FilterChip(
                  label: Text(s.toUpperCase()),
                  selected: isSelected,
                  selectedColor: _severityColor(s).withValues(alpha: 0.25),
                  onSelected: (_) => onSeverityChanged(isSelected ? null : s),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().toUtc().add(const Duration(days: 1)),
                initialDateRange: dateRange,
              );
              if (picked != null) onDateRangeChanged(picked);
            },
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              dateRange == null
                  ? 'Periodo'
                  : '${_fmtDate(dateRange!.start)} - ${_fmtDate(dateRange!.end)}',
            ),
          ),
          const SizedBox(width: 8),
          if (selectedSeverity != null || dateRange != null)
            TextButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Limpar'),
            ),
        ],
      ),
    );
  }

  Color _severityColor(String s) {
    switch (s) {
      case 'critical':
        return VeraProbColors.error;
      case 'error':
        return VeraProbColors.warning;
      case 'warning':
        return VeraProbColors.delayed;
      default:
        return VeraProbColors.info;
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _LogList extends StatelessWidget {
  final List<SystemAuditLogView> logs;

  const _LogList({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum evento encontrado para os filtros selecionados.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      itemCount: logs.length,
      separatorBuilder: (context, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final log = logs[i];
        return ListTile(
          leading: Icon(
            _severityIcon(log.severity),
            color: _severityColor(log.severity),
            size: 20,
          ),
          title: Row(
            children: [
              Expanded(child: Text(log.eventType)),
              _ActorIcon(
                actorType: log.actorType,
                impersonatorId: log.impersonatorId,
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(log.occurredAt.isNotEmpty ? log.occurredAt : '-'),
              if (log.reason != null && log.reason!.isNotEmpty)
                Text(
                  log.reason!,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: VeraProbColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          trailing: log.payload != null
              ? IconButton(
                  icon: const Icon(Icons.data_object, size: 18),
                  tooltip: 'Ver detalhes',
                  onPressed: () => _showPayload(
                    context,
                    log.payload!,
                    log.source,
                    log.actorType,
                    log.reason,
                  ),
                )
              : null,
        );
      },
    );
  }

  void _showPayload(
    BuildContext context,
    Map<String, dynamic> payload,
    String? source,
    String? actorType,
    String? reason,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Detalhes do Evento'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: AuditPayloadDiffView(
              payload: payload.cast<String, Object?>(),
              source: source,
              actorType: actorType,
              reason: reason,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  IconData _severityIcon(String s) {
    switch (s) {
      case 'critical':
        return Icons.emergency;
      case 'error':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _severityColor(String s) {
    switch (s) {
      case 'critical':
        return VeraProbColors.error;
      case 'error':
        return VeraProbColors.warning;
      case 'warning':
        return VeraProbColors.delayed;
      default:
        return VeraProbColors.info;
    }
  }
}

/// Actor type icon shown next to each audit event title.
///
/// SYSTEM: robot icon (automated action)
/// HUMAN: shield icon (super admin action)
/// IMPERSONATOR: manage_accounts icon (impersonation session)
class _ActorIcon extends StatelessWidget {
  final String? actorType;
  final String? impersonatorId;
  const _ActorIcon({this.actorType, this.impersonatorId});

  @override
  Widget build(BuildContext context) {
    switch (actorType) {
      case 'SYSTEM':
        return const Tooltip(
          message: 'Sistema',
          child: Icon(
            Icons.smart_toy_outlined,
            size: 14,
            color: VeraProbColors.textSecondary,
          ),
        );
      case 'IMPERSONATOR':
        return Tooltip(
          message: 'Impersonacao (${impersonatorId ?? "?"})',
          child: const Icon(
            Icons.manage_accounts,
            size: 14,
            color: VeraProbColors.warning,
          ),
        );
      case 'HUMAN':
        return const Tooltip(
          message: 'Admin',
          child: Icon(
            Icons.shield_outlined,
            size: 14,
            color: VeraProbColors.textPrimary,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
