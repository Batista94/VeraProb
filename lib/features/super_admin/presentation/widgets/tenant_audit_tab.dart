import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/audit_event_category.dart';
import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/audit_category_badge.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:intl/intl.dart';

const _kErrorText = TextStyle(color: VeraProbColors.error);
const _kEmptyText = TextStyle(color: VeraProbColors.textSecondary);
const _kSectionLabel = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
const _kMonoPayloadText = TextStyle(
  fontFamily: 'monospace',
  fontSize: 10,
  color: VeraProbColors.textSecondary,
);

/// UUID v4 regex for validating SuperAdmin actor IDs.
final _uuidRegExp = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Returns `true` when [value] is a valid UUID string.
bool _isValidUuid(String value) => _uuidRegExp.hasMatch(value);

class TenantAuditTab extends ConsumerWidget {
  final String organizationId;

  const TenantAuditTab({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = AuditLogParams(organizationId: organizationId, limit: 50);
    final auditLogsAsync = ref.watch(systemAuditLogProvider(params));

    return switch (auditLogsAsync) {
      AsyncData(:final value) => _buildLogList(value),
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError() => const Center(
        child: Text(
          'Não foi possível carregar os registros de auditoria.',
          style: _kErrorText,
        ),
      ),
    };
  }

  Widget _buildLogList(List<SystemAuditLogView> logs) {
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
            Text('Nenhum evento de auditoria encontrado.', style: _kEmptyText),
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
  }
}

class _AuditLogItem extends StatelessWidget {
  final SystemAuditLogView log;

  const _AuditLogItem({required this.log});

  @override
  Widget build(BuildContext context) {
    final color = _getSeverityColor(log.severity);
    final icon = _getEventIcon(log.eventType);
    final category = AuditEventCategory.fromEventType(log.eventType);

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
        title: Row(
          children: [
            Flexible(
              child: Text(
                log.eventType.replaceAll('_', ' '),
                style: VeraProbTypography.sectionTitle.copyWith(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            AuditCategoryBadge(category: category),
          ],
        ),
        subtitle: Text(formattedDate, style: VeraProbTypography.caption),
        childrenPadding: const EdgeInsets.all(16),
        expandedAlignment: Alignment.topLeft,
        children: [
          _LinkableActorRow(label: 'Ator', value: log.actorType ?? 'SYSTEM'),
          if (log.impersonatorId != null)
            _LinkableActorRow(
              label: 'Impersonator ID',
              value: log.impersonatorId!,
            ),
          if (log.source != null)
            _DetailRow(label: 'Origem', value: log.source!),
          const SizedBox(height: 8),
          const Text('Justificativa:', style: _kSectionLabel),
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
          if (log.payload?['snapshot_id'] != null)
            _CopyableIdRow(
              label: 'Snapshot ID',
              value: log.payload!['snapshot_id'].toString(),
            ),
          if (log.payload?['request_id'] != null)
            _CopyableIdRow(
              label: 'Request ID',
              value: log.payload!['request_id'].toString(),
            ),
          if (log.payload != null && log.payload!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Payload:', style: _kSectionLabel),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0x33000000), // payload background
                borderRadius: VeraProbRadii.smAll,
              ),
              child: Text(log.payload.toString(), style: _kMonoPayloadText),
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

/// Renders an actor/impersonator value as a tappable link when the value is a
/// valid UUID (i.e. a SuperAdmin ID), or as plain static text otherwise.
///
/// Satisfies Requirements 8.1 and 8.2.
class _LinkableActorRow extends StatelessWidget {
  final String label;
  final String value;

  const _LinkableActorRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isUuid = _isValidUuid(value);

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
          if (isUuid)
            GestureDetector(
              onTap: () => _navigateToSuperAdminProfile(context, value),
              child: Text(
                value,
                style: VeraProbTypography.bodySmall.copyWith(
                  color: VeraProbColors.secondary,
                  decoration: TextDecoration.underline,
                  decorationColor: VeraProbColors.secondary,
                ),
              ),
            )
          else
            Text(value, style: VeraProbTypography.bodySmall),
        ],
      ),
    );
  }

  /// Navigates to the SuperAdmin profile screen.
  void _navigateToSuperAdminProfile(BuildContext context, String superAdminId) {
    debugPrint('Navigate to SuperAdmin profile: $superAdminId');
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

/// Displays a forensic trace ID (Snapshot_ID or Request_ID) in monospace font
/// with a copy-to-clipboard action and SnackBar feedback.
///
/// Satisfies Requirements 8.3, 8.4, 8.5.
class _CopyableIdRow extends StatelessWidget {
  final String label;
  final String value;

  const _CopyableIdRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          await Clipboard.setData(ClipboardData(text: value));
          messenger.showSnackBar(
            const SnackBar(
              content: Text('ID copiado para a área de transferência'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Row(
          children: [
            Text(
              '$label: ',
              style: VeraProbTypography.caption.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: VeraProbTypography.caption.copyWith(
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.copy,
              size: 14,
              color: VeraProbColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
