import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/operational_trip.dart';
import '../../../../domain/enums/trip_status.dart';
import '../../../../state/providers/fleet_providers.dart';
import '../../../shared/widgets/status_badge.dart';

/// Left sidebar in the Command Center showing all active trips.
class TripSidebar extends ConsumerWidget {
  const TripSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(filteredTripsProvider);
    final selectedId = ref.watch(selectedTripIdProvider);
    final statusFilter = ref.watch(tripStatusFilterProvider);

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: BusFlowColors.surface,
        border: Border(right: BorderSide(color: BusFlowColors.border)),
      ),
      child: Column(
        children: [
          // Header + filter chips
          _SidebarHeader(
            tripCount: trips.length,
            statusFilter: statusFilter,
            onFilterChanged: (status) {
              ref.read(tripStatusFilterProvider.notifier).state = status;
            },
          ),

          const Divider(height: 1, color: BusFlowColors.border),

          // Trip list
          Expanded(
            child: trips.isEmpty
                ? _EmptyState()
                : ListView.separated(
                    itemCount: trips.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: BusFlowColors.border),
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      return _TripCard(
                        trip: trip,
                        isSelected: trip.id == selectedId,
                        onTap: () {
                          ref.read(selectedTripIdProvider.notifier).state =
                              trip.id == selectedId ? null : trip.id;
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final int tripCount;
  final TripStatus? statusFilter;
  final ValueChanged<TripStatus?> onFilterChanged;

  const _SidebarHeader({
    required this.tripCount,
    required this.statusFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'VIAGENS ATIVAS',
                style: BusFlowTypography.caption.copyWith(
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: BusFlowColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$tripCount',
                  style: BusFlowTypography.caption.copyWith(
                    color: BusFlowColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Filter chips
          Wrap(
            spacing: 4,
            children: [
              _FilterChip(
                label: 'Todos',
                isSelected: statusFilter == null,
                onTap: () => onFilterChanged(null),
              ),
              _FilterChip(
                label: 'Em Trânsito',
                color: BusFlowColors.onTime,
                isSelected: statusFilter == TripStatus.enRoute,
                onTap: () => onFilterChanged(
                  statusFilter == TripStatus.enRoute
                      ? null
                      : TripStatus.enRoute,
                ),
              ),
              _FilterChip(
                label: 'Atrasados',
                color: BusFlowColors.delayed,
                isSelected: statusFilter == TripStatus.delayed,
                onTap: () => onFilterChanged(
                  statusFilter == TripStatus.delayed
                      ? null
                      : TripStatus.delayed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? BusFlowColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? chipColor.withValues(alpha: 0.5)
                : BusFlowColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? chipColor : BusFlowColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

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
            ? BusFlowColors.primary.withValues(alpha: 0.08)
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
                    trip.routeShortName ?? trip.routeId,
                    style: BusFlowTypography.sectionTitle,
                  ),
                ),
                StatusBadge(status: trip.status, compact: true),
              ],
            ),
            const SizedBox(height: 4),
            // Driver + Vehicle
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 12,
                    color: BusFlowColors.textDisabled,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      trip.driverName ?? 'Sem motorista',
                      style: BusFlowTypography.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trip.vehiclePlate != null) ...[
                    Icon(
                      Icons.directions_bus_outlined,
                      size: 12,
                      color: BusFlowColors.textDisabled,
                    ),
                    const SizedBox(width: 4),
                    Text(trip.vehiclePlate!, style: BusFlowTypography.caption),
                  ],
                ],
              ),
            ),
            // Delay info
            if (trip.delaySeconds > 0)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: BusFlowColors.delayed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    trip.delayDisplay,
                    style: BusFlowTypography.caption.copyWith(
                      color: BusFlowColors.delayed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
              color: BusFlowColors.textDisabled.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text('Nenhuma viagem ativa', style: BusFlowTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}
