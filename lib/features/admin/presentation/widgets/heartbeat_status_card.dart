import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/heartbeat_monitor_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/heartbeat_monitor_providers.dart';

/// Read-only OCC widget displaying the fleet's heartbeat health summary.
///
/// Shows three counters: Normal / Network Issue / Device Tamper.
/// A yellow badge appears when [unknownCount] > 0.
///
/// INV-23: This widget is read-only — no mutations.
/// INV-1: organizationId scopes all queries.
class HeartbeatStatusCard extends ConsumerWidget {
  final String organizationId;

  const HeartbeatStatusCard({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorAsync = ref.watch(heartbeatMonitorProvider(organizationId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.monitor_heart_outlined,
                  size: 20,
                  color: VeraProbColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Integridade de Sinal',
                  style: VeraProbTypography.kpiLabel,
                ),
              ],
            ),
            const SizedBox(height: 16),
            monitorAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(
                'Erro ao carregar: $e',
                style: const TextStyle(color: VeraProbColors.error),
              ),
              data: (view) => _HeartbeatSummary(view: view),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartbeatSummary extends StatelessWidget {
  final HeartbeatMonitorView view;

  const _HeartbeatSummary({required this.view});

  @override
  Widget build(BuildContext context) {
    if (view.totalCount == 0) {
      return Text(
        'Nenhum dispositivo rastreado.',
        style: VeraProbTypography.bodyMedium.copyWith(
          color: VeraProbColors.textSecondary,
        ),
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _Counter(
          label: 'Normal',
          count: view.normalCount,
          color: VeraProbColors.success,
          icon: Icons.check_circle_outline,
        ),
        _Counter(
          label: 'Rede',
          count: view.networkIssueCount,
          color: VeraProbColors.warning,
          icon: Icons.wifi_off_outlined,
        ),
        _Counter(
          label: 'Sabotagem',
          count: view.tamperCount,
          color: VeraProbColors.error,
          icon: Icons.gpp_bad_outlined,
        ),
        if (view.unknownCount > 0)
          _Counter(
            label: 'Indefinido',
            count: view.unknownCount,
            color: VeraProbColors.warning,
            icon: Icons.help_outline,
          ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _Counter({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: VeraProbTypography.bodyMedium.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Extension for display-friendly classification label in PT-BR.
extension HeartbeatClassificationLabel on HeartbeatClassification {
  String get label => switch (this) {
    HeartbeatClassification.normal => 'Normal',
    HeartbeatClassification.deviceTamper => 'Sabotagem',
    HeartbeatClassification.networkIssue => 'Falha de Rede',
    HeartbeatClassification.unknown => 'Indefinido',
  };

  Color get statusColor => switch (this) {
    HeartbeatClassification.normal => VeraProbColors.success,
    HeartbeatClassification.deviceTamper => VeraProbColors.error,
    HeartbeatClassification.networkIssue => VeraProbColors.warning,
    HeartbeatClassification.unknown => VeraProbColors.warning,
  };
}
