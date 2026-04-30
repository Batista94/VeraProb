import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:intl/intl.dart';

class TenantAuditTab extends ConsumerWidget {
  final String organizationId;

  const TenantAuditTab({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = AuditLogParams(organizationId: organizationId, limit: 50);
    final auditLogsAsync = ref.watch(systemAuditLogProvider(params));

    return auditLogsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history_outlined,
                  size: 48,
                  color: VeraProbColors.textDisabled,
                ),
                SizedBox(height: 16),
                Text(
                  'Nenhum evento de auditoria encontrado.',
                  style: TextStyle(color: VeraProbColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return _AuditLogItem(log: log);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          'Erro ao carregar logs: $err',
          style: const TextStyle(color: VeraProbColors.error),
        ),
      ),
    );
  }
}

class _AuditLogItem extends StatelessWidget {
  final SystemAuditLogView log;

  const _AuditLogItem({required this.log});

  @override
  Widget build(BuildContext context) {
    final color = _getSeverityColor(log.severity);
    final icon = _getEventIcon(log.eventType);

    // Format timestamp
    String formattedDate = 'Data desconhecida';
    try {
      final dt = DateTime.parse(log.occurredAt).toLocal();
      formattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          log.eventType.replaceAll('_', ' '),
          style: VeraProbTypography.sectionTitle.copyWith(fontSize: 13),
        ),
        subtitle: Text(formattedDate, style: VeraProbTypography.caption),
        childrenPadding: const EdgeInsets.all(16),
        expandedAlignment: Alignment.topLeft,
        children: [
          _DetailRow(label: 'Ator', value: log.actorType ?? 'SYSTEM'),
          if (log.impersonatorId != null)
            _DetailRow(label: 'Impersonator ID', value: log.impersonatorId!),
          if (log.source != null)
            _DetailRow(label: 'Origem', value: log.source!),
          const SizedBox(height: 8),
          const Text(
            'Justificativa:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: VeraProbColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              log.reason ?? 'Nenhuma justificativa fornecida.',
              style: VeraProbTypography.bodySmall.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          if (log.payload != null && log.payload!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Payload:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.payload.toString(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'error':
        return VeraProbColors.error;
      case 'warning':
        return VeraProbColors.warning;
      case 'info':
        return VeraProbColors.info;
      default:
        return VeraProbColors.neutral;
    }
  }

  IconData _getEventIcon(String type) {
    if (type.contains('ORG_CREATED')) return Icons.business_outlined;
    if (type.contains('ORG_ARCHIVED')) return Icons.archive_outlined;
    if (type.contains('ORG_UNARCHIVED')) return Icons.unarchive_outlined;
    if (type.contains('SECRET')) return Icons.key_outlined;
    if (type.contains('IMPERSONATION')) return Icons.theater_comedy_outlined;
    if (type.contains('QUOTA')) return Icons.assessment_outlined;
    return Icons.event_note_outlined;
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: VeraProbTypography.caption.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(value, style: VeraProbTypography.bodySmall),
        ],
      ),
    );
  }
}
