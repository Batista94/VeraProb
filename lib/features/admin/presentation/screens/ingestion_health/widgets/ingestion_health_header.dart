import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/veraprob_header.dart';

/// Header for [IngestionHealthScreen].
///
/// Composes [VeraProbHeader] with:
/// - a back-button in [leading] (min 44px tap target)
/// - a polling status indicator in [actions]
///
/// [isDrillDown] switches the back-button tooltip between
/// "Voltar aos Alertas" (deep link from Command Center) and "Voltar".
class IngestionHealthHeader extends StatelessWidget {
  final AsyncValue<FleetHealthView> healthAsync;
  final VoidCallback onBack;
  final bool isDrillDown;

  const IngestionHealthHeader({
    super.key,
    required this.healthAsync,
    required this.onBack,
    this.isDrillDown = false,
  });

  @override
  Widget build(BuildContext context) {
    return VeraProbHeader(
      leading: SizedBox(
        // WCAG: 44px minimum tap target
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: isDrillDown ? 'Voltar aos Alertas' : 'Voltar',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: VeraProbColors.textPrimary),
          padding: EdgeInsets.zero,
        ),
      ),
      icon: Icons.monitor_heart_outlined,
      title: 'Monitor de Saúde da Ingestão',
      actions: [_PollStatusIndicator(healthAsync: healthAsync)],
    );
  }
}

class _PollStatusIndicator extends StatelessWidget {
  final AsyncValue<FleetHealthView> healthAsync;
  const _PollStatusIndicator({required this.healthAsync});

  @override
  Widget build(BuildContext context) {
    return healthAsync.when(
      data: (_) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: VeraProbColors.onTime,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Atualização: 60s',
            style: VeraProbTypography.kpiLabel.copyWith(fontSize: 10),
          ),
        ],
      ),
      loading: () => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: VeraProbColors.primary,
        ),
      ),
      error: (_, _) => const Icon(
        Icons.error_outline,
        color: VeraProbColors.critical,
        size: 16,
      ),
    );
  }
}
