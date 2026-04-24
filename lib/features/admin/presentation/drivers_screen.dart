import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/services/logger_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/features/admin/providers/drivers_provider.dart';
import 'widgets/driver_form_drawer.dart';
import 'widgets/telegram_binding_dialog.dart';

class DriversScreen extends ConsumerStatefulWidget {
  const DriversScreen({super.key});

  @override
  ConsumerState<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends ConsumerState<DriversScreen> {
  bool _isDrawerOpen = false;
  String? _highlightedDriverId;
  final _searchController = TextEditingController();

  void _openDrawer() {
    setState(() => _isDrawerOpen = true);
  }

  void _closeDrawer() {
    setState(() => _isDrawerOpen = false);
  }

  void _highlightDriver(String id) {
    setState(() => _highlightedDriverId = id);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightedDriverId = null);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredAsync = ref.watch(filteredDriversProvider);
    final userRole = ref.watch(currentUserRoleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Main content
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(context, colorScheme, userRole),
              const SizedBox(height: 24),
              // Search bar
              _buildSearchBar(context),
              const SizedBox(height: 20),
              // Drivers table
              Expanded(
                child: filteredAsync.when(
                  data: (drivers) => drivers.isEmpty
                      ? _buildEmptyState(context)
                      : _buildDriversTable(
                          context,
                          drivers,
                          colorScheme,
                          userRole,
                        ),
                  loading: () => _buildSkeletonLoading(),
                  error: (err, stack) {
                    LoggerService().error(
                      'Falha ao carregar motoristas',
                      error: err,
                      stackTrace: stack,
                    );
                    return _buildErrorState();
                  },
                ),
              ),
            ],
          ),
        ),
        // Drawer overlay
        if (_isDrawerOpen) ...[
          // Backdrop
          GestureDetector(
            onTap: () {}, // Prevent accidental close
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
          // Drawer panel
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: DriverFormDrawer(
              onClose: _closeDrawer,
              onDriverAdded: (id) {
                _closeDrawer();
                _highlightDriver(id);
                ref.invalidate(driversListProvider);
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
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.people_alt, size: 28, color: colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Motoristas da Frota',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cadastro administrativo dos motoristas vinculados à operação.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (userRole.hasPermission(UserRole.admin))
          FilledButton.icon(
            onPressed: _openDrawer,
            icon: const Icon(Icons.person_add_alt_1, size: 20),
            label: const Text('Cadastrar motorista'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return SizedBox(
      width: 400,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou CNH...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(driversSearchQueryProvider.notifier).state = '';
                  },
                )
              : null,
          isDense: true,
        ),
        onChanged: (value) {
          ref.read(driversSearchQueryProvider.notifier).state = value;
          setState(() {}); // Refresh clear button
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhum motorista cadastrado ainda.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Clique em "Cadastrar motorista" para começar.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'Não foi possível carregar os motoristas agora.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          SizedBox(height: 4),
          Text(
            'Tente novamente mais tarde.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Container(
                  width: 60,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriversTable(
    BuildContext context,
    List<Driver> drivers,
    ColorScheme colorScheme,
    UserRole userRole,
  ) {
    return Card(
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 52), // Avatar space
                Expanded(
                  flex: 3,
                  child: Text(
                    'NOME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'CNH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 116), // Actions space
              ],
            ),
          ),
          // Table rows
          Expanded(
            child: ListView.separated(
              itemCount: drivers.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final driver = drivers[index];
                final isHighlighted = _highlightedDriverId == driver.id;

                final orgId = ref.read(currentOrganizationIdProvider) ?? '';
                return _DriverRow(
                  driver: driver,
                  isHighlighted: isHighlighted,
                  organizationId: orgId,
                  onDelete: userRole.hasPermission(UserRole.admin)
                      ? () => _confirmDelete(context, driver)
                      : null,
                  onTelegramBind: userRole.hasPermission(UserRole.operator)
                      ? () => showDialog<void>(
                          context: context,
                          builder: (_) => TelegramBindingDialog(
                            driverId: driver.id,
                            driverName: driver.name,
                            organizationId: orgId,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Driver driver) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text('Deseja excluir o motorista ${driver.name} da frota?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(driverRepositoryProvider).deleteDriver(driver.id);
        ref.invalidate(driversListProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Motorista removido com sucesso.')),
          );
        }
      } catch (e, stack) {
        LoggerService().error(
          'Falha ao remover motorista',
          error: e,
          stackTrace: stack,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível remover o motorista agora. Tente novamente.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Driver Row Widget
// ---------------------------------------------------------------------------
class _DriverRow extends StatefulWidget {
  final Driver driver;
  final bool isHighlighted;
  final String organizationId;
  final VoidCallback? onDelete;
  final VoidCallback? onTelegramBind;

  const _DriverRow({
    required this.driver,
    required this.isHighlighted,
    required this.organizationId,
    required this.onDelete,
    required this.onTelegramBind,
  });

  @override
  State<_DriverRow> createState() => _DriverRowState();
}

class _DriverRowState extends State<_DriverRow> {
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
              ? Colors.grey.shade50
              : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                widget.driver.name[0].toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Name
            Expanded(
              flex: 3,
              child: Text(
                widget.driver.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            // CNH
            Expanded(
              flex: 2,
              child: Text(
                widget.driver.licenseNumber,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // Status chip
            SizedBox(
              width: 100,
              child: _StatusChip(status: widget.driver.status),
            ),
            // Actions
            SizedBox(
              width: 116,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onTelegramBind != null)
                    IconButton(
                      icon: const Icon(
                        Icons.telegram,
                        size: 20,
                        color: Color(0xFF0D47A1),
                      ),
                      tooltip: 'Vincular Telegram',
                      onPressed: widget.onTelegramBind,
                    ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red.shade400,
                      ),
                      tooltip: 'Remover motorista',
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

// ---------------------------------------------------------------------------
// Status Chip Widget
// ---------------------------------------------------------------------------
class _StatusChip extends StatelessWidget {
  final DriverStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bgColor) = switch (status) {
      DriverStatus.active => (
        'Ativo',
        const Color(0xFF1B5E20),
        const Color(0xFFE8F5E9),
      ),
      DriverStatus.inactive => (
        'Inativo',
        const Color(0xFF616161),
        const Color(0xFFF5F5F5),
      ),
      DriverStatus.pending => (
        'Pendente',
        const Color(0xFFE65100),
        const Color(0xFFFFF3E0),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
