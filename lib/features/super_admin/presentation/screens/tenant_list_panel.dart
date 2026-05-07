import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/super_admin/application/tenant_health_view.dart';
import 'package:veraprob/features/super_admin/application/tenant_status_filter.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Left panel: filterable list of tenant organizations.
///
/// Stage H: Split-view layout — this panel is 320px wide.
///
/// **INV-4 / Lens 2:** No domain types are imported here.
/// - Status filtering uses [TenantStatusFilter] (application layer) instead of
///   [OrgStatus] (domain). The enum's [TenantStatusFilter.matches] method
///   evaluates the primitive [TenantHealthView.isActive] flag, so no domain
///   enum comparison is needed in the presentation layer.
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

  /// Active filter. Defaults to [TenantStatusFilter.all].
  TenantStatusFilter _statusFilter = TenantStatusFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TenantHealthView> _filter(List<TenantHealthView> all) {
    var filtered = all;

    // Status filter — delegated to TenantStatusFilter.matches() so no OrgStatus
    // comparison is needed here.
    if (_statusFilter != TenantStatusFilter.all) {
      filtered = filtered
          .where((t) => _statusFilter.matches(isActive: t.isActive))
          .toList();
    }

    // Search filter
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((t) {
        return t.name.toLowerCase().contains(query) ||
            (t.legalName?.toLowerCase().contains(query) ?? false) ||
            t.id.toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(tenantHealthSnapshotProvider);

    return SizedBox(
      width: 320,
      child: Column(
        children: [
          // ── Search bar ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
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
                          setState(() {});
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
                    selected: _statusFilter == TenantStatusFilter.all,
                    onSelected: () =>
                        setState(() => _statusFilter = TenantStatusFilter.all),
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: TenantStatusFilter.active.label,
                    selected: _statusFilter == TenantStatusFilter.active,
                    onSelected: () => setState(
                      () => _statusFilter = TenantStatusFilter.active,
                    ),
                    color: VeraProbColors.success,
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: TenantStatusFilter.suspended.label,
                    selected: _statusFilter == TenantStatusFilter.suspended,
                    onSelected: () => setState(
                      () => _statusFilter = TenantStatusFilter.suspended,
                    ),
                    color: VeraProbColors.error,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Tenant list ────────────────────────────────────────────
          Expanded(
            child: tenantsAsync.when(
              data: (tenants) {
                final filtered = _filter(tenants);
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhuma organização encontrada.',
                      style: TextStyle(color: VeraProbColors.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
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
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro: $e',
                  style: const TextStyle(color: VeraProbColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
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
    return ListTile(
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
    );
  }
}
