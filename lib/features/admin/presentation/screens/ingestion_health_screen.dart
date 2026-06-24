import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/fleet_health_summary_bar.dart';
import 'package:veraprob/features/admin/presentation/widgets/vehicle_health_card.dart';
import 'package:veraprob/state/providers/fleet_health_providers.dart';

final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Ingestion Health Monitor — master-detail dashboard for fleet telemetry gaps.
///
/// **URL:** `/admin/hub/ingestion-health[?vehicleId=<uuid>]`
///
/// The optional `vehicleId` query parameter pre-selects a vehicle and opens
/// the detail panel (used for drill-down from `TELEMETRY_SILENT` /
/// `EVIDENCE_GAP` alerts in the Command Center).
///
/// INV-1: org-scoped via `currentOrganizationIdProvider`.
/// INV-16: 60s polling via `fleetHealthPollingProvider` (no Realtime on
///         `canonical_facts` — connection budget protection).
class IngestionHealthScreen extends ConsumerStatefulWidget {
  /// Pre-selected vehicle ID for drill-down navigation.
  final String? preselectedVehicleId;

  const IngestionHealthScreen({super.key, this.preselectedVehicleId});

  @override
  ConsumerState<IngestionHealthScreen> createState() =>
      _IngestionHealthScreenState();
}

class _IngestionHealthScreenState extends ConsumerState<IngestionHealthScreen> {
  @override
  void initState() {
    super.initState();
    // Apply drill-down preselection after first frame.
    if (widget.preselectedVehicleId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(selectedHealthVehicleIdProvider.notifier)
            .set(widget.preselectedVehicleId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FleetHealthView> healthAsync = ref.watch(
      fleetHealthPollingProvider,
    );
    final selectedId = ref.watch(selectedHealthVehicleIdProvider);

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              IconButton(
                tooltip: 'Voltar',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.adminHub),
                icon: const Icon(
                  Icons.arrow_back,
                  color: VeraProbColors.textPrimary,
                ),
              ),
              const SizedBox(width: VeraProbSpacing.xs),
              const Icon(
                Icons.monitor_heart_outlined,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              Flexible(
                child: Text(
                  'Monitor de Saúde da Ingestão',
                  style: VeraProbTypography.sectionTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              // Polling indicator
              healthAsync.when(
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
                error: (error, stack) => const Icon(
                  Icons.error_outline,
                  color: VeraProbColors.critical,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: VeraProbSpacing.md),

          // ── Content ──
          Expanded(
            child: healthAsync.when(
              data: (view) => _buildContent(view, selectedId),
              loading: () => const Center(
                child: CircularProgressIndicator(color: VeraProbColors.primary),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: VeraProbColors.critical,
                      size: 48,
                    ),
                    const SizedBox(height: VeraProbSpacing.sm),
                    Text(
                      'Erro ao carregar dados de saúde',
                      style: VeraProbTypography.bodyMedium.copyWith(
                        color: VeraProbColors.critical,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(FleetHealthView view, String? selectedId) {
    return Column(
      children: [
        // KPI Summary Bar
        FleetHealthSummaryBar(healthView: view),
        const SizedBox(height: VeraProbSpacing.md),

        // Master-Detail
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Master: Vehicle Grid ──
              Expanded(flex: 3, child: _buildVehicleList(view, selectedId)),

              // ── Detail Panel (shown when a vehicle is selected) ──
              if (selectedId != null) ...[
                const SizedBox(width: VeraProbSpacing.md),
                Expanded(flex: 2, child: _buildDetailPanel(view, selectedId)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleList(FleetHealthView view, String? selectedId) {
    if (view.vehicles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sensors_off_outlined,
              color: VeraProbColors.neutral.withValues(alpha: 0.5),
              size: 64,
            ),
            const SizedBox(height: VeraProbSpacing.md),
            Text(
              'Nenhum veículo ou dispositivo encontrado',
              style: VeraProbTypography.bodyMedium.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: VeraProbSpacing.xs),
            Text(
              'Cadastre veículos e configure provedores de telemetria',
              style: VeraProbTypography.kpiLabel,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: view.vehicles.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: VeraProbSpacing.xs),
      itemBuilder: (context, index) {
        final entry = view.vehicles[index];
        final entryId = entry.vehicleId ?? entry.deviceId ?? '';
        return VehicleHealthCard(
          entry: entry,
          isSelected: selectedId == entryId,
          onTap: () {
            ref
                .read(selectedHealthVehicleIdProvider.notifier)
                .set(selectedId == entryId ? null : entryId);
          },
        );
      },
    );
  }

  Widget _buildDetailPanel(FleetHealthView view, String selectedId) {
    final entry = view.vehicles.where((v) {
      final id = v.vehicleId ?? v.deviceId ?? '';
      return id == selectedId;
    }).firstOrNull;

    if (entry == null) {
      return Container(
        padding: VeraProbSpacing.sectionPadding,
        decoration: BoxDecoration(
          color: VeraProbColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VeraProbColors.border),
        ),
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

    final statusColor = _colorForStatus(entry.hardwareStatus);

    return Container(
      padding: VeraProbSpacing.sectionPadding,
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
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
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: VeraProbColors.textSecondary,
                  tooltip: 'Fechar',
                  onPressed: () {
                    ref
                        .read(selectedHealthVehicleIdProvider.notifier)
                        .set(null);
                  },
                ),
              ],
            ),
            if (entry.model != null) ...[
              const SizedBox(height: VeraProbSpacing.xs),
              Text(entry.model!, style: VeraProbTypography.kpiLabel),
            ],
            const SizedBox(height: VeraProbSpacing.md),
            const Divider(color: VeraProbColors.border, height: 1),
            const SizedBox(height: VeraProbSpacing.md),

            // Detail rows
            _DetailRow(label: 'Dispositivo', value: entry.deviceId ?? '—'),
            _DetailRow(
              label: 'Último Ping',
              value: entry.lastPingUtc != null
                  ? '${_dateFormat.format(entry.lastPingUtc!)} UTC'
                  : 'Nunca',
            ),
            _DetailRow(
              label: 'Gap',
              value: _formatGap(entry.gapSeconds),
              valueColor: statusColor,
            ),
            _DetailRow(
              label: 'Status',
              value: entry.hardwareStatus.label,
              valueColor: statusColor,
            ),
            const SizedBox(height: VeraProbSpacing.md),

            // Integrity score
            Text('Integridade do Sinal', style: VeraProbTypography.kpiLabel),
            const SizedBox(height: VeraProbSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (entry.integrityScoreBps / 10000.0).clamp(
                        0.0,
                        1.0,
                      ),
                      backgroundColor: VeraProbColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _colorForScore(entry.integrityScoreBps),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: VeraProbSpacing.sm),
                Text(
                  // Physical Metric - Double Required
                  '${(entry.integrityScoreBps / 100.0).toStringAsFixed(1)}%',
                  style: VeraProbTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _colorForScore(entry.integrityScoreBps),
                  ),
                ),
              ],
            ),
            const SizedBox(height: VeraProbSpacing.md),

            // Anomalies
            _DetailRow(
              label: 'Anomalias (24h)',
              value: '${entry.anomalyCount24h}',
              valueColor: entry.anomalyCount24h > 0
                  ? VeraProbColors.critical
                  : VeraProbColors.textSecondary,
            ),

            if (entry.isPhantom) ...[
              const SizedBox(height: VeraProbSpacing.md),
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

  static Color _colorForStatus(HardwareStatusView status) => switch (status) {
    HardwareStatusView.healthy => VeraProbColors.onTime,
    HardwareStatusView.delayed => VeraProbColors.delayed,
    HardwareStatusView.offline => VeraProbColors.critical,
    HardwareStatusView.neverSeen => VeraProbColors.neutral,
  };

  static Color _colorForScore(int bps) {
    if (bps >= 7000) return VeraProbColors.onTime;
    if (bps >= 4000) return VeraProbColors.delayed;
    return VeraProbColors.critical;
  }

  static String _formatGap(int seconds) {
    if (seconds >= 999999) return '—';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }
}

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
