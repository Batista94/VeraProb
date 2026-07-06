import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/providers/vehicles_provider.dart';
import 'package:veraprob/features/admin/presentation/resources/tabs/vehicle_form_drawer.dart';
import 'package:veraprob/core/theme/app_theme.dart';

const TextStyle _kBtnLabel = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
);
const TextStyle _kChipText = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

class VehiclesTab extends ConsumerStatefulWidget {
  const VehiclesTab({super.key});

  @override
  ConsumerState<VehiclesTab> createState() => _VehiclesTabState();
}

class _VehiclesTabState extends ConsumerState<VehiclesTab> {
  bool _isDrawerOpen = false;
  String? _highlightedId;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _highlight(String id) {
    setState(() => _highlightedId = id);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredAsync = ref.watch(filteredVehiclesProvider);
    final userRole = ref.watch(currentUserRoleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(VeraProbSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, colorScheme, userRole),
              const SizedBox(height: VeraProbSpacing.lg),
              _buildSearchBar(),
              const SizedBox(height: 20),
              Expanded(
                child: switch (filteredAsync) {
                  AsyncData(:final value) =>
                    value.isEmpty
                        ? _buildEmptyState()
                        : _buildTable(context, value, colorScheme, userRole),
                  AsyncLoading() => const SkeletonListLoader(),
                  AsyncError(:final error) => _buildAsyncError(error),
                },
              ),
            ],
          ),
        ),
        if (_isDrawerOpen) ...[
          GestureDetector(
            onTap: () {},
            child: Container(color: const Color(0x4D000000)), // drawer scrim
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: VehicleFormDrawer(
              onClose: () => setState(() => _isDrawerOpen = false),
              onVehicleAdded: (id) {
                setState(() => _isDrawerOpen = false);
                _highlight(id);
                ref.invalidate(vehiclesListProvider);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    UserRole userRole,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: VeraProbRadii.lgAll,
          ),
          child: Icon(
            Icons.directions_bus,
            size: 28,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: VeraProbSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Frota de Veículos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: VeraProbSpacing.xs),
              Text(
                'Cadastro de veículos operacionais vinculados à organização.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: VeraProbSpacing.md),
        if (userRole.hasPermission(UserRole.admin))
          FilledButton.icon(
            onPressed: () => setState(() => _isDrawerOpen = true),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Cadastrar veículo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: _kBtnLabel,
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      width: 400,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por placa ou modelo...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(vehiclesSearchQueryProvider.notifier).set('');
                  },
                )
              : null,
          isDense: true,
        ),
        onChanged: (value) {
          ref.read(vehiclesSearchQueryProvider.notifier).set(value);
          setState(() {});
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return const EmptyState(
      icon: Icons.directions_bus_outlined,
      title: 'Nenhum veículo cadastrado ainda.',
      description: 'Clique em "Cadastrar veículo" para começar.',
    );
  }

  Widget _buildAsyncError(Object error) {
    LoggerService().error('Falha ao carregar veículos', error: error);
    return const EmptyState(
      icon: Icons.error_outline,
      title: 'Não foi possível carregar os veículos agora.',
      description: 'Tente novamente mais tarde.',
    );
  }

  Widget _buildTable(
    BuildContext context,
    List<Vehicle> vehicles,
    ColorScheme colorScheme,
    UserRole userRole,
  ) {
    return Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: VeraProbColors.border)),
            ),
            child: Row(
              children: [
                _headerCell('PLACA', flex: 2),
                _headerCell('MODELO', flex: 2),
                _headerCell('CAPACIDADE', flex: 1),
                const SizedBox(
                  width: 110,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: VeraProbColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 80),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: vehicles.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: VeraProbColors.border),
              itemBuilder: (context, index) {
                final vehicle = vehicles[index];
                return _VehicleRow(
                  vehicle: vehicle,
                  isHighlighted: _highlightedId == vehicle.id,
                  onDelete: userRole.hasPermission(UserRole.admin)
                      ? () => _confirmDelete(context, vehicle)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: VeraProbColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Vehicle vehicle) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text('Deseja excluir o veículo ${vehicle.plate} da frota?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref
            .read(vehicleAssetRepositoryProvider)
            .deleteVehicle(vehicle.id);
        ref.invalidate(vehiclesListProvider);
        messenger.showSnackBar(
          const SnackBar(content: Text('Veículo removido com sucesso.')),
        );
      } catch (e, stack) {
        LoggerService().error(
          'Falha ao remover veículo',
          error: e,
          stackTrace: stack,
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível remover o veículo agora.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }
}

// ── Vehicle Row ────────────────────────────────────────────────────────────
class _VehicleRow extends StatefulWidget {
  final Vehicle vehicle;
  final bool isHighlighted;
  final VoidCallback? onDelete;

  const _VehicleRow({
    required this.vehicle,
    required this.isHighlighted,
    required this.onDelete,
  });

  @override
  State<_VehicleRow> createState() => _VehicleRowState();
}

class _VehicleRowState extends State<_VehicleRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: widget.isHighlighted
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : _isHovered
              ? VeraProbColors.surfaceElevated
              : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                widget.vehicle.plate,
                style: VeraProbTypography.mono(
                  weight: FontWeight.w600,
                  size: 14,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                widget.vehicle.model ?? '—',
                style: const TextStyle(
                  fontSize: 14,
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                '${widget.vehicle.capacity} pax',
                style: const TextStyle(
                  fontSize: 14,
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: _VehicleStatusChip(status: widget.vehicle.status),
            ),
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: VeraProbColors.error,
                      ),
                      tooltip: 'Remover veículo',
                      onPressed: widget.onDelete,
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

// ── Status Chip ─────────────────────────────────────────────────────────────
class _VehicleStatusChip extends StatelessWidget {
  final VehicleStatus status;
  const _VehicleStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      VehicleStatus.available => ('Disponível', VeraProbColors.success),
      VehicleStatus.inService => ('Em Serviço', VeraProbColors.info),
      VehicleStatus.maintenance => ('Manutenção', VeraProbColors.warning),
      VehicleStatus.retired => ('Aposentado', VeraProbColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VeraProbRadii.pill),
      ),
      child: Text(
        label,
        style: _kChipText.copyWith(color: color),
        textAlign: TextAlign.center,
      ),
    );
  }
}
