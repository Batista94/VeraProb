import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/health_display_helpers.dart';
import 'package:veraprob/presentation/shared/ui/panel_container.dart';
import 'package:veraprob/presentation/shared/ui/sparkline_widget.dart';

final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Detail panel for the Ingestion Health Monitor.
///
/// Renders vehicle details grouped into semantic sections:
/// Identificação / Telemetria / Integridade / Alertas.
/// Wraps in [PanelContainer] for consistent chrome.
class IngestionHealthDetailPanel extends StatelessWidget {
  final FleetHealthView view;
  final String selectedId;
  final VoidCallback onClose;

  const IngestionHealthDetailPanel({
    super.key,
    required this.view,
    required this.selectedId,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final entry = view.vehicles.firstWhereOrNull(
      (v) => (v.vehicleId ?? v.deviceId ?? '') == selectedId,
    );

    if (entry == null) {
      return PanelContainer(
        child: Center(
          child: Text(
            'Veículo não encontrado',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final statusColor = HealthDisplayHelpers.colorForStatus(
      entry.hardwareStatus,
    );

    return PanelContainer(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: VeraProbSpacing.sectionPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel title row
            Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: VeraProbSpacing.sm),
                Expanded(
                  child: Text(
                    entry.displayPlate,
                    style: VeraProbTypography.sectionTitle.copyWith(
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // WCAG: ≥44px close target
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: VeraProbColors.textSecondary,
                    tooltip: 'Fechar',
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            if (entry.model != null) ...[
              const SizedBox(height: VeraProbSpacing.xs),
              Tooltip(
                message: entry.model!,
                child: Text(
                  entry.model!,
                  style: VeraProbTypography.kpiLabel,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],

            // ── Identificação ─────────────────────────────────
            const _SectionHeader('Identificação'),
            _DetailRow(label: 'Dispositivo', value: entry.deviceId ?? '—'),
            _DetailRow(
              label: 'Tipo',
              value: entry.isPhantom ? 'Fantasma' : 'Registrado',
              valueColor: entry.isPhantom
                  ? VeraProbColors.secondary
                  : VeraProbColors.onTime,
            ),

            // ── Telemetria ────────────────────────────────────
            const _SectionHeader('Telemetria'),
            _DetailRow(
              label: 'Último Ping',
              value: entry.lastPingUtc != null
                  ? '${_dateFormat.format(entry.lastPingUtc!)} UTC'
                  : 'Nunca',
            ),
            _DetailRow(
              label: 'Gap',
              value: HealthDisplayHelpers.formatGap(entry.gapSeconds),
              valueColor: statusColor,
            ),
            _DetailRow(
              label: 'Status',
              value: entry.hardwareStatus.label,
              valueColor: statusColor,
            ),

            // ── Integridade ───────────────────────────────────
            const _SectionHeader('Integridade'),
            Text('Pontuação do Sinal', style: VeraProbTypography.kpiLabel),
            const SizedBox(height: VeraProbSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      // Physical metric — double required for Flutter progress API.
                      value: (entry.integrityScoreBps / 10000.0).clamp(
                        0.0,
                        1.0,
                      ),
                      backgroundColor: VeraProbColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        HealthDisplayHelpers.colorForScore(
                          entry.integrityScoreBps,
                        ),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: VeraProbSpacing.sm),
                Text(
                  // Physical metric — double required for percentage display.
                  '${(entry.integrityScoreBps / 100.0).toStringAsFixed(1)}%',
                  style: VeraProbTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: HealthDisplayHelpers.colorForScore(
                      entry.integrityScoreBps,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            // Signal-history sparkline (shows the integrity bar as a trend)
            SparklineWidget(
              values: [entry.integrityScoreBps],
              color: HealthDisplayHelpers.colorForScore(
                entry.integrityScoreBps,
              ),
              height: 36,
            ),

            // ── Alertas ───────────────────────────────────────
            const _SectionHeader('Alertas'),
            _DetailRow(
              label: 'Anomalias (24h)',
              value: '${entry.anomalyCount24h}',
              valueColor: entry.anomalyCount24h > 0
                  ? VeraProbColors.critical
                  : VeraProbColors.textSecondary,
            ),
            if (entry.isPhantom) ...[
              const SizedBox(height: VeraProbSpacing.sm),
              Container(
                padding: VeraProbSpacing.cardPadding,
                decoration: BoxDecoration(
                  color: VeraProbColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: VeraProbColors.secondary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sensors_off_outlined,
                      color: VeraProbColors.secondary,
                      size: 16,
                    ),
                    const SizedBox(width: VeraProbSpacing.sm),
                    Expanded(
                      child: Text(
                        'Dispositivo fantasma — transmitindo sem veículo '
                        'cadastrado. Chip M2M gerando custo cego.',
                        style: VeraProbTypography.kpiLabel.copyWith(
                          color: VeraProbColors.secondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section Header ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: VeraProbSpacing.md,
        bottom: VeraProbSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: VeraProbTypography.kpiLabel.copyWith(
              color: VeraProbColors.primary,
              fontSize: 10,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: VeraProbSpacing.xs),
          const Divider(color: VeraProbColors.border, height: 1),
        ],
      ),
    );
  }
}

// ── Detail Row ──────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VeraProbSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(label, style: VeraProbTypography.kpiLabel)),
          Text(
            value,
            style: VeraProbTypography.bodyMedium.copyWith(
              color: valueColor ?? VeraProbColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
