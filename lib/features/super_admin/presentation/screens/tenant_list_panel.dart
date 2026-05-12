import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/tenant_search_notifier.dart';
import 'package:veraprob/application/super_admin/tenant_status_filter.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_skeleton_tile.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Left panel: filterable list of tenant organizations.
///
/// Stage H: Split-view layout — this panel is 320px wide.
///
/// **INV-4 / Lens 2:** No domain types are imported here.
/// All filtering logic lives in [TenantSearchNotifier].
class TenantListPanel extends ConsumerStatefulWidget {
  final String? selectedOrgId;
  final ValueChanged<TenantHealthView> onOrgSelected;

  const TenantListPanel({
    super.key,
    this.selectedOrgId,
    required this.onOrgSelected,
  });

  @override
  ConsumerState<TenantListPanel> createState() => _TenantListPanelState();
}

class _TenantListPanelState extends ConsumerState<TenantListPanel> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTenants = ref.watch(tenantSearchProvider);
    final notifier = ref.read(tenantSearchProvider.notifier);
    final statusFilter = notifier.statusFilter;

    return SizedBox(
      width: 320,
      child: Column(
        children: [
          // ── Search bar ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: notifier.setQuery,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, CNPJ, ID...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          notifier.setQuery('');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // ── Status filter chips ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatusChip(
                    label: TenantStatusFilter.all.label,
                    selected: statusFilter == TenantStatusFilter.all,
                    onSelected: () =>
                        notifier.setStatusFilter(TenantStatusFilter.all),
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: TenantStatusFilter.active.label,
                    selected: statusFilter == TenantStatusFilter.active,
                    onSelected: () =>
                        notifier.setStatusFilter(TenantStatusFilter.active),
                    color: VeraProbColors.success,
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: TenantStatusFilter.suspended.label,
                    selected: statusFilter == TenantStatusFilter.suspended,
                    onSelected: () =>
                        notifier.setStatusFilter(TenantStatusFilter.suspended),
                    color: VeraProbColors.error,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Tenant list ────────────────────────────────────────────
          Expanded(child: _buildBody(asyncTenants)),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<TenantHealthView>> asyncTenants) {
    // Loading without previous data → skeleton tiles
    if (asyncTenants.isLoading && !asyncTenants.hasValue) {
      return const TenantSkeletonList();
    }

    // Error without data
    if (asyncTenants.hasError && !asyncTenants.hasValue) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Erro: ${asyncTenants.error}',
                style: const TextStyle(color: VeraProbColors.error),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(tenantHealthSnapshotProvider),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = asyncTenants.value!;
    final isDebouncing = ref.read(tenantSearchProvider.notifier).isDebouncing;

    if (filtered.isEmpty && !isDebouncing) {
      return const Center(
        child: Text(
          'Nenhuma organização encontrada.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
      );
    }

    // Debouncing with data → shimmer overlay
    if (isDebouncing) {
      return Stack(
        children: [
          _buildListView(filtered),
          Positioned.fill(
            key: const ValueKey('tenant-shimmer-overlay'),
            child: IgnorePointer(
              child: Container(
                color: VeraProbColors.background.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      );
    }

    return _buildListView(filtered);
  }

  Widget _buildListView(List<TenantHealthView> filtered) {
    return ListView.builder(
      key: const ValueKey('tenant-list-view'),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final t = filtered[index];
        final isSelected = t.id == widget.selectedOrgId;
        return _TenantListTile(
          tenant: t,
          isSelected: isSelected,
          onTap: () => widget.onOrgSelected(t),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? color;

  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: (color ?? VeraProbColors.secondary).withValues(alpha: 0.2),
      checkmarkColor: color ?? VeraProbColors.secondary,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TenantListTile extends StatelessWidget {
  final TenantHealthView tenant;
  final bool isSelected;
  final VoidCallback onTap;

  const _TenantListTile({
    required this.tenant,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = tenant.isActive ? 'Ativo' : 'Suspenso';
    return Semantics(
      label: '${tenant.name}, $statusLabel',
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: VeraProbColors.superAdminSurface.withValues(
          alpha: 0.08,
        ),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: tenant.isActive
              ? VeraProbColors.success.withValues(alpha: 0.15)
              : VeraProbColors.error.withValues(alpha: 0.15),
          child: Icon(
            tenant.isActive ? Icons.check : Icons.pause,
            size: 14,
            color: tenant.isActive
                ? VeraProbColors.success
                : VeraProbColors.error,
          ),
        ),
        title: Text(
          tenant.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          tenant.planType?.toUpperCase() ?? '—',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: tenant.hasCriticalAlerts
            ? const Icon(
                Icons.warning_amber,
                size: 16,
                color: VeraProbColors.error,
              )
            : const Icon(Icons.chevron_right, size: 16),
      ),
    );
  }
}
