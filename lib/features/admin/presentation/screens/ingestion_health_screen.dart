import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade_drawer.dart';
import 'package:veraprob/features/admin/presentation/screens/ingestion_health/widgets/ingestion_health_detail_panel.dart';
import 'package:veraprob/features/admin/presentation/screens/ingestion_health/widgets/ingestion_health_header.dart';
import 'package:veraprob/features/admin/presentation/screens/ingestion_health/widgets/vehicle_list_panel.dart';
import 'package:veraprob/features/admin/presentation/widgets/fleet_health_summary_bar.dart';
import 'package:veraprob/presentation/shared/ui/async_value_widget.dart';
import 'package:veraprob/presentation/shared/ui/skeleton_list_loader.dart';
import 'package:veraprob/state/providers/fleet_health_providers.dart';

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
  Timer? _pulseClearTimer;
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
    _pulseClearTimer?.cancel();
    _preselectionSub?.close();
    _fleetSub?.close();
    _scrollTrigger.dispose();
    Future.microtask(() {
      try {
        _selectionNotifier.set(null);
      } catch (_) {}
    });
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
    _pulseClearTimer?.cancel();
    _pulseClearTimer = Timer(const Duration(milliseconds: 1600), () {
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

    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Padding(
        padding: const EdgeInsets.all(VeraProbSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IngestionHealthHeader(
              healthAsync: healthAsync,
              onBack: _onBack,
              isDrillDown: widget.preselectedVehicleId != null,
            ),
            const SizedBox(height: VeraProbSpacing.md),
            Expanded(
              child: AsyncValueWidget<FleetHealthView>(
                asyncValue: healthAsync,
                loading: () => const SkeletonListLoader(itemCount: 6),
                error: (err, _) => Center(
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
                        'Falha ao carregar dados de telemetria',
                        style: VeraProbTypography.bodyMedium.copyWith(
                          color: VeraProbColors.critical,
                        ),
                      ),
                    ],
                  ),
                ),
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
                            child: VehicleListPanel(
                              view: view,
                              selectedId: selectedId,
                              preselectedId: _resolvedPreselectionId,
                              scrollTrigger: _scrollTrigger,
                              onSelect: (id) => ref
                                  .read(
                                    selectedHealthVehicleIdProvider.notifier,
                                  )
                                  .set(id),
                            ),
                          ),
                          if (selectedId != null) ...[
                            const SizedBox(width: VeraProbSpacing.md),
                            Expanded(
                              flex: 2,
                              child: IngestionHealthDetailPanel(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
