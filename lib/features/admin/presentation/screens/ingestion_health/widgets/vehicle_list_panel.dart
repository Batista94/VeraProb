import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/health_display_helpers.dart';
import 'package:veraprob/features/admin/presentation/widgets/vehicle_health_card.dart';
import 'package:veraprob/presentation/shared/ui/veraprob_chip.dart';

/// Vehicle list panel with filter bar, column headers, and sorted/filtered list.
///
/// Filter state is local (client-side) per the plan's guidance:
/// "client-side sort/filter on [VehicleHealthEntry] is INV-13-safe in the widget layer."
/// Only promoted to a NotifierProvider when >3 filter dimensions.
class VehicleListPanel extends StatefulWidget {
  final FleetHealthView view;
  final String? selectedId;
  final String? preselectedId;
  final ValueNotifier<String?> scrollTrigger;
  final void Function(String? id) onSelect;

  const VehicleListPanel({
    super.key,
    required this.view,
    required this.selectedId,
    required this.preselectedId,
    required this.scrollTrigger,
    required this.onSelect,
  });

  @override
  State<VehicleListPanel> createState() => _VehicleListPanelState();
}

class _VehicleListPanelState extends State<VehicleListPanel> {
  // Stride = card vertical padding (sm*2=16) + icon height (36) + separator (xs=4)
  static const double _kStride =
      VeraProbSpacing.sm * 2 + 36.0 + VeraProbSpacing.xs; // 56.0

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  /// null = show all; otherwise restrict to this status
  HardwareStatusView? _statusFilter;
  bool _showPhantomOnly = false;
  _SortMode _sortMode = _SortMode.none;

  @override
  void initState() {
    super.initState();
    widget.scrollTrigger.addListener(_onScrollTrigger);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.scrollTrigger.removeListener(_onScrollTrigger);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScrollTrigger() {
    final targetId = widget.scrollTrigger.value;
    if (targetId == null || !_scrollController.hasClients) return;
    final index = _filteredVehicles.indexWhere(
      (e) => (e.vehicleId ?? e.deviceId) == targetId,
    );
    if (index < 0) return;
    _scrollController.animateTo(
      (index * _kStride).clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  List<VehicleHealthEntry> get _filteredVehicles {
    var vehicles = widget.view.vehicles;

    // Status chip filter
    if (_statusFilter != null) {
      vehicles = vehicles
          .where((e) => e.hardwareStatus == _statusFilter)
          .toList();
    }

    // Phantom toggle
    if (_showPhantomOnly) {
      vehicles = vehicles.where((e) => e.isPhantom).toList();
    }

    // Plate search
    final query = _searchController.text.trim().toUpperCase();
    if (query.isNotEmpty) {
      vehicles = vehicles
          .where((e) => e.displayPlate.toUpperCase().contains(query))
          .toList();
    }

    // Sort
    switch (_sortMode) {
      case _SortMode.gapAsc:
        vehicles.sort((a, b) => a.gapSeconds.compareTo(b.gapSeconds));
      case _SortMode.gapDesc:
        vehicles.sort((a, b) => b.gapSeconds.compareTo(a.gapSeconds));
      case _SortMode.scoreAsc:
        vehicles.sort(
          (a, b) => a.integrityScoreBps.compareTo(b.integrityScoreBps),
        );
      case _SortMode.scoreDesc:
        vehicles.sort(
          (a, b) => b.integrityScoreBps.compareTo(a.integrityScoreBps),
        );
      case _SortMode.none:
        break;
    }

    return vehicles;
  }

  void _toggleStatusFilter(HardwareStatusView status) {
    setState(() {
      _statusFilter = _statusFilter == status ? null : status;
      _showPhantomOnly = false;
    });
  }

  void _togglePhantom() {
    setState(() {
      _showPhantomOnly = !_showPhantomOnly;
      _statusFilter = null;
    });
  }

  void _cycleSortGap() {
    setState(() {
      _sortMode = switch (_sortMode) {
        _SortMode.gapDesc => _SortMode.gapAsc,
        _SortMode.gapAsc => _SortMode.none,
        _ => _SortMode.gapDesc,
      };
    });
  }

  void _cycleSortScore() {
    setState(() {
      _sortMode = switch (_sortMode) {
        _SortMode.scoreDesc => _SortMode.scoreAsc,
        _SortMode.scoreAsc => _SortMode.none,
        _ => _SortMode.scoreDesc,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredVehicles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterBar(
          searchController: _searchController,
          statusFilter: _statusFilter,
          showPhantomOnly: _showPhantomOnly,
          phantomCount: widget.view.phantomCount,
          onStatusTap: _toggleStatusFilter,
          onPhantomToggle: _togglePhantom,
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        _ListHeader(
          sortMode: _sortMode,
          onGapTap: _cycleSortGap,
          onScoreTap: _cycleSortScore,
        ),
        const SizedBox(height: VeraProbSpacing.xs),
        Expanded(child: _buildList(filtered)),
      ],
    );
  }

  Widget _buildList(List<VehicleHealthEntry> filtered) {
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
            const SizedBox(height: VeraProbSpacing.lg),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Cadastrar Veículo'),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'Nenhum resultado para os filtros aplicados',
          style: VeraProbTypography.bodyMedium.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: VeraProbSpacing.xs),
      itemBuilder: (_, index) {
        final entry = filtered[index];
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

// ── Filter Bar ────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final HardwareStatusView? statusFilter;
  final bool showPhantomOnly;
  final int phantomCount;
  final void Function(HardwareStatusView) onStatusTap;
  final VoidCallback onPhantomToggle;

  const _FilterBar({
    required this.searchController,
    required this.statusFilter,
    required this.showPhantomOnly,
    required this.phantomCount,
    required this.onStatusTap,
    required this.onPhantomToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status filter chips
        Wrap(
          spacing: VeraProbSpacing.xs,
          runSpacing: VeraProbSpacing.xs,
          children: [
            for (final status in HardwareStatusView.values)
              GestureDetector(
                onTap: () => onStatusTap(status),
                child: VeraProbChip(
                  label: status.label,
                  outline: statusFilter != status,
                  color: HealthDisplayHelpers.colorForStatus(status),
                ),
              ),
            if (phantomCount > 0)
              GestureDetector(
                onTap: onPhantomToggle,
                child: VeraProbChip(
                  label: 'Fantasma ($phantomCount)',
                  outline: !showPhantomOnly,
                  color: VeraProbColors.secondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        // Plate search
        SizedBox(
          height: 36,
          child: TextField(
            controller: searchController,
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar placa…',
              hintStyle: VeraProbTypography.bodySmall.copyWith(
                color: VeraProbColors.textSecondary,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: VeraProbColors.textSecondary,
              ),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      color: VeraProbColors.textSecondary,
                      onPressed: () => searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: VeraProbColors.surfaceElevated,
              border: const OutlineInputBorder(
                borderRadius: VeraProbRadii.mdAll,
                borderSide: BorderSide(color: VeraProbColors.border),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: VeraProbRadii.mdAll,
                borderSide: BorderSide(color: VeraProbColors.border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: VeraProbRadii.mdAll,
                borderSide: BorderSide(color: VeraProbColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Column Label Header ────────────────────────────────────────

class _ListHeader extends StatelessWidget {
  final _SortMode sortMode;
  final VoidCallback onGapTap;
  final VoidCallback onScoreTap;

  const _ListHeader({
    required this.sortMode,
    required this.onGapTap,
    required this.onScoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VeraProbSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text('PLACA', style: VeraProbTypography.kpiLabel),
          ),
          Expanded(
            flex: 2,
            child: Text('STATUS', style: VeraProbTypography.kpiLabel),
          ),
          Expanded(
            flex: 2,
            child: _SortableLabel(
              label: 'GAP',
              active:
                  sortMode == _SortMode.gapAsc || sortMode == _SortMode.gapDesc,
              ascending: sortMode == _SortMode.gapAsc,
              onTap: onGapTap,
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortableLabel(
              label: 'SCORE',
              active:
                  sortMode == _SortMode.scoreAsc ||
                  sortMode == _SortMode.scoreDesc,
              ascending: sortMode == _SortMode.scoreAsc,
              onTap: onScoreTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortableLabel extends StatelessWidget {
  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  const _SortableLabel({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: VeraProbTypography.kpiLabel.copyWith(
              color: active ? VeraProbColors.primary : null,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 2),
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: VeraProbColors.primary,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sort Mode ─────────────────────────────────────────────────

enum _SortMode { none, gapAsc, gapDesc, scoreAsc, scoreDesc }
