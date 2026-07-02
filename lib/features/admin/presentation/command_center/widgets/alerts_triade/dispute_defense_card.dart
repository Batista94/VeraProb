import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade/alert_card_atoms.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade/alerts_drawer_state.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';

/// Triage card for a `DISPUTE_DEFENSE_SUBMITTED` alert. Metadata only (no raw
/// testimony — INV-3/9): plate, driver, fine at risk, and a single CTA that
/// drops the auditor straight into the disputed lane of the Tribunal.
class DisputeDefenseCard extends ConsumerWidget {
  final OperationalAlert alert;

  const DisputeDefenseCard({super.key, required this.alert});

  static String _formatBrl(int cents) {
    final s = (cents / 100).toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
      buf.write(intPart[i]);
    }
    return 'R\$ $buf,${parts[1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = alert.context;
    final plate = (ctx['vehicle_plate'] as String?) ?? alert.entityId;
    final driver = ctx['driver_name'] as String?;
    final fineCents = switch (ctx['fine_amount_cents']) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
    final isFile = (ctx['defense_type'] as String?) == 'file';
    final fileName = ctx['filename'] as String?;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: VeraProbColors.delayed.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AlertSeverityBadge(
                label: 'CONTESTAÇÃO',
                color: VeraProbColors.delayed,
              ),
              const Spacer(),
              Text(
                formatAlertTimeAgo(alert.triggeredAtUtc),
                style: alertTimestampStyle(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Text(
                  plate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VeraProbTypography.dataValue.copyWith(fontSize: 13),
                ),
              ),
              if (driver != null && driver.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '· $driver',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VeraProbTypography.caption,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Multa em risco: ${_formatBrl(fineCents)}',
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                isFile ? Icons.attachment_rounded : Icons.notes_rounded,
                size: 13,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  isFile ? 'Anexo: ${fileName ?? 'arquivo'}' : 'Defesa textual',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VeraProbTypography.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: AlertActionButton(
              label: 'IR PARA DISPUTA →',
              icon: Icons.gavel_rounded,
              color: VeraProbColors.delayed,
              onPressed: () {
                ref
                    .read(auditorQueueFilterProvider.notifier)
                    .setFilter(AuditorQueueFilter.disputed);
                ref.read(isAlertsDrawerOpenProvider.notifier).set(false);
                Navigator.of(context).pop();
                context.go(AdminNav.auditorQueue.path);
              },
            ),
          ),
        ],
      ),
    );
  }
}
