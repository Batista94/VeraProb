import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pactaflow/core/theme/app_theme.dart';
import 'package:pactaflow/domain/entities/operational_trip.dart';
import 'package:pactaflow/state/providers/fleet_providers.dart';
import 'package:pactaflow/presentation/shared/trip_status_theme.dart';
import 'package:pactaflow/application/projections/providers/command_center_filter_provider.dart';
import 'package:pactaflow/presentation/shared/widgets/status_badge.dart';
import 'package:pactaflow/dev/performance_metrics.dart';

/// Local sidebar state for search and sort (not global — UI-only).
final _sidebarSearchProvider = StateProvider<String>((ref) => '');
final _sidebarSortAscProvider = StateProvider<bool>((ref) => true);

/// Left sidebar in the Command Center showing all active trips.
///
/// Features:
/// - Incremental search by route/line name
/// - Sort by route name (A→Z / Z→A toggle)
/// - Active filter banner when KpiBar filter is active
/// - No duplicate filter chips (filters are in KpiBar only)
class TripSidebar extends ConsumerWidget {
  const TripSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(filteredTripsProvider);
    final selectedId = ref.watch(selectedTripIdProvider);
    final filterState = ref.watch(commandCenterFilterProvider);
    final statusFilter = filterState.selectedFleetStatusFilter;
    final searchQuery = ref.watch(_sidebarSearchProvider).toLowerCase();
    final sortAsc = ref.watch(_sidebarSortAscProvider);

    // Apply local search filter
    var displayTrips = trips.where((t) {
      if (searchQuery.isEmpty) return true;
      final routeName = (t.routeShortName ?? t.routeLongName ?? '')
          .toLowerCase();
      return routeName.contains(searchQuery);
    }).toList();

    // Apply local sort if user toggled it
    if (sortAsc) {
      displayTrips.sort(
        (a, b) => (a.routeShortName ?? '').compareTo(b.routeShortName ?? ''),
      );
    } else {
      displayTrips.sort(
        (a, b) => (b.routeShortName ?? '').compareTo(a.routeShortName ?? ''),
      );
    }

    return RebuildCounter(
      name: 'Sidebar',
      child: Container(
        width: 280,
        decoration: const BoxDecoration(
          color: PactaFlowColors.surface,
          border: Border(right: BorderSide(color: PactaFlowColors.border)),
        ),
        child: Column(
          children: [
            // Header
            _SidebarHeader(tripCount: displayTrips.length),

            const Divider(height: 1, color: PactaFlowColors.border),

            // Search + Sort controls
            _SearchSortBar(
              onSearchChanged: (query) {
                ref.read(_sidebarSearchProvider.notifier).state = query;
              },
              sortAsc: sortAsc,
              onSortToggle: () {
                ref.read(_sidebarSortAscProvider.notifier).state = !sortAsc;
              },
            ),

            const Divider(height: 1, color: PactaFlowColors.border),

            // Active filter indicator banner
            if (statusFilter != FleetStatusFilter.all)
              _ActiveFilterBanner(
                statusFilter: statusFilter,
                onClear: () {
                  ref
                      .read(commandCenterFilterProvider.notifier)
                      .setStatusFilter(FleetStatusFilter.all);
                },
              ),

            // Trip list
            Expanded(
              child: displayTrips.isEmpty
                  ? _EmptyState()
                  : ListView.separated(
                      itemCount: displayTrips.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: PactaFlowColors.border,
                      ),
                      itemBuilder: (context, index) {
                        final trip = displayTrips[index];
                        return _TripCard(
                          trip: trip,
                          isSelected: trip.id == selectedId,
                          onTap: () {
                            final isSelecting = trip.id != selectedId;
                            ref.read(selectedTripIdProvider.notifier).state =
                                isSelecting ? trip.id : null;

                            if (isSelecting) {
                              final positions = ref
                                  .read(normalizedStateProvider)
                                  .valueOrNull;
                              final vehicle = positions
                                  ?.where((v) => v.tripId == trip.id)
                                  .firstOrNull;
                              if (vehicle != null) {
                                ref
                                    .read(commandCenterFilterProvider.notifier)
                                    .setFollowVehicleId(vehicle.vehicleId);
                              }
                            } else {
                              ref
                                  .read(commandCenterFilterProvider.notifier)
                                  .setFollowVehicleId(null);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────
class _SidebarHeader extends StatelessWidget {
  final int tripCount;
  const _SidebarHeader({required this.tripCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Text(
            'VIAGENS ATIVAS',
            style: PactaFlowTypography.caption.copyWith(
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: PactaFlowColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$tripCount',
              style: PactaFlowTypography.caption.copyWith(
                color: PactaFlowColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search + Sort Bar ───────────────────────────────────
class _SearchSortBar extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final bool sortAsc;
  final VoidCallback onSortToggle;

  const _SearchSortBar({
    required this.onSearchChanged,
    required this.sortAsc,
    required this.onSortToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                onChanged: onSearchChanged,
                style: const TextStyle(
                  fontSize: 12,
                  color: PactaFlowColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar linha...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: PactaFlowColors.textDisabled,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    maxHeight: 30,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: PactaFlowColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: PactaFlowColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: PactaFlowColors.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  filled: true,
                  fillColor: PactaFlowColors.surface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Sort toggle
          InkWell(
            onTap: onSortToggle,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: PactaFlowColors.border),
              ),
              child: Icon(
                sortAsc ? Icons.sort_by_alpha : Icons.sort_by_alpha,
                size: 16,
                color: PactaFlowColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trip Card ───────────────────────────────────────────
class _TripCard extends StatelessWidget {
  final OperationalTrip trip;
  final bool isSelected;
  final VoidCallback onTap;

  const _TripCard({
    required this.trip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isSelected
            ? PactaFlowColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Route + Status
            Row(
              children: [
                // Route color dot
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: trip.status.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.routeDisplay,
                    style: PactaFlowTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusBadge(status: trip.status),
              ],
            ),
            const SizedBox(height: 4),
            // Details row
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  if (trip.vehiclePlate != null) ...[
                    Icon(
                      Icons.directions_bus,
                      size: 12,
                      color: PactaFlowColors.textDisabled,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      trip.vehiclePlate!,
                      style: PactaFlowTypography.caption,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (trip.driverName != null) ...[
                    Icon(
                      Icons.person,
                      size: 12,
                      color: PactaFlowColors.textDisabled,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        trip.driverName!,
                        style: PactaFlowTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Delay badge
                  if (trip.delaySeconds > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: PactaFlowColors.delayed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        trip.delayDisplay,
                        style: PactaFlowTypography.caption.copyWith(
                          color: PactaFlowColors.delayed,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ─────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_bus_outlined,
              size: 40,
              color: PactaFlowColors.textDisabled.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text('Nenhuma viagem ativa', style: PactaFlowTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ── Active Filter Banner ────────────────────────────────
class _ActiveFilterBanner extends StatelessWidget {
  final FleetStatusFilter statusFilter;
  final VoidCallback onClear;

  const _ActiveFilterBanner({
    required this.statusFilter,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final filterColor = _colorForFilter(statusFilter);
    final filterLabel = _labelForFilter(statusFilter);

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: filterColor.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: filterColor, width: 3),
          bottom: const BorderSide(color: PactaFlowColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 12, color: filterColor),
          const SizedBox(width: 6),
          Text(
            'Filtro: $filterLabel',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: filterColor,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 14,
                color: PactaFlowColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForFilter(FleetStatusFilter filter) {
    switch (filter) {
      case FleetStatusFilter.active:
        return PactaFlowColors.primary;
      case FleetStatusFilter.onTime:
        return PactaFlowColors.onTime;
      case FleetStatusFilter.delayed:
        return PactaFlowColors.delayed;
      case FleetStatusFilter.alerts:
        return PactaFlowColors.critical;
      case FleetStatusFilter.atStop:
        return PactaFlowColors.scheduled;
      case FleetStatusFilter.all:
        return PactaFlowColors.textSecondary;
    }
  }

  String _labelForFilter(FleetStatusFilter filter) {
    switch (filter) {
      case FleetStatusFilter.active:
        return 'Em Operação';
      case FleetStatusFilter.onTime:
        return 'No Horário';
      case FleetStatusFilter.delayed:
        return 'Atrasados';
      case FleetStatusFilter.alerts:
        return 'Alertas';
      case FleetStatusFilter.atStop:
        return 'No Ponto';
      case FleetStatusFilter.all:
        return 'Todos';
    }
  }
}
