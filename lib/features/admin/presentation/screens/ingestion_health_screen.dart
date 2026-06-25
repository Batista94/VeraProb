import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade_drawer.dart';
import 'package:veraprob/features/admin/presentation/widgets/fleet_health_summary_bar.dart';
import 'package:veraprob/features/admin/presentation/widgets/health_display_helpers.dart';
import 'package:veraprob/features/admin/presentation/widgets/vehicle_health_card.dart';
import 'package:veraprob/state/providers/fleet_health_providers.dart';

final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Ingestion Health Monitor — master-detail dashboard for fleet telemetry gaps.
///
/// **URL:** `/admin/hub/ingestion-health[?vehicleId=<uuid>]`
///
/// The optional `vehicleId` query param pre-selects a vehicle, scrolls it into
/// view, and opens the detail panel (drill-down from `TELEMETRY_SILENT` /
/// `EVIDENCE_GAP` alerts in the Command Center drawer).
///
/// INV-1: org-scoped via `currentOrganizationIdProvider`.
/// INV-16: 60s polling (no Realtime on `canonical_facts` — connection budget).
/// INV-22/INV-26: vehicleId validated against org fleet before acting.
class IngestionHealthScreen extends ConsumerStatefulWidget {
  final String? preselectedVehicleId;

  const IngestionHealthScreen({super.key, this.preselectedVehicleId});

  @override
  ConsumerState<IngestionHealthScreen> createState() =>
      _IngestionHealthScreenState();
}

class _IngestionHealthScreenState extends ConsumerState<IngestionHealthScreen> {
  final _scrollTrigger = ValueNotifier<String?>(null);
  String? _resolvedPreselectionId;
  bool _preselectionHandled = false;
  ProviderSubscription<String?>? _preselectionSub;
  ProviderSubscription<AsyncValue<FleetHealthView>>? _fleetSub;
  // Stored in initState so dispose() can call .set(null) without ref (Riverpod rule).
  late final SelectedHealthVehicleIdNotifier _selectionNotifier;

  @override
  void initState() {
    super.initState();
    _selectionNotifier = ref.read(selectedHealthVehicleIdProvider.notifier);
    if (widget.preselectedVehicleId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Capture before any async gap (Lesson 8).
        _listenForPreselection(ScaffoldMessenger.of(context));
      });
    }
  }

  @override
  void dispose() {
    _preselectionSub?.close();
    _fleetSub?.close();
    _scrollTrigger.dispose();
    _selectionNotifier.set(null);
    super.dispose();
  }

  void _listenForPreselection(ScaffoldMessengerState messenger) {
    // Immediate check: maybe fleet data already in cache.
    final immediate = ref.read(
      resolvedPreselectionProvider(widget.preselectedVehicleId),
    );
    if (immediate != null) {
      _resolvePreselection(immediate);
      return;
    }
    if (ref.read(fleetHealthPollingProvider).asData != null) {
      _showAbsentNotice(messenger);
      return;
    }

    // Data still loading: watch for id resolution (null → uuid).
    _preselectionSub = ref.listenManual(
      resolvedPreselectionProvider(widget.preselectedVehicleId),
      (_, id) {
        if (_preselectionHandled || id == null) return;
        _cancelPreselectionSubs();
        _resolvePreselection(id);
      },
    );

    // Also watch fleet load: if data arrives but id stays null, it's absent.
    _fleetSub = ref.listenManual(fleetHealthPollingProvider, (_, next) {
      if (_preselectionHandled || next.asData == null) return;
      final id = ref.read(
        resolvedPreselectionProvider(widget.preselectedVehicleId),
      );
      if (id != null) return; // _preselectionSub will handle this case.
      _cancelPreselectionSubs();
      if (mounted) _showAbsentNotice(messenger);
    });
  }

  void _cancelPreselectionSubs() {
    _preselectionHandled = true;
    _preselectionSub?.close();
    _preselectionSub = null;
    _fleetSub?.close();
    _fleetSub = null;
  }

  void _resolvePreselection(String id) {
    _preselectionHandled = true;
    _selectionNotifier.set(id);
    if (!mounted) return;
    setState(() => _resolvedPreselectionId = id);
    _scrollTrigger.value = id;
    // Clear after pulse duration so subsequent poll rebuilds don't re-pulse.
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _resolvedPreselectionId = null);
    });
  }

  void _showAbsentNotice(ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Este registro não está mais disponível no monitor.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onBack() {
    if (widget.preselectedVehicleId != null) {
      context.go(AppRoutes.adminHub);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(isAlertsDrawerOpenProvider.notifier).set(true);
      });
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.adminHub);
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthAsync = ref.watch(fleetHealthPollingProvider);
    final selectedId = ref.watch(selectedHealthVehicleIdProvider);

    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IngestionHealthHeader(healthAsync: healthAsync, onBack: _onBack),
          const SizedBox(height: VeraProbSpacing.md),
          Expanded(
            child: healthAsync.when(
              data: (view) => Column(
                children: [
                  FleetHealthSummaryBar(healthView: view),
                  const SizedBox(height: VeraProbSpacing.md),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _VehicleListPanel(
                            view: view,
                            selectedId: selectedId,
                            preselectedId: _resolvedPreselectionId,
                            scrollTrigger: _scrollTrigger,
                            onSelect: (id) => ref
                                .read(selectedHealthVehicleIdProvider.notifier)
                                .set(id),
                          ),
                        ),
                        if (selectedId != null) ...[
                          const SizedBox(width: VeraProbSpacing.md),
                          Expanded(
                            flex: 2,
                            child: _IngestionHealthDetailPanel(
                              view: view,
                              selectedId: selectedId,
                              onClose: () => ref
                                  .read(
                                    selectedHealthVehicleIdProvider.notifier,
                                  )
                                  .set(null),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              loading: () => const Center(
                child: CircularProgressIndicator(color: VeraProbColors.primary),
              ),
              error: (_, _) => Center(
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
}

class _IngestionHealthHeader extends StatelessWidget {
  final AsyncValue<FleetHealthView> healthAsync;
  final VoidCallback onBack;

  const _IngestionHealthHeader({
    required this.healthAsync,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Voltar',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: VeraProbColors.textPrimary),
        ),
        const SizedBox(width: VeraProbSpacing.xs),
        const Icon(Icons.monitor_heart_outlined, color: VeraProbColors.primary),
        const SizedBox(width: VeraProbSpacing.sm),
        Flexible(
          child: Text(
            'Monitor de Saúde da Ingestão',
            style: VeraProbTypography.sectionTitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
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
          error: (_, _) => const Icon(
            Icons.error_outline,
            color: VeraProbColors.critical,
            size: 16,
          ),
        ),
      ],
    );
  }
}

class _VehicleListPanel extends StatefulWidget {
  final FleetHealthView view;
  final String? selectedId;
  final String? preselectedId;
  final ValueNotifier<String?> scrollTrigger;
  final void Function(String? id) onSelect;

  const _VehicleListPanel({
    required this.view,
    required this.selectedId,
    required this.preselectedId,
    required this.scrollTrigger,
    required this.onSelect,
  });

  @override
  State<_VehicleListPanel> createState() => _VehicleListPanelState();
}

class _VehicleListPanelState extends State<_VehicleListPanel> {
  // Stride = card vertical padding (sm*2=16) + icon height (36) + separator (xs=4)
  static const double _kStride =
      VeraProbSpacing.sm * 2 + 36.0 + VeraProbSpacing.xs; // 56.0

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.scrollTrigger.addListener(_onScrollTrigger);
  }

  @override
  void dispose() {
    widget.scrollTrigger.removeListener(_onScrollTrigger);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollTrigger() {
    final targetId = widget.scrollTrigger.value;
    if (targetId == null || !_scrollController.hasClients) return;
    final index = widget.view.vehicles.indexWhere(
      (e) => (e.vehicleId ?? e.deviceId) == targetId,
    );
    if (index < 0) return;
    _scrollController.animateTo(
      (index * _kStride).clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.view.vehicles.isEmpty) {
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
      controller: _scrollController,
      itemCount: widget.view.vehicles.length,
      separatorBuilder: (_, _) => const SizedBox(height: VeraProbSpacing.xs),
      itemBuilder: (_, index) {
        final entry = widget.view.vehicles[index];
        final entryId = entry.vehicleId ?? entry.deviceId ?? '';
        return VehicleHealthCard(
          entry: entry,
          isSelected: widget.selectedId == entryId,
          isPreselected: widget.preselectedId == entryId,
          onTap: () =>
              widget.onSelect(widget.selectedId == entryId ? null : entryId),
        );
      },
    );
  }
}

class _IngestionHealthDetailPanel extends StatelessWidget {
  final FleetHealthView view;
  final String selectedId;
  final VoidCallback onClose;

  const _IngestionHealthDetailPanel({
    required this.view,
    required this.selectedId,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final entry = view.vehicles.firstWhereOrNull(
      (v) => (v.vehicleId ?? v.deviceId ?? '') == selectedId,
    );

    final decoration = BoxDecoration(
      color: VeraProbColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: VeraProbColors.border),
    );

    if (entry == null) {
      return Container(
        padding: VeraProbSpacing.sectionPadding,
        decoration: decoration,
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

    return Container(
      padding: VeraProbSpacing.sectionPadding,
      decoration: decoration,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  onPressed: onClose,
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
            const SizedBox(height: VeraProbSpacing.md),
            const Divider(color: VeraProbColors.border, height: 1),
            const SizedBox(height: VeraProbSpacing.md),
            _DetailRow(label: 'Dispositivo', value: entry.deviceId ?? '—'),
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
            const SizedBox(height: VeraProbSpacing.md),
            Text('Integridade do Sinal', style: VeraProbTypography.kpiLabel),
            const SizedBox(height: VeraProbSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      // Physical Metric - Double Required
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
                  // Physical Metric - Double Required
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
            const SizedBox(height: VeraProbSpacing.md),
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
